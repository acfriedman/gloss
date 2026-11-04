import Foundation

/// The symbols the scanned sources declare, as a DocC link names them, so a link written in one file
/// can be checked against every file.
public struct SymbolIndex: Sendable {
    /// Every declaration's path from its outermost type, components joined by `/`, under its bare name
    /// and, for callables, under its signature too.
    private var paths: Set<String> = []
    /// The paths of declarations without a parameter list, which a link may still name with one, as
    /// it does an enum case with associated values.
    private var bare: Set<String> = []
    /// The scanned modules, which a link may start with.
    private var modules: Set<String> = []
    /// The modules the sources import, whose symbols a link may name though no scanned file declares them.
    private var imports: Set<String> = []
    /// Every name a declaration's path is made of, so a link's first name can be told from a module's.
    private var names: Set<String> = []

    /// Modules and types the scanned sources never declare, so a link or a dotted path under them names
    /// another module's symbol, not one of the project's. Extend it when a new framework's symbols start
    /// appearing in docs.
    public static let externalPrefixes: Set<String> = [
        "Swift", "Foundation", "Dispatch", "Combine", "XCTest", "Testing", "CoreData", "SwiftUI", "UIKit",
        "AppKit", "NotificationCenter", "DispatchQueue", "DispatchGroup", "DispatchTime", "Thread",
        "ProcessInfo", "FileManager", "URLSession", "URLProtocol", "URLRequest", "URL", "JSONEncoder",
        "JSONDecoder", "Date", "Data", "Task", "MainActor", "NSObject", "Bundle", "RunLoop", "Timer",
        "OperationQueue", "UserDefaults", "NSLock", "NSManagedObjectContext", "NSPersistentContainer",
        "String", "Array", "Dictionary", "Set", "Optional", "Result", "Int", "Double", "Bool", "Character",
        "StaticString", "Substring", "Float", "UInt", "UInt8", "Int8", "Int32", "UInt32", "Int64", "UInt64", "Never",
        "Error", "Sequence", "Collection", "Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Range",
        "ClosedRange", "CustomStringConvertible"
    ]

    /// Indexes every declaration read from the scanned files.
    ///
    /// - Parameters:
    ///   - readings: Each file's path and the declarations read from it.
    ///   - imports: The modules the files import, by their first names.
    public init(_ readings: [(file: String, entries: [DeclarationReader.Entry])], imports: [String] = []) {
        self.imports = Set(imports)
        for (file, entries) in readings {
            modules.insert(SourceFiles.module(of: file))
            for entry in entries where entry.declaration.kind != .other {
                // A link names a keyword-named declaration, such as ``Role/throws``, without its backticks.
                func path(_ last: String) -> String {
                    (entry.details.container + [last]).joined(separator: "/").replacingOccurrences(of: "`", with: "")
                }
                paths.insert(path(entry.declaration.name))
                names.formUnion(entry.details.container.map { $0.replacingOccurrences(of: "`", with: "") })
                names.insert(entry.declaration.name.replacingOccurrences(of: "`", with: ""))
                if entry.declaration.parameters == nil {
                    bare.insert(path(entry.declaration.name))
                } else {
                    paths.insert(path(entry.declaration.signature))
                }
            }
        }
    }

    /// Whether a link names something: a scanned declaration, reached from the scope it is written in
    /// and then outward as DocC resolves it; a scanned module; or a symbol of another module.
    ///
    /// - Parameters:
    ///   - link: The text between double backticks, such as `Cart/add(_:)`.
    ///   - scope: The types enclosing the comment, outermost first, including the documented type itself.
    /// - Returns: `false` only for a link into the scanned sources that matches nothing there.
    ///
    /// Another module's symbol is one under a module the sources import or a well-known one, whose
    /// declarations gloss cannot see. A first name that nothing scanned declares or imports is taken for
    /// the project's own module named another way, such as an Xcode target whose files gloss names by
    /// their folder, and the rest of the link must still name something.
    public func resolves(_ link: String, from scope: [String]) -> Bool {
        var components = link.split(separator: "/").map { Self.dropDisambiguation(String($0)) }
        if let first = components.first, modules.contains(first), !paths.contains(first) {
            components.removeFirst()
            if components.isEmpty { return true }
        }
        guard let first = components.first, !Self.externalPrefixes.contains(first), !imports.contains(first) else { return true }
        if declares(components, from: scope) { return true }
        return components.count > 1 && !names.contains(first) && declares(Array(components.dropFirst()), from: scope)
    }

    /// Whether a path names a scanned declaration, from the innermost scope outward.
    ///
    /// - Parameters:
    ///   - components: The link's names, disambiguation dropped, without a module.
    ///   - scope: The types enclosing the comment, outermost first.
    /// - Returns: `true` when some scope holds the path, or the type a synthesized member belongs to.
    private func declares(_ components: [String], from scope: [String]) -> Bool {
        for depth in stride(from: scope.count, through: 0, by: -1) {
            let candidate = (scope.prefix(depth) + components).joined(separator: "/")
            if paths.contains(candidate) { return true }
            if let open = candidate.lastIndex(of: "("), bare.contains(String(candidate[..<open])) { return true }
            // A conformance's synthesized member, such as `allCases`, is declared by no source.
            if components.count > 1, let last = components.last, Declaration.knownRequirements.contains(last),
               paths.contains((scope.prefix(depth) + components.dropLast()).joined(separator: "/")) {
                return true
            }
        }
        return false
    }

    /// Removes a DocC disambiguation suffix: a kind, as in `-swift.property`, or a hash, as in
    /// `parse(source:)-7tndx`, either of which tells overloads apart rather than naming the symbol.
    ///
    /// - Parameter component: One component of a link.
    /// - Returns: The component without its suffix.
    package static func dropDisambiguation(_ component: String) -> String {
        if let range = component.range(of: "-swift.") { return String(component[..<range.lowerBound]) }
        guard let dash = component.lastIndex(of: "-"), dash > component.startIndex else { return component }
        let hash = component[component.index(after: dash)...]
        let isHash = (3...6).contains(hash.count) && hash.allSatisfy { $0.isLowercase || $0.isNumber }
        return isHash ? String(component[..<dash]) : component
    }

    /// The double-backticked links in a comment, outside fenced code.
    ///
    /// - Parameter doc: A doc comment.
    /// - Returns: Each link's text and the source line it is on, in source order.
    public static func links(in doc: DocComment) -> [(text: String, line: Int)] {
        let code = doc.codeLines
        var links: [(text: String, line: Int)] = []
        for line in doc.lines where !code.contains(line.line) {
            var rest = Substring(line.text)
            while let open = rest.range(of: "``") {
                let after = rest[open.upperBound...]
                guard let close = after.range(of: "``") else { break }
                let text = after[..<close.lowerBound].trimmed
                if !text.isEmpty { links.append((text, line.line)) }
                rest = after[close.upperBound...]
            }
        }
        return links
    }
}

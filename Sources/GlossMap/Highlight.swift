import Foundation
import GlossRead
import GlossModel
import SwiftIDEUtils
import SwiftParser
import SwiftSyntax

/// Swift source split into runs an editor would color alike: keywords, types, literals, and the name
/// being declared.
///
/// Runs come from swift-syntax's own classification, so they follow the parser rather than a
/// pattern, and a type the scanned sources declare is told apart from one they only use.
public enum Highlight {
    /// What a run of source is.
    public enum Kind: Sendable, Equatable {
        /// Identifiers, operators, punctuation, and whitespace: what an editor leaves uncolored.
        case plain
        /// A keyword, such as `func`, `public`, or `let`.
        case keyword
        /// An attribute's `@` and name, such as `@MainActor`, without its arguments.
        case attribute
        /// A string or regex literal.
        case string
        /// An integer or floating-point literal.
        case number
        /// A comment of any form, doc comments included.
        case comment
        /// A type no scanned source declares, such as `String`.
        case type
        /// A type a scanned source declares.
        case projectType
        /// The name the declaration introduces.
        case declaration
    }

    /// One stretch of source with one kind.
    public struct Run: Sendable, Equatable {
        /// The source as written, whitespace included; the runs in order spell the code exactly.
        public var text: String
        /// What the run is, which decides its color; neighboring runs always differ, since runs of one
        /// kind merge.
        public var kind: Kind
    }

    /// Splits source into runs.
    ///
    /// - Parameters:
    ///   - code: Swift source. A declaration without its body parses with recovery and colors the same.
    ///   - projectTypes: Type names the scanned sources declare, each path component on its own.
    /// - Returns: Runs that together spell `code` exactly, with neighbors of one kind merged.
    public static func runs(_ code: String, projectTypes: Set<String> = []) -> [Run] {
        // A page draws its declarations again each time it shows, and parsing one is the slow part.
        let key = code + "\u{0}" + projectTypes.sorted().joined(separator: ",")
        if let cached = cache.runs(for: key) { return cached }
        let runs = parsedRuns(code, projectTypes: projectTypes)
        cache.store(runs, for: key)
        return runs
    }

    /// The runs already worked out, by source and project types.
    private static let cache = RunCache()

    /// Works out the runs of many contracts ahead of time, on every core, so pages that show them later
    /// draw from the cache rather than parsing while the reader waits.
    ///
    /// - Parameter contracts: The contracts, such as every one in an interface.
    public static func warm(_ contracts: [Contract]) {
        let phase = Timing.begin("warm highlighting"); defer { Timing.end(phase, "\(contracts.count) declarations") }
        let chunk = 256
        DispatchQueue.concurrentPerform(iterations: (contracts.count + chunk - 1) / chunk) { part in
            for contract in contracts[(part * chunk)..<min(contracts.count, (part + 1) * chunk)] { _ = runs(of: contract) }
        }
    }

    /// Splits source into runs by parsing it, which ``runs(_:projectTypes:)`` does once per source.
    ///
    /// - Parameters:
    ///   - code: Swift source.
    ///   - projectTypes: Type names the scanned sources declare, each path component on its own.
    /// - Returns: The runs.
    private static func parsedRuns(_ code: String, projectTypes: Set<String>) -> [Run] {
        let tree = Parser.parse(source: code)
        let declared = declaredNames(in: tree)
        var runs: [Run] = []
        func add(_ text: String, _ kind: Kind) {
            guard !text.isEmpty else { return }
            if let last = runs.last, last.kind == kind {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: text, kind: kind))
            }
        }
        func add(_ trivia: Trivia) {
            for piece in trivia {
                var text = ""
                piece.write(to: &text)
                switch piece {
                case .lineComment, .blockComment, .docLineComment, .docBlockComment: add(text, .comment)
                default: add(text, .plain)
                }
            }
        }
        for token in tree.tokens(viewMode: .sourceAccurate) {
            add(token.leadingTrivia)
            let text = token.text
            let kind: Kind = if declared.contains(token.positionAfterSkippingLeadingTrivia) {
                .declaration
            } else if isAttributeName(token) {
                .attribute
            } else {
                switch token.tokenClassification.kind {
                case .keyword: .keyword
                case .attribute: .attribute
                case .stringLiteral, .regexLiteral: .string
                case .integerLiteral, .floatLiteral: .number
                case .lineComment, .blockComment, .docLineComment, .docBlockComment: .comment
                case .type: projectTypes.contains(text) ? .projectType : .type
                default: .plain
                }
            }
            add(text, kind)
            add(token.trailingTrivia)
        }
        return runs
    }

    /// Splits one contract's declaration into runs, with the types it resolves to scanned sources marked.
    ///
    /// - Parameter contract: A contract whose mentions are resolved, as every contract in an
    ///   ``GlossModel/Interface`` is.
    /// - Returns: Runs that together spell the declaration exactly.
    public static func runs(of contract: Contract) -> [Run] {
        let names = contract.mentions.filter { $0.resolved != nil }.flatMap { $0.name.split(separator: ".").map(String.init) }
        return runs(contract.declaration, projectTypes: Set(names))
    }

    /// Whether a token spells an attribute's name, such as `MainActor` in `@MainActor`, which the
    /// classifier reads as a type but an editor colors with its `@`.
    ///
    /// - Parameter token: Any token of the parsed source.
    /// - Returns: `true` when the token is part of an attribute's name, not its arguments.
    private static func isAttributeName(_ token: TokenSyntax) -> Bool {
        var node = Syntax(token)
        while let parent = node.parent {
            if parent.is(AttributeSyntax.self) { return node.keyPathInParent == \AttributeSyntax.attributeName }
            node = parent
        }
        return false
    }

    /// Where the names a source's first declaration introduces begin.
    ///
    /// - Parameter tree: The parsed source.
    /// - Returns: The position of each declared name: a type's, a function's, each variable's, and
    ///   each enum case's; empty when the source opens with no declaration or with an initializer.
    private static func declaredNames(in tree: SourceFileSyntax) -> Set<AbsolutePosition> {
        guard let declaration = tree.statements.first?.item.as(DeclSyntax.self) else { return [] }
        var names: [TokenSyntax] = []
        if let named = declaration.asProtocol(NamedDeclSyntax.self) {
            names.append(named.name)
        } else if let variable = declaration.as(VariableDeclSyntax.self) {
            names += variable.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier }
        } else if let cases = declaration.as(EnumCaseDeclSyntax.self) {
            names += cases.elements.map(\.name)
        }
        return Set(names.map(\.positionAfterSkippingLeadingTrivia))
    }
}

/// The runs ``Highlight`` has worked out, shared across threads. It holds at most ``limit`` sources and
/// starts over when full, since an interface's declarations number in the tens of thousands at most.
private final class RunCache: @unchecked Sendable {
    /// The most sources kept.
    private static let limit = 100_000
    private let lock = NSLock()
    private var runs: [String: [Highlight.Run]] = [:]

    /// The runs kept for a key.
    ///
    /// - Parameter key: The source and its project types.
    /// - Returns: The runs, or `nil` when none are kept.
    func runs(for key: String) -> [Highlight.Run]? {
        lock.withLock { runs[key] }
    }

    /// Keeps the runs for a key.
    ///
    /// - Parameters:
    ///   - runs: The runs.
    ///   - key: The source and its project types.
    func store(_ runs: [Highlight.Run], for key: String) {
        lock.withLock {
            if self.runs.count >= Self.limit { self.runs.removeAll() }
            self.runs[key] = runs
        }
    }
}

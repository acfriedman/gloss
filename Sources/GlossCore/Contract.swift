/// What one declaration promises: its signature as written, and the doc comment read as a contract.
///
/// This is the record the interface view renders and the JSON export carries. A view may only show
/// what is in here, so anything worth seeing becomes a field first.
public struct Contract: Sendable, Equatable, Codable {
    /// One parameter with its type as written and the doc entry that describes it.
    public struct Parameter: Sendable, Equatable, Codable {
        public var label: String?
        public var name: String
        public var type: String
        public var hasDefault: Bool
        public var doc: String?
    }

    /// One callout outside the parameter, returns, and throws entries, such as `- Note:`.
    public struct Callout: Sendable, Equatable, Codable {
        public var keyword: String
        public var text: String
    }

    /// A type name the declaration mentions, and where: in its signature or in its body.
    ///
    /// Mentions are what the dependency graph is drawn from. The name is kept as written; `resolved` is
    /// the graph node it names, or `nil` when no scanned source declares it.
    public struct Mention: Sendable, Equatable, Codable {
        /// Where a mention appears, which says how the declaration depends on the type.
        public enum Role: String, Sendable, Codable, CaseIterable {
            /// In an inheritance clause: the type conforms to it or inherits from it.
            case conformance
            /// In a property's type, or in an unannotated property's initial value.
            case property
            /// In a parameter's type.
            case parameter
            /// In the return type.
            case returns
            /// In a typed `throws(E)` clause.
            case `throws`
            /// Anywhere in a body: implementation, not interface.
            case body
        }

        public var name: String
        public var role: Role
        public var resolved: String?
    }

    /// One rule finding, addressed by line so the view can place it next to the contract it breaks.
    public struct Finding: Sendable, Equatable, Codable {
        public var rule: String
        public var line: Int
        public var message: String
    }

    public var module: String
    public var kind: Declaration.Kind
    /// The introducing keyword as written: `func`, `init`, `var`, `struct`, `protocol`, and so on.
    public var keyword: String
    public var name: String
    /// The enclosing types and extended types, outermost first; empty at file scope.
    public var container: [String]
    /// The effective access level: `open`, `public`, `package`, `internal`, `fileprivate`, or `private`.
    public var access: String
    /// The declaration as written, without its body, doc comment, or stored-property initializer.
    public var declaration: String
    public var parameters: [Parameter]
    /// The return type as written, or `nil` for `Void` callables and for non-callables.
    public var returnType: String?
    /// The `throws`, `throws(E)`, or `rethrows` clause as written, or `nil` when the callable does not throw.
    public var throwsClause: String?
    public var isAsync: Bool
    public var isDocumented: Bool
    public var requiresDoc: Bool
    public var summary: String?
    public var returns: String?
    public var throwsDoc: String?
    public var callouts: [Callout]
    /// The prose paragraphs below the markup block.
    public var notes: [String]
    /// Why the declaration is excused from the harness, in words, or `nil` when it is not.
    public var exemption: String?
    public var findings: [Finding]
    public var mentions: [Mention]
    public var file: String
    public var line: Int

    /// The container path and name joined with dots, which is how a reader names the symbol.
    public var qualifiedName: String { (container + [name]).joined(separator: ".") }

    /// Whether the declaration is a type that holds members: a struct, class, enum, actor, or protocol.
    public var opensScope: Bool { ["struct", "class", "enum", "actor", "protocol"].contains(keyword) }

    /// Orders access levels so a view can show everything at or above a threshold.
    ///
    /// - Parameter access: An access keyword.
    /// - Returns: 3 for `open` and `public`, 2 for `package`, 1 for `internal`, 0 for the private levels.
    public static func rank(_ access: String) -> Int {
        switch access {
        case "open", "public": 3
        case "package": 2
        case "internal": 1
        default: 0
        }
    }

    /// Joins a syntactic declaration and its doc comment into one contract. The doc is read with the
    /// same parser the rules use, so the view and the harness can never disagree about a comment.
    ///
    /// - Parameters:
    ///   - declaration: What the rules know about the declaration.
    ///   - doc: Its doc comment, or `nil` when it has none.
    ///   - facts: The syntax-only details the rules do not need: types, effects, access, and header text.
    ///   - findings: The rule findings for this declaration.
    /// - Returns: The contract, with `module` left empty for ``Interface/build(sources:)`` to fill in.
    static func make(_ declaration: Declaration, doc: DocComment?, facts: Facts, findings: [Diagnostic]) -> Contract {
        let structure = doc.map(DocStructure.parse)
        let callouts = structure?.callouts ?? []
        let entries = callouts.filter { $0.normalizedKeyword == "parameters" }.flatMap(\.entries).map { ($0.name, $0.text) }
            + callouts.filter { $0.normalizedKeyword == "parameter" }.compactMap { callout in callout.argument.map { ($0, callout.text) } }
        let parameters = zip(declaration.parameters ?? [], facts.parameterTypes).map { parameter, type in
            Parameter(label: parameter.label, name: parameter.name, type: type.type, hasDefault: type.hasDefault,
                      doc: entries.first { parameter.matches($0.0) }.map(\.1))
        }
        let markup: Set<String> = ["parameters", "parameter", "returns", "throws"]
        return Contract(
            module: "",
            kind: declaration.kind,
            keyword: facts.keyword,
            name: declaration.name,
            container: facts.container,
            access: facts.access,
            declaration: facts.header,
            parameters: parameters,
            returnType: declaration.returnsValue ? facts.returnType : nil,
            throwsClause: facts.throwsClause,
            isAsync: facts.isAsync,
            isDocumented: doc != nil,
            requiresDoc: declaration.requiresDoc,
            summary: structure.flatMap { $0.summary.isEmpty ? nil : $0.summary.map(\.text).joined(separator: " ").trimmed },
            returns: callouts.first { $0.normalizedKeyword == "returns" }?.text,
            throwsDoc: callouts.first { $0.normalizedKeyword == "throws" }?.text,
            callouts: callouts.filter { !markup.contains($0.normalizedKeyword) }.map { Callout(keyword: $0.keyword, text: $0.text) },
            notes: Self.paragraphs(structure?.notes ?? []),
            exemption: declaration.exemption.map(Self.describe),
            findings: findings.map { Finding(rule: $0.rule.rawValue, line: $0.line, message: $0.message) },
            mentions: facts.mentions,
            file: declaration.file,
            line: declaration.line
        )
    }

    /// Groups note lines into paragraphs: consecutive source lines join with a space, and a gap in line
    /// numbers, which is where a blank `///` line was, starts a new paragraph.
    ///
    /// - Parameter lines: The note lines in source order.
    /// - Returns: One string per paragraph.
    static func paragraphs(_ lines: [DocLine]) -> [String] {
        var paragraphs: [String] = []
        var previous = Int.min
        for line in lines {
            if line.line == previous + 1, let last = paragraphs.popLast() {
                paragraphs.append(last + " " + line.text.trimmed)
            } else {
                paragraphs.append(line.text.trimmed)
            }
            previous = line.line
        }
        return paragraphs
    }

    /// Words a reader can act on for each exemption, so the view never shows an enum case name.
    ///
    /// - Parameter exemption: The reason the harness excused the declaration.
    /// - Returns: A short phrase; a marker's own reason is passed through.
    static func describe(_ exemption: Declaration.Exemption) -> String {
        switch exemption {
        case .knownRequirement: "Known protocol requirement"
        case .conformanceExtension: "In a conformance extension"
        case .marker(let reason): reason.isBlank ? "Marked exempt, no reason given" : reason
        case .memberwiseInit: "Memberwise initializer"
        }
    }

    /// The details of a declaration that only the syntax tree knows and only the contract needs.
    struct Facts {
        var keyword: String
        var mentions: [Mention]
        var container: [String]
        var access: String
        var header: String
        var parameterTypes: [(type: String, hasDefault: Bool)]
        var returnType: String?
        var throwsClause: String?
        var isAsync: Bool
    }
}

/// Every contract found under a set of paths, grouped by module: the interface as one document.
///
/// The JSON form is the stable surface for other tools; ``InterfacePage`` renders the same value.
public struct Interface: Sendable, Equatable, Codable {
    /// The version of this JSON shape. It changes only when a field is removed or changes meaning.
    public var schema = 1
    public var files: [String]
    public var contracts: [Contract]
    public var graph: Graph

    /// Reads every source and collects its contracts in file order, then source order.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents.
    /// - Returns: The interface, with each contract's module named from its path and its mentions resolved.
    public static func build(sources: [(file: String, source: String)]) -> Interface {
        var contracts: [Contract] = []
        for (file, source) in sources {
            let module = Self.module(of: file)
            contracts += Checker.contracts(source: source, file: file).map { contract in
                var contract = contract
                contract.module = module
                return contract
            }
        }
        let graph = Graph.build(&contracts)
        return Interface(files: sources.map(\.file), contracts: contracts, graph: graph)
    }

    /// Names the module a file belongs to by the SwiftPM layout: the directory right under `Sources`
    /// or `Tests`. Outside that layout the file's own directory stands in, which is right for most
    /// Xcode projects and harmless for the rest.
    ///
    /// - Parameter file: The path as given.
    /// - Returns: The module name, or `Module` for a bare file name.
    public static func module(of file: String) -> String {
        let parts = file.split(separator: "/").map(String.init)
        if let root = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }), root + 2 < parts.count {
            return parts[root + 1]
        }
        return parts.count >= 2 ? parts[parts.count - 2] : "Module"
    }
}

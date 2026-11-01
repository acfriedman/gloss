/// What one declaration promises: its signature as written, and the doc comment read as a contract.
///
/// This is the record the interface view renders and the JSON export carries. It says nothing about
/// whether the doc follows the rules; that is the ``Assessment`` the ``Linter`` makes beside it.
public struct Contract: Sendable, Equatable, Codable {
    /// One parameter with its type as written and the doc entry that describes it.
    public struct Parameter: Sendable, Equatable, Codable {
        /// The external argument label, or `nil` for `_`.
        public var label: String?
        /// The internal name; the same as the label when the signature gives only one.
        public var name: String
        /// The type as written, with the `...` of a variadic parameter kept.
        public var type: String
        /// `true` when the signature gives the parameter a default value.
        public var hasDefault: Bool
        /// The text of the doc entry that names this parameter by label or internal name, or `nil` when none
        /// does.
        public var doc: String?
    }

    /// One callout outside the parameter, returns, and throws entries, such as `- Note:`.
    public struct Callout: Sendable, Equatable, Codable {
        /// The keyword as written, such as `Note` or `Important`.
        public var keyword: String
        /// The text after the colon, with continuation lines joined by spaces.
        public var text: String
    }

    /// The module the declaration belongs to, named from its path by ``Interface/module(of:)``.
    public var module: String
    /// The syntactic category, which decides which rules apply to the declaration.
    public var kind: Declaration.Kind
    /// The introducing keyword as written: `func`, `init`, `var`, `struct`, `protocol`, and so on.
    public var keyword: String
    /// The base name: `init` for initializers, `subscript` for subscripts, and the first name when one `var`
    /// or `case` declares several.
    public var name: String
    /// The enclosing types and extended types, outermost first; empty at file scope.
    public var container: [String]
    /// The effective access level: `open`, `public`, `package`, `internal`, `fileprivate`, or `private`.
    public var access: String
    /// The declaration as written, without its body or doc comment, and without a stored property's
    /// initial value when the property has a type annotation.
    public var declaration: String
    /// The parameters in signature order; empty for a declaration that takes none or is not callable.
    public var parameters: [Parameter]
    /// The return type as written, or `nil` for `Void` callables and for non-callables.
    public var returnType: String?
    /// A property's type annotation as written, or `nil` when it has none or is not a property.
    public var valueType: String?
    /// The `throws`, `throws(E)`, or `rethrows` clause as written, or `nil` when the callable does not throw.
    public var throwsClause: String?
    /// `true` for an `async` function or initializer.
    public var isAsync: Bool
    /// `true` for an `override`, whose contract is the inherited one.
    public var isOverride: Bool
    /// `true` when a doc comment is attached, including a `/** */` one whose text is never read.
    public var isDocumented: Bool
    /// The summary paragraph on one line, or `nil` when there is no comment or it opens with a blank line or
    /// a callout.
    public var summary: String?
    /// The text of the `- Returns:` entry, or `nil` when there is none.
    public var returns: String?
    /// The text of the `- Throws:` entry, or `nil` when there is none.
    public var throwsDoc: String?
    /// The callouts other than the parameter, returns, and throws entries, in source order.
    public var callouts: [Callout]
    /// The prose paragraphs below the markup block.
    public var notes: [String]
    /// The type names the declaration mentions, by role; ``Graph/build(_:)`` resolves each to its node.
    public var mentions: [Mention]
    /// The path the declaration was read from, as reported.
    public var file: String
    /// The 1-based source line of the declaration, as its diagnostics report it.
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

    /// Builds the contract of one declaration as read. The doc is parsed with the same parser the rules
    /// use, so the contract and the lint can never disagree about a comment.
    ///
    /// - Parameter entry: The declaration, its doc comment, and its details, from ``DeclarationReader``.
    /// - Returns: The contract, with `module` left empty for ``Interface/build(sources:)`` to fill in.
    static func make(_ entry: DeclarationReader.Entry) -> Contract {
        let (declaration, doc, facts) = (entry.declaration, entry.doc, entry.details)
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
            valueType: facts.valueType,
            throwsClause: facts.throwsClause,
            isAsync: facts.isAsync,
            isOverride: declaration.isOverride,
            isDocumented: doc != nil,
            summary: structure.flatMap { $0.summary.isEmpty ? nil : $0.summary.map(\.text).joined(separator: " ").trimmed },
            returns: callouts.first { $0.normalizedKeyword == "returns" }?.text,
            throwsDoc: callouts.first { $0.normalizedKeyword == "throws" }?.text,
            callouts: callouts.filter { !markup.contains($0.normalizedKeyword) }.map { Callout(keyword: $0.keyword, text: $0.text) },
            notes: Self.paragraphs(structure?.notes ?? []),
            mentions: facts.mentions,
            file: declaration.file,
            line: declaration.line
        )
    }

    /// Groups note lines into paragraphs: consecutive source lines join with a space, and a gap in line
    /// numbers, which is where a blank `///` line was, starts a new paragraph. Fenced code is one
    /// paragraph of its own, its fences included and its lines joined by newlines as written.
    ///
    /// - Parameter lines: The note lines in source order.
    /// - Returns: One string per paragraph; a code paragraph starts with its opening fence.
    static func paragraphs(_ lines: [DocLine]) -> [String] {
        var paragraphs: [String] = []
        var previous = Int.min
        let code = DocComment(lines: lines).codeLines
        var openCode = false
        for line in lines {
            if code.contains(line.line) {
                if openCode {
                    paragraphs[paragraphs.count - 1] += "\n" + line.text
                    if line.text.trimmed.hasPrefix("```") { openCode = false }
                } else {
                    paragraphs.append(line.text.trimmed)
                    openCode = true
                }
            } else if line.line == previous + 1, let last = paragraphs.last, !last.hasPrefix("```") {
                paragraphs[paragraphs.count - 1] = last + " " + line.text.trimmed
            } else {
                paragraphs.append(line.text.trimmed)
            }
            previous = line.line
        }
        return paragraphs
    }
}

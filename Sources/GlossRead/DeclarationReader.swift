import Foundation
import SwiftParser
import SwiftSyntax

/// Reads every declaration in one Swift file, with its doc comment and what its syntax says about it.
///
/// Reading is the one pass over the syntax tree. What it produces feeds two consumers that never meet
/// here: GlossLint checks the doc comments against its rules, and GlossModel builds the contract
/// model and its dependency graph.
public final class DeclarationReader: SyntaxVisitor {
    /// One declaration as read: what the rules need, its doc comment, and what the model needs.
    public struct Entry: Sendable {
        /// What the rules check: kind, name, exemption, signature facts, and position.
        public var declaration: Declaration
        /// The doc comment directly above the declaration, or `nil` when it has none.
        public var doc: DocComment?
        /// What the contract model needs beyond what the rules check.
        public var details: Details
    }

    /// What the syntax says about a declaration beyond what the rules need: its kind, scope, access,
    /// header, types, effects, and the type names it mentions.
    public struct Details: Sendable {
        /// The introducing keyword as ``Header/keyword(of:)`` reads it, or `code` for top-level code.
        public var keyword: String
        /// The type names the declaration mentions, each tagged with where it appears; unresolved until
        /// the contract model builds its graph.
        public var mentions: [Mention]
        /// The enclosing types and extended types, outermost first; empty at file scope.
        public var container: [String]
        /// The effective access level, an implicit one taken from the enclosing extension, protocol, or enum,
        /// else `internal`, or `private` inside a private scope.
        public var access: String
        /// The one-line declaration from ``Header/text(of:)``, which the contract shows as written.
        public var header: String
        /// Each parameter's type as written, a variadic's `...` included, and whether it has a default, in
        /// signature order.
        public var parameterTypes: [(type: String, hasDefault: Bool)]
        /// The return type as written, `Void` included, or `nil` when the signature has no return clause.
        public var returnType: String?
        /// A property's type annotation as written, or `nil` when it has none or is not a property.
        public var valueType: String?
        /// The `throws`, `throws(E)`, or `rethrows` clause of a function or initializer as written, or `nil`
        /// when it has none.
        public var throwsClause: String?
        /// `true` when a function or initializer is declared `async`.
        public var isAsync: Bool
        /// A fingerprint of the body, as ``DeclarationReader/fingerprint(of:)`` takes it, or `nil` for a
        /// declaration without one.
        public var bodyFingerprint: String?
        /// The lines the declaration takes, its doc comment's first through its last; a type's stop at
        /// the brace that opens its members, which are declarations of their own.
        public var lines: ClosedRange<Int>
    }

    private let file: String
    private let converter: SourceLocationConverter
    private var entries: [Entry] = []
    private var conformanceDepth = 0
    private var privateDepth = 0
    private var scopes: [Scope] = []
    /// Whether the file has top-level statements, which makes its top-level variables the entry point's.
    private var isScript = false

    /// One enclosing type or extension: its name and the access its members take when they name none.
    private struct Scope {
        var name: String
        /// The access members default to: an extension's own modifier, or a protocol's access for its
        /// requirements; `nil` means `internal`.
        var memberAccess: String?
        /// The access an enum's cases share, which is the enum's own.
        var caseAccess: String?
    }

    private static let accessLevels: Set<String> = ["open", "public", "package", "internal", "fileprivate", "private"]

    /// Reads the source text of one file. Parsing happens here so callers hand over text, not trees.
    ///
    /// - Parameters:
    ///   - source: The file's contents.
    ///   - file: The path every entry reports.
    /// - Returns: Every declaration in source order, private ones included, and the file's top-level
    ///   statements as one `top-level code` entry first when it has any.
    public static func read(source: String, file: String) -> [Entry] {
        let tree = Parser.parse(source: source)
        let reader = DeclarationReader(file: file, converter: SourceLocationConverter(fileName: file, tree: tree))
        reader.walk(tree)
        return reader.entries
    }

    private init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause != nil { conformanceDepth += 1 }
        if Self.isPrivate(node.modifiers) { privateDepth += 1 }
        scopes.append(Scope(name: node.extendedType.trimmedDescription, memberAccess: Self.explicitAccess(node.modifiers)))
        return .visitChildren
    }

    override public func visitPost(_ node: ExtensionDeclSyntax) {
        if node.inheritanceClause != nil { conformanceDepth -= 1 }
        if Self.isPrivate(node.modifiers) { privateDepth -= 1 }
        scopes.removeLast()
    }

    // A script's top-level statements are its entry point. They are not declarations, so they are kept
    // as one `top-level code` entry that carries their mentions into the graph; no rule applies to it.
    // A script's top-level variables are the entry point's locals, so they join it rather than standing
    // as declarations that would need docs.
    override public func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        guard node.statements.contains(where: { !$0.item.is(DeclSyntax.self) }) else { return .visitChildren }
        isScript = true
        let statements = node.statements.filter { !$0.item.is(DeclSyntax.self) || $0.item.is(VariableDeclSyntax.self) }
        guard let first = statements.first else { return .visitChildren }
        var mentions: [Mention] = []
        for statement in statements {
            for name in Mentions.names(in: statement) where !mentions.contains(where: { $0.name == name }) {
                mentions.append(Mention(name: name, role: .body))
            }
        }
        let line = converter.location(for: first.positionAfterSkippingLeadingTrivia).line
        let declaration = Declaration(kind: .other, name: "top-level code", file: file, line: line, column: 1)
        let details = Details(keyword: "code", mentions: mentions, container: [], access: "internal",
                              header: "top-level code", parameterTypes: [], returnType: nil, valueType: nil, throwsClause: nil, isAsync: false,
                              bodyFingerprint: Self.fingerprint(of: statements.map(Syntax.init)),
                              lines: line...max(line, converter.location(for: (statements.last ?? first).endPositionBeforeTrailingTrivia).line))
        entries.append(Entry(declaration: declaration, doc: nil, details: details))
        return .visitChildren
    }

    override public func visitPost(_ node: ClassDeclSyntax) { leaveType(node.modifiers) }
    override public func visitPost(_ node: StructDeclSyntax) { leaveType(node.modifiers) }
    override public func visitPost(_ node: EnumDeclSyntax) { leaveType(node.modifiers) }
    override public func visitPost(_ node: ActorDeclSyntax) { leaveType(node.modifiers) }
    override public func visitPost(_ node: ProtocolDeclSyntax) { leaveType(node.modifiers) }

    // Local declarations inside bodies are not API; skip them wholesale.
    override public func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        guard name.first?.isLetter == true || name.first == "_" else { return .skipChildren }
        record(node, kind: .function, name: name, at: node.name,
               parameters: node.signature.parameterClause.parameters,
               returnType: node.signature.returnClause?.type,
               throwsErrors: node.signature.effectSpecifiers?.throwsClause != nil,
               modifiers: node.modifiers,
               effects: node.signature.effectSpecifiers)
        return .skipChildren
    }

    override public func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: .function, name: node.name.text, at: node.name,
               parameters: node.signature.parameterClause.parameters,
               returnType: node.signature.returnClause?.type,
               throwsErrors: false,
               modifiers: node.modifiers)
        return .skipChildren
    }

    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: .initializer, name: "init", at: node.initKeyword,
               parameters: node.signature.parameterClause.parameters,
               returnType: nil,
               throwsErrors: node.signature.effectSpecifiers?.throwsClause != nil,
               modifiers: node.modifiers,
               effects: node.signature.effectSpecifiers,
               isMemberwise: Self.isMemberwise(node))
        return .skipChildren
    }

    /// Whether an initializer's body is nothing but `self.x = x` for its own parameters, the shape the
    /// compiler would have synthesized. Any other statement, default, or expression makes it a real
    /// initializer with a contract of its own.
    ///
    /// - Parameter node: The initializer.
    /// - Returns: `true` for a non-empty body of bare parameter-to-property assignments.
    static func isMemberwise(_ node: InitializerDeclSyntax) -> Bool {
        guard let statements = node.body?.statements, !statements.isEmpty else { return false }
        let parameters = Set(node.signature.parameterClause.parameters.map { ($0.secondName ?? $0.firstName).text })
        return statements.allSatisfy { statement in
            guard let (target, source) = Self.assignment(statement.item),
                  target.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
            else { return false }
            return parameters.contains(source.baseName.text)
        }
    }

    /// Reads `lhs = rhs` from a statement, whether the parser left it as an unfolded sequence (its
    /// default) or an operator table already folded it.
    ///
    /// - Parameter item: The statement.
    /// - Returns: The member being assigned and the bare name assigned to it, or `nil` for any other shape.
    private static func assignment(_ item: CodeBlockItemSyntax.Item) -> (MemberAccessExprSyntax, DeclReferenceExprSyntax)? {
        if let folded = item.as(InfixOperatorExprSyntax.self), folded.operator.is(AssignmentExprSyntax.self),
           let target = folded.leftOperand.as(MemberAccessExprSyntax.self),
           let source = folded.rightOperand.as(DeclReferenceExprSyntax.self) {
            return (target, source)
        }
        guard let sequence = item.as(SequenceExprSyntax.self) else { return nil }
        let parts = Array(sequence.elements)
        guard parts.count == 3, parts[1].is(AssignmentExprSyntax.self),
              let target = parts[0].as(MemberAccessExprSyntax.self),
              let source = parts[2].as(DeclReferenceExprSyntax.self)
        else { return nil }
        return (target, source)
    }

    override public func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: .subscript, name: "subscript", at: node.subscriptKeyword,
               parameters: node.parameterClause.parameters,
               returnType: node.returnClause.type,
               throwsErrors: false,
               modifiers: node.modifiers)
        return .skipChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }
    override public func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind { type(node, node.name, node.modifiers) }

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isScript, scopes.isEmpty { return .skipChildren }
        let name = node.bindings.first?.pattern.trimmedDescription ?? "property"
        record(node, kind: .property, name: name, at: node.bindingSpecifier, parameters: nil, returnType: nil,
               throwsErrors: false, modifiers: node.modifiers)
        return .skipChildren
    }

    override public func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.elements.first?.name.text ?? "case"
        record(node, kind: .enumCase, name: name, at: node.caseKeyword, parameters: nil, returnType: nil,
               throwsErrors: false, modifiers: node.modifiers)
        return .skipChildren
    }

    private func type(_ node: some DeclSyntaxProtocol, _ nameToken: TokenSyntax, _ modifiers: DeclModifierListSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: .type, name: nameToken.text, at: nameToken, parameters: nil, returnType: nil,
               throwsErrors: false, modifiers: modifiers)
        guard !node.is(TypeAliasDeclSyntax.self), !node.is(AssociatedTypeDeclSyntax.self) else { return .visitChildren }
        if Self.isPrivate(modifiers) { privateDepth += 1 }
        let access = effectiveAccess(modifiers, kind: .type)
        scopes.append(Scope(name: nameToken.text,
                            memberAccess: node.is(ProtocolDeclSyntax.self) ? access : nil,
                            caseAccess: node.is(EnumDeclSyntax.self) ? access : nil))
        return .visitChildren
    }

    // Typealiases and associated types have no members, so only the five container kinds balance
    // `privateDepth` and `scopes`.
    private func leaveType(_ modifiers: DeclModifierListSyntax) {
        if Self.isPrivate(modifiers) { privateDepth -= 1 }
        scopes.removeLast()
    }

    private static func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { ($0.name.text == "private" || $0.name.text == "fileprivate") && $0.detail == nil }
    }

    // `private(set)` and its kin narrow only the setter, so a modifier with a detail is not the access level.
    private static func explicitAccess(_ modifiers: DeclModifierListSyntax) -> String? {
        modifiers.first { accessLevels.contains($0.name.text) && $0.detail == nil }?.name.text
    }

    private func effectiveAccess(_ modifiers: DeclModifierListSyntax, kind: Declaration.Kind) -> String {
        if let explicit = Self.explicitAccess(modifiers) { return explicit }
        if kind == .enumCase, let access = scopes.last?.caseAccess { return access }
        if let access = scopes.last?.memberAccess { return access }
        return privateDepth > 0 ? "private" : "internal"
    }

    private func record(
        _ node: some DeclSyntaxProtocol,
        kind: Declaration.Kind,
        name: String,
        at anchor: TokenSyntax,
        parameters: FunctionParameterListSyntax?,
        returnType: TypeSyntax?,
        throwsErrors: Bool,
        modifiers: DeclModifierListSyntax,
        effects: FunctionEffectSpecifiersSyntax? = nil,
        isMemberwise: Bool = false
    ) {
        let location = converter.location(for: anchor.positionAfterSkippingLeadingTrivia)
        let doc = DocComment.leading(node, converter: converter)
        let names = modifiers.map(\.name.text)
        var declaration = Declaration(
            kind: kind,
            name: name,
            parameters: parameters.map { list in
                list.map { param in
                    let label = param.firstName.text
                    let internalName = param.secondName?.text ?? label
                    return Declaration.Parameter(label: label == "_" ? nil : label, name: internalName == "_" ? label : internalName)
                }
            },
            returnsValue: returnType.map { !Self.isVoid($0) } ?? false,
            throwsErrors: throwsErrors,
            isPrivate: Self.isPrivate(modifiers) || privateDepth > 0,
            isOverride: names.contains("override"),
            file: file,
            line: location.line,
            column: location.column
        )
        if let reason = Self.exemptMarker(in: node.leadingTrivia) {
            declaration.exemption = .marker(reason: reason)
        } else if Declaration.knownRequirements.contains(declaration.signature)
                    || (kind == .enumCase && scopes.last?.name == "CodingKeys") {
            declaration.exemption = .knownRequirement
        } else if conformanceDepth > 0 {
            declaration.exemption = .conformanceExtension
        } else if isMemberwise {
            declaration.exemption = .memberwiseInit
        }
        let access = effectiveAccess(modifiers, kind: kind)
        declaration.access = access
        let details = Details(
            keyword: Header.keyword(of: node),
            mentions: Mentions.collect(node, parameters: parameters, returnType: returnType, effects: effects),
            container: scopes.map(\.name),
            access: access,
            header: Header.text(of: node),
            parameterTypes: (parameters ?? []).map { ($0.type.trimmedDescription + ($0.ellipsis?.text ?? ""), $0.defaultValue != nil) },
            returnType: returnType?.trimmedDescription,
            valueType: node.as(VariableDeclSyntax.self)?.bindings.first?.typeAnnotation?.type.trimmedDescription,
            throwsClause: effects?.throwsClause?.trimmedDescription,
            isAsync: effects?.asyncSpecifier != nil,
            bodyFingerprint: Self.fingerprint(of: Self.bodies(of: node)),
            lines: Self.lines(of: node, doc: doc, at: location.line, converter: converter)
        )
        entries.append(Entry(declaration: declaration, doc: doc, details: details))
    }

    /// The lines a declaration takes: from its doc comment, or its own first line without one, to its
    /// last line, or for a type to the brace that opens its members.
    ///
    /// - Parameters:
    ///   - node: The declaration.
    ///   - doc: Its doc comment, if it has one.
    ///   - line: The line the declaration itself starts on.
    ///   - converter: The file's line converter.
    /// - Returns: The lines, first through last.
    static func lines(of node: some DeclSyntaxProtocol, doc: DocComment?, at line: Int, converter: SourceLocationConverter) -> ClosedRange<Int> {
        let first = doc?.startLine ?? line
        let end = Syntax(node).asProtocol(DeclGroupSyntax.self).map { $0.memberBlock.leftBrace.positionAfterSkippingLeadingTrivia }
            ?? node.endPositionBeforeTrailingTrivia
        return first...max(first, line, converter.location(for: end).line)
    }

    /// The parts of a declaration that do its work rather than declare it: a function's, initializer's,
    /// or deinitializer's body, a subscript's or property's accessors, and a property's initial value.
    ///
    /// - Parameter node: The declaration.
    /// - Returns: The parts in source order; empty for a declaration without any.
    static func bodies(of node: some DeclSyntaxProtocol) -> [Syntax] {
        let syntax = Syntax(node)
        var parts: [Syntax?] = [
            syntax.as(FunctionDeclSyntax.self)?.body.map(Syntax.init),
            syntax.as(InitializerDeclSyntax.self)?.body.map(Syntax.init),
            syntax.as(DeinitializerDeclSyntax.self)?.body.map(Syntax.init),
            syntax.as(SubscriptDeclSyntax.self)?.accessorBlock.map(Syntax.init)
        ]
        for binding in syntax.as(VariableDeclSyntax.self)?.bindings ?? [] {
            parts.append(binding.initializer.map(Syntax.init))
            parts.append(binding.accessorBlock.map(Syntax.init))
        }
        return parts.compactMap { $0 }
    }

    /// A fingerprint of what some code does: a hash of its tokens, without the comments and spacing
    /// between them, so an edit that only reformats or comments the code keeps it.
    ///
    /// - Parameter parts: The code, such as ``bodies(of:)`` gives.
    /// - Returns: 16 hexadecimal digits, or `nil` when there is no code.
    static func fingerprint(of parts: [Syntax]) -> String? {
        guard !parts.isEmpty else { return nil }
        // FNV-1a: stable across runs and platforms, unlike `hashValue`.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for part in parts {
            for token in part.tokens(viewMode: .sourceAccurate) {
                for byte in token.text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
                hash = (hash ^ 0) &* 0x100_0000_01b3
            }
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// Reads a `// gloss:exempt <reason>` line from the trivia directly above a declaration.
    ///
    /// - Parameter trivia: The declaration's leading trivia.
    /// - Returns: The reason text (possibly empty, which the rules refuse), or `nil` with no marker.
    static func exemptMarker(in trivia: Trivia) -> String? {
        for piece in trivia.pieces {
            guard case .lineComment(let text) = piece else { continue }
            let body = text.dropFirst(2).trimmed
            guard body.hasPrefix("gloss:exempt") else { continue }
            return body.dropFirst("gloss:exempt".count).trimmed
        }
        return nil
    }

    private static func isVoid(_ type: TypeSyntax) -> Bool {
        let text = type.trimmedDescription
        return text == "Void" || text == "()" || text == "Swift.Void" || text == "Never"
    }
}

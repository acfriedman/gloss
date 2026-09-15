import Foundation
import SwiftParser
import SwiftSyntax

/// Walks one Swift file and reports every doc-comment violation in it.
///
/// The visitor only adapts syntax nodes into `Declaration` values; the rules live in `Rules` so the
/// two can evolve independently.
public final class Checker: SyntaxVisitor {
    private let file: String
    private let converter: SourceLocationConverter
    private var findings: [Diagnostic] = []
    private var conformanceDepth = 0
    private var privateDepth = 0

    /// Lints the source text of one file. Parsing happens here so callers hand over text, not trees.
    /// - Parameters:
    ///   - source: The file's contents.
    ///   - file: The path reported in diagnostics.
    /// - Returns: Violations in source order.
    public static func check(source: String, file: String) -> [Diagnostic] {
        let tree = Parser.parse(source: source)
        let checker = Checker(file: file, converter: SourceLocationConverter(fileName: file, tree: tree))
        checker.walk(tree)
        return checker.findings.sorted { ($0.line, $0.column, $0.rule.rawValue) < ($1.line, $1.column, $1.rule.rawValue) }
    }

    private init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.inheritanceClause != nil { conformanceDepth += 1 }
        if Self.isPrivate(node.modifiers) { privateDepth += 1 }
        return .visitChildren
    }

    override public func visitPost(_ node: ExtensionDeclSyntax) {
        if node.inheritanceClause != nil { conformanceDepth -= 1 }
        if Self.isPrivate(node.modifiers) { privateDepth -= 1 }
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
               modifiers: node.modifiers)
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
               isMemberwise: Self.isMemberwise(node))
        return .skipChildren
    }

    /// Whether an initializer's body is nothing but `self.x = x` for its own parameters, the shape the
    /// compiler would have synthesized. Any other statement, default, or expression makes it a real
    /// initializer with a contract of its own.
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

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
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
        if Self.isPrivate(modifiers) { privateDepth += 1 }
        return .visitChildren
    }

    // Typealiases have no members, so only the five container kinds balance `privateDepth`.
    private func leaveType(_ modifiers: DeclModifierListSyntax) {
        if Self.isPrivate(modifiers) { privateDepth -= 1 }
    }

    private static func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "private" || $0.name.text == "fileprivate" }
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
        isMemberwise: Bool = false
    ) {
        let location = converter.location(for: anchor.positionAfterSkippingLeadingTrivia)
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
        } else if Declaration.knownRequirements.contains(declaration.signature) {
            declaration.exemption = .knownRequirement
        } else if conformanceDepth > 0 {
            declaration.exemption = .conformanceExtension
        } else if isMemberwise {
            declaration.exemption = .memberwiseInit
        }
        let doc = DocComment.leading(node, converter: converter)
        findings += Rules.check(declaration, doc: doc)
    }

    /// Reads a `// gloss:exempt <reason>` line from the trivia directly above a declaration.
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

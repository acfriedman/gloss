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

    /// Lints the source text of one file.
    ///
    /// Parsing happens here so callers hand over text, not trees.
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

    // Local declarations inside bodies are not API; skip them wholesale.
    override public func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override public func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        guard name.first?.isLetter == true || name.first == "_" else { return .skipChildren }
        record(node, kind: .function, name: name, at: node.name,
               parameters: node.signature.parameterClause.parameters,
               returnType: node.signature.returnClause?.type,
               throwsErrors: node.signature.effectSpecifiers?.throwsClause != nil,
               modifiers: node.modifiers)
        return .skipChildren
    }

    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node, kind: .initializer, name: "init", at: node.initKeyword,
               parameters: node.signature.parameterClause.parameters,
               returnType: nil,
               throwsErrors: node.signature.effectSpecifiers?.throwsClause != nil,
               modifiers: node.modifiers)
        return .skipChildren
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
        return .visitChildren
    }

    private func record(
        _ node: some DeclSyntaxProtocol,
        kind: Declaration.Kind,
        name: String,
        at anchor: TokenSyntax,
        parameters: FunctionParameterListSyntax?,
        returnType: TypeSyntax?,
        throwsErrors: Bool,
        modifiers: DeclModifierListSyntax
    ) {
        let location = converter.location(for: anchor.positionAfterSkippingLeadingTrivia)
        let names = modifiers.map(\.name.text)
        let declaration = Declaration(
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
            isPrivate: names.contains("private") || names.contains("fileprivate"),
            isOverride: names.contains("override"),
            file: file,
            line: location.line,
            column: location.column
        )
        let doc = DocComment.leading(node, converter: converter)
        findings += Rules.check(declaration, doc: doc)
    }

    private static func isVoid(_ type: TypeSyntax) -> Bool {
        let text = type.trimmedDescription
        return text == "Void" || text == "()" || text == "Swift.Void" || text == "Never"
    }
}

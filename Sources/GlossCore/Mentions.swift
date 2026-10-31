import SwiftSyntax

/// Collects the type names a declaration mentions, tagged with where each appears.
///
/// Only capitalized names are collected, which is how Swift spells types. Whether a name is one of the
/// scanned types is decided later, against every declaration, by ``Graph/build(_:)``.
enum Mentions {
    /// Reads every type mention of one declaration: its signature by role, then its body.
    ///
    /// - Parameters:
    ///   - node: The declaration.
    ///   - parameters: Its parameter list, for callables.
    ///   - returnType: Its return type, for callables and subscripts.
    ///   - effects: Its effect specifiers, for a typed `throws(E)` clause.
    /// - Returns: Mentions in signature order, each name listed once per role.
    static func collect(
        _ node: some DeclSyntaxProtocol,
        parameters: FunctionParameterListSyntax?,
        returnType: TypeSyntax?,
        effects: FunctionEffectSpecifiersSyntax?
    ) -> [Contract.Mention] {
        var mentions: [Contract.Mention] = []
        func add(_ syntax: (some SyntaxProtocol)?, _ role: Contract.Mention.Role) {
            guard let syntax else { return }
            for name in names(in: syntax) where !mentions.contains(where: { $0.name == name && $0.role == role }) {
                mentions.append(Contract.Mention(name: name, role: role))
            }
        }
        let syntax = Syntax(node)
        if let group = syntax.asProtocol(DeclGroupSyntax.self) {
            add(group.inheritanceClause, .conformance)
        }
        for parameter in parameters ?? [] { add(parameter.type, .parameter) }
        add(returnType, .returns)
        add(effects?.throwsClause?.type, .throws)
        if let variable = syntax.as(VariableDeclSyntax.self) {
            for binding in variable.bindings {
                add(binding.typeAnnotation?.type, .property)
                add(binding.initializer, binding.typeAnnotation == nil ? .property : .body)
                add(binding.accessorBlock, .body)
            }
        }
        add(syntax.as(FunctionDeclSyntax.self)?.body, .body)
        add(syntax.as(InitializerDeclSyntax.self)?.body, .body)
        add(syntax.as(SubscriptDeclSyntax.self)?.accessorBlock, .body)
        return mentions
    }

    /// The capitalized type names in a piece of syntax, in source order.
    ///
    /// - Parameter syntax: A type, an expression, or a body.
    /// - Returns: Each name once; a nested type keeps its path, as in `Contract.Facts`.
    static func names(in syntax: some SyntaxProtocol) -> [String] {
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(syntax)
        var seen = Set<String>()
        return collector.names.filter { seen.insert($0).inserted }
    }

    /// Walks types and expressions, keeping capitalized names and dotted type paths.
    private final class Collector: SyntaxVisitor {
        var names: [String] = []

        override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
            keep(node.name.text)
            return .visitChildren
        }

        override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
            if let path = Self.path(of: TypeSyntax(node)) { keep(path) }
            if let arguments = node.genericArgumentClause { walk(arguments) }
            return .skipChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            keep(node.baseName.text)
            return .visitChildren
        }

        // `Contract.Facts(...)` reads as one nested type, not as `Contract` and a member.
        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            guard let base = node.base?.as(DeclReferenceExprSyntax.self), Self.isTypeName(base.baseName.text) else {
                return .visitChildren
            }
            let member = node.declName.baseName.text
            keep(Self.isTypeName(member) ? base.baseName.text + "." + member : base.baseName.text)
            return .skipChildren
        }

        private func keep(_ name: String) {
            guard let first = name.split(separator: ".").first, Self.isTypeName(String(first)), first != "Self" else { return }
            names.append(name)
        }

        private static func isTypeName(_ name: String) -> Bool {
            name.first?.isUppercase == true
        }

        private static func path(of type: TypeSyntax) -> String? {
            if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
            if let member = type.as(MemberTypeSyntax.self), let base = path(of: member.baseType) {
                return base + "." + member.name.text
            }
            return nil
        }
    }
}

import SwiftSyntax

/// A type name the declaration mentions, and where: in its signature or in its body.
///
/// Mentions are what the dependency graph is drawn from. The name is kept as written; `resolved` is
/// the graph node it names, or `nil` when no scanned source declares it.
public struct Mention: Sendable, Equatable, Codable {
    /// Where a mention appears, which says how the declaration depends on the type.
    public enum Role: String, Sendable, Codable, CaseIterable {
        /// In an inheritance clause: the type conforms to it or inherits from it.
        case conformance
        /// In a property's type, in an unannotated property's initial value, or in its attributes, such
        /// as the type a property wrapper reads in `@Environment(Store.self)`.
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

    /// The type name as written, with a nested type's dotted path kept whole.
    public var name: String
    /// Where the name appears, which says how the declaration depends on it.
    public var role: Role
    /// The id of the graph node the name refers to, set by ``Graph/build(_:)``, or `nil` when no scanned
    /// source declares it.
    public var resolved: String?
    /// The internal names of the parameters whose types mention the name, in signature order; empty for
    /// every role but `parameter`.
    public var parameters: [String] = []
}

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
    /// - Returns: Mentions in signature order, each name listed once per role, with the parameters that
    ///   mention it.
    static func collect(
        _ node: some DeclSyntaxProtocol,
        parameters: FunctionParameterListSyntax?,
        returnType: TypeSyntax?,
        effects: FunctionEffectSpecifiersSyntax?
    ) -> [Mention] {
        var mentions: [Mention] = []
        func add(_ syntax: (some SyntaxProtocol)?, _ role: Mention.Role, parameter: String? = nil) {
            guard let syntax else { return }
            for name in names(in: syntax) {
                if let index = mentions.firstIndex(where: { $0.name == name && $0.role == role }) {
                    if let parameter, !mentions[index].parameters.contains(parameter) { mentions[index].parameters.append(parameter) }
                } else {
                    mentions.append(Mention(name: name, role: role, parameters: parameter.map { [$0] } ?? []))
                }
            }
        }
        let syntax = Syntax(node)
        if let group = syntax.asProtocol(DeclGroupSyntax.self) {
            add(group.inheritanceClause, .conformance)
        }
        for parameter in parameters ?? [] { add(parameter.type, .parameter, parameter: (parameter.secondName ?? parameter.firstName).text) }
        add(returnType, .returns)
        add(effects?.throwsClause?.type, .throws)
        if let variable = syntax.as(VariableDeclSyntax.self) {
            add(variable.attributes, .property)
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

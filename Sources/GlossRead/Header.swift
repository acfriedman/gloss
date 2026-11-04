import Foundation
import SwiftSyntax

/// Renders a declaration the way an interface listing shows it: attributes, modifiers, and signature,
/// without the body, the doc comment, or a stored property's initial value.
///
/// Bodies are implementation; dropping them is what turns a source file into its interface.
enum Header {
    /// The header text of a declaration, on one line.
    ///
    /// - Parameter node: Any declaration the checker records.
    /// - Returns: The declaration without its body, whitespace collapsed to single spaces.
    static func text(of node: some DeclSyntaxProtocol) -> String {
        let syntax = Syntax(node)
        let text: String
        if let function = syntax.as(FunctionDeclSyntax.self) {
            text = function.with(\.body, nil).trimmedDescription
        } else if let initializer = syntax.as(InitializerDeclSyntax.self) {
            text = initializer.with(\.body, nil).trimmedDescription
        } else if let subscriptDecl = syntax.as(SubscriptDeclSyntax.self) {
            text = subscriptDecl.with(\.accessorBlock, nil).trimmedDescription + accessors(subscriptDecl.accessorBlock)
        } else if let variable = syntax.as(VariableDeclSyntax.self) {
            text = property(variable)
        } else if let group = syntax.asProtocol(DeclGroupSyntax.self) {
            text = typeHeader(group)
        } else {
            text = syntax.trimmedDescription
        }
        return collapse(text)
    }

    /// The keyword that introduces a declaration, which says what kind of thing it is.
    ///
    /// - Parameter node: Any declaration the checker records.
    /// - Returns: `func`, `init`, `subscript`, `var`, `let`, `case`, `struct`, `class`, `enum`, `actor`,
    ///   `protocol`, `typealias`, or `macro`; `decl` for anything else.
    static func keyword(of node: some DeclSyntaxProtocol) -> String {
        let syntax = Syntax(node)
        if syntax.is(FunctionDeclSyntax.self) { return "func" }
        if syntax.is(InitializerDeclSyntax.self) { return "init" }
        if syntax.is(SubscriptDeclSyntax.self) { return "subscript" }
        if let variable = syntax.as(VariableDeclSyntax.self) { return variable.bindingSpecifier.text }
        if syntax.is(EnumCaseDeclSyntax.self) { return "case" }
        if syntax.is(StructDeclSyntax.self) { return "struct" }
        if syntax.is(ClassDeclSyntax.self) { return "class" }
        if syntax.is(EnumDeclSyntax.self) { return "enum" }
        if syntax.is(ActorDeclSyntax.self) { return "actor" }
        if syntax.is(ProtocolDeclSyntax.self) { return "protocol" }
        if syntax.is(TypeAliasDeclSyntax.self) { return "typealias" }
        if syntax.is(AssociatedTypeDeclSyntax.self) { return "associatedtype" }
        if syntax.is(MacroDeclSyntax.self) { return "macro" }
        return "decl"
    }

    /// A type's header: everything before its member block.
    ///
    /// - Parameter group: A struct, class, enum, actor, protocol, or extension.
    /// - Returns: The header with the member block removed.
    private static func typeHeader(_ group: some DeclGroupSyntax) -> String {
        var copy = group
        copy.memberBlock = MemberBlockSyntax(members: [])
        let text = copy.trimmedDescription
        return text.hasSuffix("{}") ? String(text.dropLast(2)) : text
    }

    /// A property's header. The initial value is dropped when a type annotation already says what the
    /// property holds, and kept when it is the only statement of the type; a computed body becomes the
    /// `{ get }` or `{ get set }` it offers callers.
    ///
    /// - Parameter variable: The property declaration.
    /// - Returns: The header, one binding after another.
    private static func property(_ variable: VariableDeclSyntax) -> String {
        var copy = variable
        var bindings: [PatternBindingSyntax] = []
        var suffix = ""
        for binding in variable.bindings {
            var trimmed = binding.with(\.accessorBlock, nil)
            if binding.typeAnnotation != nil { trimmed = trimmed.with(\.initializer, nil) }
            suffix = accessors(binding.accessorBlock)
            bindings.append(trimmed)
        }
        copy.bindings = PatternBindingListSyntax(bindings)
        return copy.trimmedDescription + suffix
    }

    /// The accessors an accessor block offers callers, without their bodies.
    ///
    /// - Parameter block: The block, or `nil` for a stored property.
    /// - Returns: ` { get }`, ` { get set }`, and the like, or an empty string when only observers are present.
    private static func accessors(_ block: AccessorBlockSyntax?) -> String {
        guard let block else { return "" }
        switch block.accessors {
        case .getter:
            return " { get }"
        case .accessors(let list):
            let names = list.map(\.accessorSpecifier.text).filter { $0 == "get" || $0 == "set" }
            return names.isEmpty ? "" : " { " + names.joined(separator: " ") + " }"
        }
    }

    /// Collapses every whitespace run to one space, and drops the space a line break left inside
    /// brackets, so a signature wrapped across lines reads as one.
    ///
    /// - Parameter text: Source text, possibly spanning lines.
    /// - Returns: The text on one line.
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "( ", with: "(")
            .replacingOccurrences(of: " )", with: ")")
            .replacingOccurrences(of: ", )", with: ")")
            .replacingOccurrences(of: ",)", with: ")")
    }
}

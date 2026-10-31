import GlossCore
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
        case plain
        case keyword
        case attribute
        case string
        case number
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
        public var text: String
        public var kind: Kind
    }

    /// Splits source into runs.
    ///
    /// - Parameters:
    ///   - code: Swift source. A declaration without its body parses with recovery and colors the same.
    ///   - projectTypes: Type names the scanned sources declare, each path component on its own.
    /// - Returns: Runs that together spell `code` exactly, with neighbors of one kind merged.
    public static func runs(_ code: String, projectTypes: Set<String> = []) -> [Run] {
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
    ///   ``GlossCore/Interface`` is.
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

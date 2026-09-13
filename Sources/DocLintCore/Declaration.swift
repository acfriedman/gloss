/// What the rules need to know about a declaration, independent of the syntax tree.
///
/// Decoupling from SwiftSyntax keeps every rule testable from a literal and lets the checker
/// stay a thin adapter.
public struct Declaration: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case function, initializer, `subscript`, type, property, enumCase, other
    }

    /// One parameter of a callable, as the two names DocC will accept for it.
    public struct Parameter: Sendable, Equatable {
        public var label: String?
        public var name: String

        public init(label: String?, name: String) {
            self.label = label
            self.name = name
        }

        /// Whether a `- Parameter x:` entry naming `x` refers to this parameter.
        ///
        /// DocC matches the internal name, and Xcode tolerates the external label; both are accepted
        /// so the doc never has to be rewritten when only the label changes.
        /// - Parameter written: The name as it appears in the doc comment.
        /// - Returns: `true` when `written` is the internal name or the external label.
        public func matches(_ written: String) -> Bool {
            written == name || written == label
        }
    }

    public var kind: Kind
    public var name: String
    public var parameters: [Parameter]?
    public var returnsValue: Bool
    public var throwsErrors: Bool
    public var isPrivate: Bool
    public var isOverride: Bool
    public var file: String
    public var line: Int
    public var column: Int

    public init(
        kind: Kind,
        name: String,
        parameters: [Parameter]? = nil,
        returnsValue: Bool = false,
        throwsErrors: Bool = false,
        isPrivate: Bool = false,
        isOverride: Bool = false,
        file: String = "<memory>",
        line: Int = 1,
        column: Int = 1
    ) {
        self.kind = kind
        self.name = name
        self.parameters = parameters
        self.returnsValue = returnsValue
        self.throwsErrors = throwsErrors
        self.isPrivate = isPrivate
        self.isOverride = isOverride
        self.file = file
        self.line = line
        self.column = column
    }

    /// Whether the harness demands a doc comment on this declaration at all.
    ///
    /// Private members and overrides are exempt: the first are implementation detail, the second
    /// inherit the documented contract of what they override.
    public var requiresDoc: Bool {
        switch kind {
        case .function, .initializer, .subscript, .type:
            return !isPrivate && !isOverride
        case .property, .enumCase, .other:
            return false
        }
    }
}

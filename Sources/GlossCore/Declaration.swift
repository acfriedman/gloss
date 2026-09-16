/// What the rules need to know about a declaration, independent of the syntax tree.
///
/// Decoupling from SwiftSyntax keeps every rule testable from a literal and lets the checker
/// stay a thin adapter.
public struct Declaration: Sendable, Equatable {
    /// The syntactic category of a declaration, which decides which rules apply. Callables get the
    /// markup rules; types, properties, and cases get only the summary rules once documented.
    public enum Kind: String, Sendable {
        case function, initializer, `subscript`, type, property, enumCase, other
    }

    /// One parameter of a callable, as the two names DocC will accept for it.
    public struct Parameter: Sendable, Equatable {
        public var label: String?
        public var name: String

        /// Creates a parameter from its two names.
        ///
        /// - Parameters:
        ///   - label: The external argument label, or `nil` for `_`.
        ///   - name: The internal name; the same as `label` when the signature gives only one.
        public init(label: String?, name: String) {
            self.label = label
            self.name = name
        }

        /// Whether a `- Parameter x:` entry naming `x` refers to this parameter. DocC matches the internal
        /// name and Xcode tolerates the external label, so both are accepted and a label-only change
        /// never forces a doc rewrite.
        ///
        /// - Parameter written: The name as it appears in the doc comment.
        /// - Returns: `true` when `written` is the internal name or the external label.
        public func matches(_ written: String) -> Bool {
            written == name || written == label
        }
    }

    /// Why a declaration is excused from the harness, when it is.
    ///
    /// Syntax cannot prove that a method implements a protocol requirement, so the harness accepts
    /// three proxies: a signature every Swift author recognizes, residence in a conformance
    /// extension, or an author's marker naming the reason.
    public enum Exemption: Sendable, Equatable {
        /// The signature is a well-known protocol requirement, one of ``Declaration/knownRequirements``.
        case knownRequirement
        /// The declaration sits in an `extension T: P { }` block, which houses P's requirements.
        case conformanceExtension
        /// A `// gloss:exempt <reason>` line directly above the declaration.
        case marker(reason: String)
        /// An initializer whose body only assigns its parameters to stored properties, so a parameter
        /// entry could only restate the property's own doc.
        case memberwiseInit
    }

    public var kind: Kind
    public var name: String
    public var exemption: Exemption?
    public var parameters: [Parameter]?
    public var returnsValue: Bool
    public var throwsErrors: Bool
    public var isPrivate: Bool
    public var isOverride: Bool
    public var file: String
    public var line: Int
    public var column: Int

    /// Creates a declaration by hand, for tests and tools that have no syntax tree.
    ///
    /// - Parameters:
    ///   - kind: The syntactic category; decides which rules apply.
    ///   - name: The base name as diagnostics report it (`init` for initializers, `subscript` for subscripts).
    ///   - exemption: Why the declaration is excused, or `nil` when it is not.
    ///   - parameters: The parameter list of a callable; `nil` for types, properties, and cases, which
    ///     also skips the returns and throws rules.
    ///   - returnsValue: `true` when the declared return type is anything but `Void`, `()`, or `Never`.
    ///   - throwsErrors: `true` for `throws` and `rethrows`.
    ///   - isPrivate: `true` for `private` or `fileprivate`, including members of a private type or
    ///     extension; excuses `missing-doc` only.
    ///   - isOverride: `true` for `override`; excuses `missing-doc`, since the doc is inherited.
    ///   - file: The path diagnostics report.
    ///   - line: The 1-based source line of the name token.
    ///   - column: The 1-based column of the name token.
    public init(
        kind: Kind,
        name: String,
        exemption: Exemption? = nil,
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
        self.exemption = exemption
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
    /// Private members, overrides, and exempt declarations are excused: the first are
    /// implementation detail, the rest inherit the documented contract of what they implement or,
    /// for a memberwise initializer, of the properties they set.
    public var requiresDoc: Bool {
        guard exemption == nil else { return false }
        switch kind {
        case .function, .initializer, .subscript, .type:
            return !isPrivate && !isOverride
        case .property, .enumCase, .other:
            return false
        }
    }

    /// The signature as the harness names it: the base name followed by the argument labels, each
    /// with its colon, in parentheses. Labels are what tell two initializers of one type apart, so this
    /// is the key the known-requirement list is matched on.
    public var signature: String {
        guard let parameters else { return name }
        return name + "(" + parameters.map { ($0.label ?? "_") + ":" }.joined() + ")"
    }

    /// Signatures the standard library, Foundation, and the macro system require of conformers.
    ///
    /// Their contract is the protocol's; a doc comment here would restate it. Keep the list to
    /// requirements every Swift author recognizes on sight.
    public static let knownRequirements: Set<String> = [
        // Codable / NSCoding / NSCopying
        "init(from:)", "encode(to:)", "init(coder:)", "encode(with:)", "copy(with:)",
        // Hashable / Equatable / Comparable / Identifiable helpers
        "hash(into:)", "isEqual(_:)",
        // RawRepresentable and the literal protocols
        "init(rawValue:)", "init(stringLiteral:)", "init(extendedGraphemeClusterLiteral:)",
        "init(unicodeScalarLiteral:)", "init(integerLiteral:)", "init(floatLiteral:)",
        "init(booleanLiteral:)", "init(arrayLiteral:)", "init(dictionaryLiteral:)", "init(nilLiteral:)",
        "init(stringInterpolation:)", "init(literalCapacity:interpolationCount:)", "appendLiteral(_:)",
        // Sequence / IteratorProtocol / Collection
        "makeIterator()", "next()", "index(after:)", "index(before:)",
        // Entry points and command runners
        "main()", "run()", "validate()",
        // Error / CustomStringConvertible-style descriptions are properties; listed as methods only
        "encode(to:configuration:)", "init(from:configuration:)",
        // swift-syntax macro roles
        "expansion(of:in:)", "expansion(of:providingMembersOf:in:)",
        "expansion(of:providingMembersOf:conformingTo:in:)", "expansion(of:providingPeersOf:in:)",
        "expansion(of:attachedTo:providingExtensionsOf:conformingTo:in:)",
        "expansion(of:attachedTo:providingAttributesFor:in:)", "expansion(of:providingAccessorsOf:in:)",
        "expansion(of:providingPreambleFor:in:)", "expansion(of:providingBodyFor:in:)",
        // Result builders
        "buildBlock(_:)", "buildExpression(_:)", "buildOptional(_:)", "buildEither(first:)",
        "buildEither(second:)", "buildArray(_:)", "buildPartialBlock(first:)",
        "buildPartialBlock(accumulated:next:)", "buildFinalResult(_:)", "buildLimitedAvailability(_:)"
    ]
}

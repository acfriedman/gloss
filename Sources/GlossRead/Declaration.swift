/// What the rules need to know about a declaration, independent of the syntax tree.
///
/// Decoupling from SwiftSyntax keeps every rule testable from a literal and lets the checker
/// stay a thin adapter.
public struct Declaration: Sendable, Equatable {
    /// The syntactic category of a declaration, which decides which rules apply. Callables get the
    /// markup rules; types, properties, and cases get only the summary rules once documented.
    public enum Kind: String, Sendable, Codable {
        /// A `func` or a `macro`.
        case function
        /// An `init`.
        case initializer
        /// A `subscript`.
        case `subscript`
        /// A struct, class, enum, actor, protocol, `typealias`, or `associatedtype`.
        case type
        /// A `var` or `let` outside a body.
        case property
        /// An enum case, covering every element its `case` line declares.
        case enumCase
        /// Anything else, such as a script's top-level code, which owes no doc.
        case other
    }

    /// One parameter of a callable, as the two names DocC will accept for it.
    public struct Parameter: Sendable, Equatable {
        /// The external argument label, or `nil` for `_`.
        public var label: String?
        /// The internal name; the same as the label when the signature gives only one.
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
        /// The signature is a well-known protocol requirement, one of ``Declaration/knownRequirements``,
        /// or the declaration is a case of a `CodingKeys` enum, which names a stored property.
        case knownRequirement
        /// The declaration sits in an `extension T: P { }` block, which houses P's requirements.
        case conformanceExtension
        /// A `// gloss:exempt <reason>` line directly above the declaration.
        case marker(reason: String)
        /// An initializer whose body only assigns its parameters to stored properties, so a parameter
        /// entry could only restate the property's own doc.
        case memberwiseInit
    }

    /// The syntactic category, which decides which rules apply.
    public var kind: Kind
    /// The base name as diagnostics report it: `init` for initializers, `subscript` for subscripts.
    public var name: String
    /// Why the declaration is excused from the harness, or `nil` when it is not.
    public var exemption: Exemption?
    /// The parameter list of a callable, or `nil` for types, properties, and cases, which skips the
    /// parameter, returns, and throws rules.
    public var parameters: [Parameter]?
    /// `true` when the declared return type is anything but `Void`, `()`, or `Never`, which makes
    /// `- Returns:` required.
    public var returnsValue: Bool
    /// `true` for `throws`, `throws(E)`, and `rethrows`, which makes `- Throws:` required.
    public var throwsErrors: Bool
    /// `true` for `private` or `fileprivate`, including members of a private type or extension; excuses
    /// `missing-doc` only.
    public var isPrivate: Bool
    /// `true` for `override`; excuses `missing-doc`, since the doc is inherited.
    public var isOverride: Bool
    /// The effective access level: `open`, `public`, `package`, `internal`, `fileprivate`, or `private`.
    public var access: String
    /// The path diagnostics report.
    public var file: String
    /// The 1-based source line of the name token, or of the keyword for an initializer, subscript, property,
    /// or case.
    public var line: Int
    /// The 1-based column of the name token, or of the keyword for an initializer, subscript, property, or
    /// case.
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
    ///   - access: The effective access level, such as `public` or `internal`.
    ///   - file: The path diagnostics report.
    ///   - line: The 1-based source line of the name token, or of the keyword for an initializer,
    ///     subscript, property, or enum case.
    ///   - column: The 1-based column of that token.
    public init(
        kind: Kind,
        name: String,
        exemption: Exemption? = nil,
        parameters: [Parameter]? = nil,
        returnsValue: Bool = false,
        throwsErrors: Bool = false,
        isPrivate: Bool = false,
        isOverride: Bool = false,
        access: String = "internal",
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
        self.access = access
        self.file = file
        self.line = line
        self.column = column
    }

    /// The signature as the harness names it: the base name followed by the argument labels, each
    /// with its colon, in parentheses. Labels are what tell two initializers of one type apart, so this
    /// is the key the known-requirement list is matched on.
    public var signature: String {
        guard let parameters else { return name }
        return name + "(" + parameters.map { ($0.label ?? "_") + ":" }.joined() + ")"
    }

    /// How wide an access level is, so two can be compared.
    ///
    /// - Parameter access: An access level as written, such as `public`.
    /// - Returns: 3 for `open` and `public`, 2 for `package`, 1 for `internal`, and 0 for the private ones.
    public static func rank(_ access: String) -> Int {
        switch access {
        case "open", "public": 3
        case "package": 2
        case "internal": 1
        default: 0
        }
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
        // SwiftUI's ViewModifier and its style protocols, such as ButtonStyle
        "body(content:)", "makeBody(configuration:)",
        // Codable with configuration
        "encode(to:configuration:)", "init(from:configuration:)",
        // Properties: View, Identifiable, the description protocols, RawRepresentable, Hashable,
        // CaseIterable, LocalizedError, Collection, and Actor
        "body", "id", "description", "debugDescription", "rawValue", "hashValue", "allCases",
        "errorDescription", "failureReason", "recoverySuggestion", "helpAnchor", "startIndex", "endIndex",
        "unownedExecutor",
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

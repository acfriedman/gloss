import LucidRead

/// What one declaration says about a type it mentions: the source's own answer to why one type uses
/// another.
///
/// Every declaration a dependency runs through owes a doc comment, so the reason is usually written
/// where the type is used already: in the entry for the parameter that takes it, in the `- Returns:` or
/// `- Throws:` entry, or in the summary of the property that holds it or the member that uses it inside.
public struct Reason: Sendable, Equatable {
    /// Doc carried over from the type a declaration uses, standing in where the declaration's own says
    /// nothing: the summary of a member it reaches, or of the type itself.
    public struct Forward: Sendable, Equatable {
        /// What the doc belongs to: a member of the used type as a caller writes it, or the type's name.
        public var name: String
        /// The forwarded summary.
        public var summary: String

        /// Creates a forwarded doc.
        ///
        /// - Parameters:
        ///   - name: What the doc belongs to: a member of the used type as a caller writes it, or the
        ///     type's name.
        ///   - summary: The forwarded summary.
        public init(name: String, summary: String) {
            self.name = name
            self.summary = summary
        }
    }

    /// One doc entry that speaks to the type itself.
    public struct Entry: Sendable, Equatable {
        /// The role the entry documents: `parameter`, `returns`, or `throws`.
        public var role: Mention.Role
        /// The parameter's internal name for a parameter entry, or `nil` for the others.
        public var parameter: String?
        /// The entry's text, or `nil` when the doc has no such entry.
        public var text: String?
    }

    /// The declaration's name as a caller writes it, as ``Contract/callName`` gives it.
    public var name: String
    /// The introducing keyword, such as `func`, `var`, or `struct`.
    public var keyword: String
    /// Every role the declaration mentions the type in, in ``LucidRead/Mention/Role`` order.
    public var roles: [Mention.Role]
    /// The entries that answer for one role apart from the summary: each parameter that takes the type,
    /// then the return, then the thrown error.
    public var entries: [Entry]
    /// The declaration's summary, which answers for a property, a conformance, and a use inside a body;
    /// `nil` when it has none.
    public var summary: String?
    /// The path the declaration was read from, as reported.
    public var file: String
    /// The declaration's 1-based line.
    public var line: Int
    /// The members of the type the declaration's body reaches, by base name in source order.
    public var members: [String] = []
    /// Docs carried over from the type when the declaration's own says nothing, set by whoever holds the
    /// type's contracts; empty when the declaration explains itself.
    public var forwarded: [Forward] = []

    /// `true` when nothing written says why: no summary, and no entry with text.
    public var isUnexplained: Bool {
        summary == nil && entries.allSatisfy { $0.text == nil }
    }
}

extension Contract {
    /// What the declaration says about a type it mentions.
    ///
    /// - Parameter target: A node id, as ``LucidRead/Mention/resolved`` holds it once ``Graph/build(_:)`` has run.
    /// - Returns: The reason, or `nil` when the declaration does not mention the type.
    public func reason(toward target: String) -> Reason? {
        let mentions = self.mentions.filter { $0.resolved == target }
        guard !mentions.isEmpty else { return nil }
        let roles = Mention.Role.allCases.filter { role in mentions.contains { $0.role == role } }
        let taking = Set(mentions.flatMap(\.parameters))
        var entries = parameters.filter { taking.contains($0.name) }.map {
            Reason.Entry(role: .parameter, parameter: $0.name, text: $0.doc)
        }
        if roles.contains(.returns) { entries.append(Reason.Entry(role: .returns, text: returns)) }
        if roles.contains(.throws) { entries.append(Reason.Entry(role: .throws, text: throwsDoc)) }
        var members: [String] = []
        for member in mentions.flatMap(\.members) where !members.contains(member) { members.append(member) }
        return Reason(name: callName, keyword: keyword, roles: roles, entries: entries, summary: summary, file: file, line: line,
                      members: members)
    }

    /// The name a caller writes: a callable's base name with its argument labels, the way this one is
    /// written ``Contract/reason(toward:)``, and any other declaration's name as it is.
    public var callName: String {
        guard ["func", "init", "subscript", "macro"].contains(keyword) else { return name }
        return name + "(" + parameters.map { ($0.label ?? "_") + ":" }.joined() + ")"
    }
}

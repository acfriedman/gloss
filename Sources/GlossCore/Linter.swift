/// Checks doc comments against ``Rules``, over the declarations ``DeclarationReader`` reads.
///
/// Linting is one consumer of a reading, and the contract model is another; neither knows the other.
public enum Linter {
    /// Lints the source text of one file.
    ///
    /// - Parameters:
    ///   - source: The file's contents.
    ///   - file: The path reported in diagnostics.
    /// - Returns: Violations in source order.
    public static func check(source: String, file: String) -> [Diagnostic] {
        DeclarationReader.read(source: source, file: file)
            .flatMap { Rules.check($0.declaration, doc: $0.doc) }
            .sorted { ($0.line, $0.column, $0.rule.rawValue) < ($1.line, $1.column, $1.rule.rawValue) }
    }

    /// Assesses one declaration as read: whether it owes a doc, why it is excused if it is, and what
    /// the rules found.
    ///
    /// - Parameter entry: A declaration from ``DeclarationReader``.
    /// - Returns: The assessment, findings in source order.
    public static func assess(_ entry: DeclarationReader.Entry) -> Assessment {
        Assessment(
            requiresDoc: entry.declaration.requiresDoc,
            exemption: entry.declaration.exemption.map(describe),
            findings: Rules.check(entry.declaration, doc: entry.doc).map {
                Assessment.Finding(rule: $0.rule.rawValue, line: $0.line, message: $0.message)
            }
        )
    }

    /// Words a reader can act on for each exemption, so no view ever shows an enum case name.
    ///
    /// - Parameter exemption: The reason the harness excused the declaration.
    /// - Returns: A short phrase; a marker's own reason is passed through.
    static func describe(_ exemption: Declaration.Exemption) -> String {
        switch exemption {
        case .knownRequirement: "Known protocol requirement"
        case .conformanceExtension: "In a conformance extension"
        case .marker(let reason): reason.isBlank ? "Marked exempt, no reason given" : reason
        case .memberwiseInit: "Memberwise initializer"
        }
    }
}

/// What the linter concluded about one declaration, kept beside its ``Contract`` rather than in it.
public struct Assessment: Sendable, Equatable, Codable {
    /// One rule finding, addressed by line so a view can place it next to the contract it breaks.
    public struct Finding: Sendable, Equatable, Codable {
        public var rule: String
        public var line: Int
        public var message: String
    }

    /// `true` when the harness demands a doc comment on the declaration.
    public var requiresDoc: Bool
    /// Why the declaration is excused from the harness, in words, or `nil` when it is not.
    public var exemption: String?
    public var findings: [Finding]
}

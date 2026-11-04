import GlossRead

/// Checks doc comments against ``Rules``, over the declarations ``GlossRead/DeclarationReader`` reads.
///
/// Linting is one consumer of a ``GlossRead/Reading``, and the contract model is another; neither knows
/// the other.
public enum Linter {
    /// Lints the source text of one file on its own, without the rules that need every file, such as
    /// ``Rule/deadLink``.
    ///
    /// - Parameters:
    ///   - source: The file's contents.
    ///   - file: The path reported in diagnostics.
    /// - Returns: Violations in source order.
    public static func check(source: String, file: String) -> [Diagnostic] {
        DeclarationReader.read(source: source, file: file)
            .flatMap { Rules.check($0.declaration, doc: $0.doc) }
            .sorted(by: inSourceOrder)
    }

    /// Lints a whole project: every file's own rules, then the links each file makes into the others.
    ///
    /// - Parameter sources: Each file's path, as it should be reported, and its contents.
    /// - Returns: Violations, file by file in the order given, each file's in source order.
    public static func check(sources: [(file: String, source: String)]) -> [Diagnostic] {
        let reading = Reading(sources: sources)
        return reading.files.flatMap { file in
            file.entries.flatMap { Rules.check($0.declaration, doc: $0.doc) + deadLinks($0, index: reading.index) }
                .sorted(by: inSourceOrder)
        }
    }

    /// Assesses every declaration of sources already read, links into every file included.
    ///
    /// - Parameter reading: The sources, read once.
    /// - Returns: One assessment per declaration, in file order and then source order, the order the
    ///   contract model keeps its contracts in.
    public static func assess(_ reading: Reading) -> [Assessment] {
        Timing.measure("lint", "\(reading.files.count) files") {
            concurrentMap(reading.files) { file in file.entries.map { assess($0, index: reading.index) } }.flatMap { $0 }
        }
    }

    /// Finds the links in a declaration's comment that name nothing.
    ///
    /// - Parameters:
    ///   - entry: A declaration from ``DeclarationReader``.
    ///   - index: Every declaration of the project.
    /// - Returns: One ``Rule/deadLink`` finding per link that resolves to nothing, in source order.
    public static func deadLinks(_ entry: DeclarationReader.Entry, index: SymbolIndex) -> [Diagnostic] {
        guard let doc = entry.doc else { return [] }
        let declaration = entry.declaration
        let scope = entry.details.container + (declaration.kind == .type ? [declaration.name] : [])
        return SymbolIndex.links(in: doc).filter { !index.resolves($0.text, from: scope) }.map { link in
            Rules.diagnostic(declaration, line: link.line, .deadLink,
                             "``\(link.text)`` names nothing the scanned sources declare. Fix the path, or qualify another module's symbol with its module, as in ``Swift/String``.")
        }
    }

    /// Assesses one declaration as read: whether it owes a doc, why it is excused if it is, and what
    /// the rules found.
    ///
    /// - Parameters:
    ///   - entry: A declaration from ``DeclarationReader``.
    ///   - index: Every declaration of the project, to check the comment's links against; `nil` skips
    ///     them.
    /// - Returns: The assessment, findings in source order.
    public static func assess(_ entry: DeclarationReader.Entry, index: SymbolIndex? = nil) -> Assessment {
        let diagnostics = Rules.check(entry.declaration, doc: entry.doc) + (index.map { deadLinks(entry, index: $0) } ?? [])
        return Assessment(
            requiresDoc: entry.declaration.requiresDoc,
            exemption: entry.declaration.exemption.map(describe),
            findings: diagnostics.sorted(by: inSourceOrder).map {
                Assessment.Finding(rule: $0.rule.rawValue, line: $0.line, message: $0.message)
            }
        )
    }

    /// Orders diagnostics by line, then column, then rule code, so reports are stable.
    ///
    /// - Parameters:
    ///   - lhs: One diagnostic.
    ///   - rhs: Another.
    /// - Returns: `true` when `lhs` comes first.
    static func inSourceOrder(_ lhs: Diagnostic, _ rhs: Diagnostic) -> Bool {
        (lhs.line, lhs.column, lhs.rule.rawValue) < (rhs.line, rhs.column, rhs.rule.rawValue)
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
        /// The rule's code as reports print it, such as `missing-doc`.
        public var rule: String
        /// The 1-based source line the finding points at.
        public var line: Int
        /// The fix in one or two sentences, quoting the fragment it names.
        public var message: String
    }

    /// `true` when the harness demands a doc comment on the declaration.
    public var requiresDoc: Bool
    /// Why the declaration is excused from the harness, in words, or `nil` when it is not.
    public var exemption: String?
    /// What the rules found, in source order; empty when there is nothing to fix.
    public var findings: [Finding]
}

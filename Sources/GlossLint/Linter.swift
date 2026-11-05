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
    ///   - style: The project's house style; gloss's own when not given.
    /// - Returns: Violations in source order, at the levels the style sets.
    public static func check(source: String, file: String, style: HouseStyle = HouseStyle()) -> [Diagnostic] {
        style.report(DeclarationReader.read(source: source, file: file)
            .flatMap { Rules.check($0.declaration, doc: $0.doc, style: style) }
            .sorted(by: inSourceOrder))
    }

    /// Lints a whole project: every file's own rules, then the links each file makes into the others.
    ///
    /// - Parameters:
    ///   - sources: Each file's path, as it should be reported, and its contents.
    ///   - style: The project's house style; gloss's own when not given. Files it excludes are read, so
    ///     links into them resolve, but not linted.
    /// - Returns: Violations, file by file in the order given, each file's in source order, at the levels
    ///   the style sets.
    public static func check(sources: [(file: String, source: String)], style: HouseStyle = HouseStyle()) -> [Diagnostic] {
        check(Reading(sources: sources), style: style)
    }

    /// Lints sources already read, so a caller that builds the interface from the same reading parses once.
    ///
    /// - Parameters:
    ///   - reading: The sources, read once.
    ///   - style: The project's house style; gloss's own when not given.
    /// - Returns: Violations, file by file in the order read, each file's in source order, at the levels the
    ///   style sets.
    public static func check(_ reading: Reading, style: HouseStyle = HouseStyle()) -> [Diagnostic] {
        files(reading, style: style) + pages(reading, style: style)
    }

    /// Lints each file's declarations and the links they make into the others.
    ///
    /// - Parameters:
    ///   - reading: The sources, read once.
    ///   - style: The project's house style.
    /// - Returns: Violations, file by file in the order read, each file's in source order.
    static func files(_ reading: Reading, style: HouseStyle) -> [Diagnostic] {
        reading.files.filter { !style.excludes($0.file) }.flatMap { file in
            style.report(file.entries.flatMap { Rules.check($0.declaration, doc: $0.doc, style: style) + deadLinks($0, index: reading.index) }
                .sorted(by: inSourceOrder))
        }
    }

    /// Assesses every declaration of sources already read, links into every file included.
    ///
    /// - Parameters:
    ///   - reading: The sources, read once.
    ///   - style: The project's house style; gloss's own when not given.
    /// - Returns: One assessment per declaration, in file order and then source order, the order the
    ///   contract model keeps its contracts in; a file the style excludes owes no docs and has no findings.
    public static func assess(_ reading: Reading, style: HouseStyle = HouseStyle()) -> [Assessment] {
        Timing.measure("lint", "\(reading.files.count) files") {
            concurrentMap(reading.files) { file in
                guard !style.excludes(file.file) else {
                    return file.entries.map { _ in Assessment(requiresDoc: false, exemption: "Excluded by the house style", findings: []) }
                }
                return file.entries.map { assess($0, index: reading.index, style: style) }
            }.flatMap { $0 }
        }
    }

    /// The longest a module page's Overview runs, in sentences, so the page reads at a glance.
    static let overviewLimit = 5
    /// The longest a Topics group's lead runs, in sentences.
    static let topicLeadLimit = 1

    /// Checks each module's page against its module: that it is there and titled for it, says what the
    /// module does in a summary the house style accepts, stays short, links every public type, and links
    /// nothing that is gone. Only SwiftPM's modules, the folders right under `Sources`, are asked for one.
    ///
    /// - Parameters:
    ///   - reading: The sources, read once, the pages among them.
    ///   - style: The project's house style.
    /// - Returns: Violations, the missing pages first, then each page's in source order.
    static func pages(_ reading: Reading, style: HouseStyle) -> [Diagnostic] {
        // Each module in SwiftPM's layout, in the order first read: its first file and its public types.
        var modules: [(name: String, first: String, sources: String, types: [String])] = []
        for file in reading.files where !style.excludes(file.file) {
            let parts = file.file.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard let root = parts.lastIndex(of: "Sources"), root + 2 < parts.count else { continue }
            let name = parts[root + 1]
            let types = file.entries.filter {
                $0.declaration.kind == .type && $0.details.container.isEmpty && Declaration.rank($0.declaration.access) == 3
            }.map(\.declaration.name)
            if let index = modules.firstIndex(where: { $0.name == name }) {
                modules[index].types += types
            } else {
                modules.append((name, file.file, parts[...root].joined(separator: "/"), types))
            }
        }
        var found: [Diagnostic] = []
        let pages = reading.modulePages.filter { !style.excludes($0.file) }
        let paged = Set(pages.map { SourceFiles.module(of: $0.file) })
        for module in modules where !paged.contains(module.name) {
            found.append(Diagnostic(file: module.first, line: 1, column: 1, rule: .moduleDocMissing,
                                    message: "`\(module.name)` has no page. Write `\(ModulePage.path(forModule: module.name, in: module.sources))`: a `# \(module.name)` title, what it does and why in a sentence or two, an Overview, and Topics."))
        }
        for page in pages {
            let name = SourceFiles.module(of: page.file)
            let declaration = Declaration(kind: .type, name: name, access: "public", file: page.file, line: page.titleLine, column: 1)
            var findings: [Diagnostic] = []
            if page.module != name {
                findings.append(Rules.diagnostic(declaration, line: page.titleLine, .moduleDocTitle,
                                                 "The page's first line must be `# \(name)`, the module whose folder it is in."))
            }
            if page.summary.isEmpty {
                findings.append(Rules.diagnostic(declaration, line: page.titleLine, .summaryEmpty,
                                                 "Under its title, say what `\(name)` does and why it exists, in one or two sentences."))
            } else {
                let summary = DocComment(lines: page.summary)
                findings += Rules.summaryRules(declaration, summary, DocStructure.parse(summary))
            }
            findings += Rules.symbolLinkRules(declaration, DocComment(lines: page.summary + page.overview + page.topics.flatMap(\.lead)))
            let sentences = Sentences.count(in: page.overviewParagraphs.joined(separator: " "))
            if sentences > overviewLimit, let first = page.overview.first {
                findings.append(Rules.diagnostic(declaration, line: first.line, .moduleDocLength,
                                                 "The Overview has \(sentences) sentences; keep it to \(overviewLimit) so the page reads at a glance, and leave the detail to the types' own docs."))
            }
            for topic in page.topics where Sentences.count(in: topic.lead.map(\.text).joined(separator: " ")) > topicLeadLimit {
                findings.append(Rules.diagnostic(declaration, line: topic.line, .moduleDocLength,
                                                 "The lead under `### \(topic.title)` is more than one sentence; say what the group holds in one."))
            }
            let links = SymbolIndex.links(in: DocComment(lines: page.lines))
            for link in links where !reading.index.resolves(link.text, from: []) {
                findings.append(Rules.diagnostic(declaration, line: link.line, .deadLink,
                                                 "``\(link.text)`` names nothing the scanned sources declare. Fix the path, or drop the link if the type is gone."))
            }
            // A link names a type by its first name after the module, as in ``GlossRead/Reading``.
            let linked = Set(links.compactMap { link -> String? in
                var parts = link.text.split(separator: "/").map(String.init)
                if parts.count > 1, parts[0] == name { parts.removeFirst() }
                return parts.first
            })
            let topics = page.topics.first?.line ?? page.titleLine
            for type in modules.first(where: { $0.name == name })?.types ?? [] where !linked.contains(type) {
                findings.append(Rules.diagnostic(declaration, line: topics, .moduleDocUnlisted,
                                                 "`\(type)` is public, but the page links it nowhere; list it as ``\(type)`` under a `###` group in Topics."))
            }
            found += findings.sorted(by: inSourceOrder)
        }
        return style.report(found)
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
    ///   - style: The project's house style; gloss's own when not given.
    /// - Returns: The assessment, findings in source order at the levels the style sets.
    public static func assess(_ entry: DeclarationReader.Entry, index: SymbolIndex? = nil, style: HouseStyle = HouseStyle()) -> Assessment {
        let diagnostics = Rules.check(entry.declaration, doc: entry.doc, style: style) + (index.map { deadLinks(entry, index: $0) } ?? [])
        return Assessment(
            requiresDoc: style.requiresDoc(entry.declaration),
            exemption: entry.declaration.exemption.map(describe),
            findings: style.report(diagnostics.sorted(by: inSourceOrder)).map {
                Assessment.Finding(rule: $0.rule.rawValue, line: $0.line, message: $0.message, severity: $0.severity)
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

/// What the linter concluded about one declaration, kept beside its contract rather than in it.
public struct Assessment: Sendable, Equatable, Codable {
    /// One rule finding, addressed by line so a view can place it next to the contract it breaks.
    public struct Finding: Sendable, Equatable, Codable {
        /// The rule's code as reports print it, such as `missing-doc`.
        public var rule: String
        /// The 1-based source line the finding points at.
        public var line: Int
        /// The fix in one or two sentences, quoting the fragment it names.
        public var message: String
        /// How loudly the house style reports it.
        public var severity: Diagnostic.Severity
    }

    /// `true` when the house style demands a doc comment on the declaration.
    public var requiresDoc: Bool
    /// Why the declaration is excused from the harness, in words, or `nil` when it is not.
    public var exemption: String?
    /// What the rules found, in source order; empty when there is nothing to fix.
    public var findings: [Finding]
}

/// A module's page: the `README.md` in its folder, `Sources/<Module>/README.md`, read the way gloss reads a
/// doc comment, so the same rules check it and the app can lead with it.
///
/// A page is short by design: its title names the module, a summary says what the module does and why,
/// an Overview places it among the others, and Topics group the types a reader reaches for.
///
/// ```markdown
/// # GlossRead
///
/// Parses the sources once, so the lint and the model read the same declarations.
///
/// ## Overview
///
/// Every other module starts from a ``Reading``.
///
/// ## Topics
///
/// ### Reading
///
/// - ``Reading``
/// - ``DeclarationReader``
/// ```
public struct ModulePage: Sendable, Equatable, Codable {
    /// One group of the page's Topics: its `###` title, the lead under it, and the symbols it links.
    public struct Topic: Sendable, Equatable, Codable {
        /// The group's title.
        public var title: String
        /// The 1-based line of the group's heading.
        public var line: Int
        /// The prose between the heading and the first linked item, line by line.
        public var lead: [DocLine]
        /// What the group's items link, as written between double backticks, in order.
        public var links: [String]
    }

    /// The page's path, as it is reported.
    public var file: String
    /// The module the title names, as in `# GlossRead`, or `nil` when the page has no title.
    public var module: String?
    /// The 1-based line of the title, or 1 when the page has none.
    public var titleLine: Int
    /// The summary: the first paragraph after the title.
    public var summary: [DocLine]
    /// The Overview's paragraphs, blank lines between them kept as empty lines.
    public var overview: [DocLine]
    /// The Topics' groups, in order.
    public var topics: [Topic]
    /// Every line of the page, so its links can be checked wherever they are.
    public var lines: [DocLine]

    /// Whether a path is a module page: the `README.md` right in a module's folder under `Sources`.
    ///
    /// - Parameter path: A source path.
    /// - Returns: `true` for `Sources/<Module>/README.md`, and `false` for any other Markdown file.
    public static func isPage(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return parts.count >= 3 && parts[parts.count - 1] == "README.md" && parts[parts.count - 3] == "Sources"
    }

    /// Where a module keeps its page in SwiftPM's layout.
    ///
    /// - Parameters:
    ///   - module: The module's name.
    ///   - sources: The `Sources` folder's path, as the module's files are reported under it.
    /// - Returns: `<sources>/<module>/README.md`.
    public static func path(forModule module: String, in sources: String) -> String {
        "\(sources)/\(module)/README.md"
    }

    /// Reads a page's Markdown.
    ///
    /// - Parameters:
    ///   - text: The page's contents.
    ///   - file: The path reported for it.
    /// - Returns: The page, its parts empty where the Markdown has none of them.
    public static func parse(_ text: String, file: String) -> ModulePage {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
            DocLine(text: String($0.element), line: $0.offset + 1)
        }
        var page = ModulePage(file: file, module: nil, titleLine: 1, summary: [], overview: [], topics: [], lines: lines)
        enum Section { case head, summary, overview, topics, other }
        var section = Section.head
        var fence = false
        for line in lines {
            let text = line.text.trimmed
            if text.hasPrefix("```") { fence.toggle() }
            if !fence, text.hasPrefix("# "), section == .head {
                page.titleLine = line.line
                // The title is the module's name, written plainly or as a link.
                let name = text.dropFirst(2).replacingOccurrences(of: "`", with: "").trimmed
                page.module = name.isEmpty ? nil : name
                section = .summary
                continue
            }
            if !fence, text.hasPrefix("## ") {
                let name = text.dropFirst(3).trimmed
                section = name == "Overview" ? .overview : name == "Topics" ? .topics : .other
                continue
            }
            switch section {
            case .head, .other:
                break
            case .summary:
                // The summary is the first paragraph; a blank line after it ends it.
                if text.isEmpty { if !page.summary.isEmpty { section = .other } } else { page.summary.append(line) }
            case .overview:
                if !(text.isEmpty && page.overview.isEmpty) { page.overview.append(DocLine(text: text, line: line.line)) }
            case .topics:
                if !fence, text.hasPrefix("### ") {
                    page.topics.append(Topic(title: String(text.dropFirst(4)).trimmed, line: line.line, lead: [], links: []))
                } else if !page.topics.isEmpty, text.hasPrefix("- ") {
                    if let link = Self.link(in: text) { page.topics[page.topics.count - 1].links.append(link) }
                } else if !page.topics.isEmpty, !text.isEmpty, page.topics[page.topics.count - 1].links.isEmpty {
                    page.topics[page.topics.count - 1].lead.append(DocLine(text: text, line: line.line))
                }
            }
        }
        while page.overview.last?.text.isEmpty == true { page.overview.removeLast() }
        return page
    }

    /// The overview's paragraphs, each joined onto one line.
    public var overviewParagraphs: [String] {
        overview.split { $0.text.isEmpty }.map { $0.map(\.text).joined(separator: " ") }
    }

    /// The first double-backticked link on a line.
    ///
    /// - Parameter text: A line of the page.
    /// - Returns: What the link names, or `nil` when the line has none.
    static func link(in text: String) -> String? {
        guard let open = text.range(of: "``") else { return nil }
        let rest = text[open.upperBound...]
        guard let close = rest.range(of: "``") else { return nil }
        let link = rest[..<close.lowerBound].trimmed
        return link.isEmpty ? nil : link
    }
}

/// A `- Keyword:` callout as written in the markup block, with any nested entries.
///
/// The keyword is kept as written so the capitalization rule can quote it back verbatim.
public struct Callout: Sendable, Equatable {
    /// The keyword as written, capitalization included; compare through ``Callout/normalizedKeyword``.
    public var keyword: String
    /// The name in a `- Parameter name:` callout, or `nil` for every other form.
    public var argument: String?
    /// The text after the colon, with indented continuation lines joined by spaces; empty for a bare
    /// `- Parameters:`.
    public var text: String
    /// The 1-based source line of the callout.
    public var line: Int
    /// The `- name: text` lines nested under a `- Parameters:` callout; empty for every other keyword.
    public var entries: [Entry]

    /// One `- name: text` line nested under `- Parameters:`.
    public struct Entry: Sendable, Equatable {
        /// The parameter name before the colon, a single word.
        public var name: String
        /// The description after the colon, with indented continuation lines joined by spaces.
        public var text: String
        /// The 1-based source line of the entry.
        public var line: Int
    }

    /// The keyword lowercased, so `- returns:` and `- Returns:` compare equal.
    public var normalizedKeyword: String { keyword.lowercased() }
}

/// The three-section reading of a doc comment: summary, markup block, notes.
///
/// Parsing structure once, up front, lets every rule ask a direct question instead of re-scanning lines.
public struct DocStructure: Sendable, Equatable {
    /// The opening lines up to the first blank line or callout; empty when the comment opens with one.
    public var summary: [DocLine]
    /// Every top-level callout in source order, including any that follow prose.
    public var callouts: [Callout]
    /// The first top-level callout that appears after prose, if the markup block was split.
    public var calloutAfterProse: Callout?
    /// Prose lines outside the summary and the markup block, in source order: the notes.
    public var notes: [DocLine] = []

    /// Every callout keyword Apple's symbol-documentation markup recognizes, lowercased.
    public static let knownKeywords: Set<String> = [
        "parameters", "parameter", "returns", "throws", "note", "important", "precondition",
        "postcondition", "warning", "attention", "author", "authors", "bug", "complexity",
        "copyright", "date", "experiment", "invariant", "remark", "requires", "seealso", "since",
        "tip", "todo", "version", "mutatingvariant", "nonmutatingvariant", "localizationkey", "tag"
    ]

    /// Splits a comment into summary, callouts, and the point where prose interrupted markup. A callout
    /// line is `- Keyword:` or `- Keyword argument:` at column zero, an indented `- name:` beneath
    /// `- Parameters:` is an entry of it, and anything else is prose.
    ///
    /// - Parameter doc: The comment to read.
    /// - Returns: The parsed structure; an empty summary means the comment opened with a blank or a callout.
    public static func parse(_ doc: DocComment) -> DocStructure {
        var summary: [DocLine] = []
        var callouts: [Callout] = []
        var calloutAfterProse: Callout?
        var notes: [DocLine] = []
        var index = 0
        let lines = doc.lines

        while index < lines.count, !lines[index].text.isBlank, Self.callout(in: lines[index]) == nil {
            summary.append(lines[index])
            index += 1
        }

        var seenProseAfterSummary = false
        var inCallout = false
        let code = doc.codeLines
        while index < lines.count {
            let line = lines[index]
            index += 1
            // Fenced code is quoted text: kept whole as a note, blank lines included, and never a callout.
            if code.contains(line.line) {
                inCallout = false
                seenProseAfterSummary = true
                notes.append(line)
                continue
            }
            if line.text.isBlank { continue }
            if let parsed = Self.callout(in: line) {
                if seenProseAfterSummary, calloutAfterProse == nil { calloutAfterProse = parsed }
                callouts.append(parsed)
                inCallout = true
                continue
            }
            if inCallout {
                var last = callouts.removeLast()
                defer { callouts.append(last) }
                let indented = line.text.first == " " || line.text.first == "\t"
                if last.normalizedKeyword == "parameters", let entry = Self.entry(in: line) {
                    last.entries.append(entry)
                    continue
                }
                if indented {
                    if let entry = last.entries.popLast() {
                        last.entries.append(.init(name: entry.name, text: entry.text + " " + line.text.trimmed, line: entry.line))
                    } else {
                        last.text += " " + line.text.trimmed
                    }
                    continue
                }
            }
            inCallout = false
            seenProseAfterSummary = true
            notes.append(line)
        }
        return DocStructure(summary: summary, callouts: callouts, calloutAfterProse: calloutAfterProse, notes: notes)
    }

    /// Reads a top-level `- Keyword:` / `- Keyword argument:` line. Only known keywords and the
    /// `Parameter name:` two-word form qualify, so a prose bullet such as `- the first case` stays prose.
    ///
    /// - Parameter line: The line to read, unindented.
    /// - Returns: The callout, or `nil` when the line is not one.
    static func callout(in line: DocLine) -> Callout? {
        let text = line.text
        guard text.hasPrefix("- ") else { return nil }
        let body = text.dropFirst(2)
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let head = body[..<colon].split(separator: " ", omittingEmptySubsequences: true)
        guard let keyword = head.first, head.count <= 2 else { return nil }
        let normalized = keyword.lowercased()
        let argument = head.count == 2 ? String(head[1]) : nil
        let known = Self.knownKeywords.contains(normalized) || Self.commonMisspellings[normalized] != nil
        guard known else { return nil }
        if argument != nil, normalized != "parameter" { return nil }
        let rest = body[body.index(after: colon)...].trimmed
        return Callout(keyword: String(keyword), argument: argument, text: rest, line: line.line, entries: [])
    }

    /// Reads an indented `- name: text` entry beneath `- Parameters:`.
    ///
    /// - Parameter line: The line to read; leading indentation is ignored.
    /// - Returns: The entry, or `nil` when the line is not shaped like one.
    static func entry(in line: DocLine) -> Callout.Entry? {
        let text = line.text.trimmed
        guard text.hasPrefix("- ") else { return nil }
        let body = text.dropFirst(2)
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let name = body[..<colon].trimmed
        guard !name.isEmpty, !name.contains(" ") else { return nil }
        return .init(name: name, text: body[body.index(after: colon)...].trimmed, line: line.line)
    }

    /// Misspellings the report corrects by name, so the fix is one edit away.
    public static let commonMisspellings: [String: String] = [
        "return": "Returns", "param": "Parameter", "params": "Parameters", "throw": "Throws",
        "parameters:": "Parameters", "notes": "Note", "see": "SeeAlso", "see also": "SeeAlso"
    ]
}

extension StringProtocol {
    /// The text with leading and trailing whitespace removed.
    package var trimmed: String { String(self.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed()) }
    /// `true` when the text is empty or only whitespace.
    package var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

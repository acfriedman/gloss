/// A `- Keyword:` callout as written in the markup block, with any nested entries.
///
/// The keyword is kept as written so the capitalization rule can quote it back verbatim.
public struct Callout: Sendable, Equatable {
    public var keyword: String
    public var argument: String?
    public var text: String
    public var line: Int
    public var entries: [Entry]

    /// One `- name: text` line nested under `- Parameters:`.
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var text: String
        public var line: Int
    }

    /// The keyword lowercased, so `- returns:` and `- Returns:` compare equal.
    public var normalizedKeyword: String { keyword.lowercased() }
}

/// The three-section reading of a doc comment: summary, markup block, notes.
///
/// Parsing structure once, up front, lets every rule ask a direct question instead of re-scanning lines.
public struct DocStructure: Sendable, Equatable {
    public var summary: [DocLine]
    public var callouts: [Callout]
    /// The first top-level callout that appears after prose, if the markup block was split.
    public var calloutAfterProse: Callout?

    /// Every callout keyword Apple's symbol-documentation markup recognizes, lowercased.
    public static let knownKeywords: Set<String> = [
        "parameters", "parameter", "returns", "throws", "note", "important", "precondition",
        "postcondition", "warning", "attention", "author", "authors", "bug", "complexity",
        "copyright", "date", "experiment", "invariant", "remark", "requires", "seealso", "since",
        "tip", "todo", "version", "mutatingvariant", "nonmutatingvariant", "localizationkey", "tag"
    ]

    /// Splits a comment into summary, callouts, and the point where prose interrupted markup.
    ///
    /// A callout line is `- Keyword:` or `- Keyword argument:` at column zero; an indented `- name:`
    /// beneath `- Parameters:` is an entry of it; anything else is prose.
    /// - Parameter doc: The comment to read.
    /// - Returns: The parsed structure; an empty summary means the comment opened with a blank or a callout.
    public static func parse(_ doc: DocComment) -> DocStructure {
        var summary: [DocLine] = []
        var callouts: [Callout] = []
        var calloutAfterProse: Callout?
        var index = 0
        let lines = doc.lines

        while index < lines.count, !lines[index].text.isBlank, Self.callout(in: lines[index]) == nil {
            summary.append(lines[index])
            index += 1
        }

        var seenProseAfterSummary = false
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.text.isBlank { continue }
            if let parsed = Self.callout(in: line) {
                if seenProseAfterSummary, calloutAfterProse == nil { calloutAfterProse = parsed }
                callouts.append(parsed)
                continue
            }
            if !callouts.isEmpty, !seenProseAfterSummary {
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
            seenProseAfterSummary = true
        }
        return DocStructure(summary: summary, callouts: callouts, calloutAfterProse: calloutAfterProse)
    }

    /// Reads a top-level `- Keyword:` / `- Keyword argument:` line.
    ///
    /// Only known keywords and the `Parameter name:` two-word form qualify, so a prose bullet such as
    /// `- the first case` stays prose.
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
    var trimmed: String { String(self.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed()) }
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

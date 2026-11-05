import SwiftSyntax

/// One line of a doc comment with its `///` prefix, or a `/** */` comment's delimiters and leading
/// stars, removed, tagged with its source line.
///
/// Keeping the line number per entry lets a rule point at the exact offending line, not the block.
public struct DocLine: Sendable, Equatable, Codable {
    /// The line with its `///` prefix and one following space removed; deeper indentation is kept.
    public var text: String
    /// The 1-based source line the text came from.
    public var line: Int

    /// Creates a line of comment text tagged with its source line.
    ///
    /// - Parameters:
    ///   - text: The line with its `///` prefix and one following space removed; deeper indentation is kept.
    ///   - line: The 1-based source line the text came from.
    public init(text: String, line: Int) {
        self.text = text
        self.line = line
    }
}

/// The documentation attached to one declaration, before any rule has looked at it.
///
/// Extraction is separate from analysis so the parser can be tested on plain strings.
public struct DocComment: Sendable, Equatable {
    /// The comment's lines in source order, a `/** */` comment's as Xcode reads them.
    public var lines: [DocLine]
    /// `true` when the source used `/** */`, which Swift accepts and gloss's own house style flags as
    /// `block-doc`; its lines are read all the same.
    public var isBlockComment: Bool

    /// The source lines of fenced code: each fence of three backticks or more, and everything
    /// between an opening fence and its close. Code is quoted, not prose, so no rule reads it.
    public var codeLines: Set<Int> {
        var lines = Set<Int>()
        var fence: String?
        for line in self.lines {
            let trimmed = line.text.trimmed
            let run = String(trimmed.prefix { $0 == "`" })
            if let open = fence {
                lines.insert(line.line)
                if run.count >= open.count, trimmed.allSatisfy({ $0 == "`" }) { fence = nil }
            } else if run.count >= 3 {
                lines.insert(line.line)
                fence = run
            }
        }
        return lines
    }

    /// Creates a comment from lines already stripped of their `///` prefixes.
    ///
    /// - Parameters:
    ///   - lines: The comment text in source order.
    ///   - isBlockComment: `true` when the source used `/** */`.
    public init(lines: [DocLine], isBlockComment: Bool = false) {
        self.lines = lines
        self.isBlockComment = isBlockComment
    }

    /// The source line the comment starts on, or zero for an empty comment.
    public var startLine: Int { lines.first?.line ?? 0 }

    /// Builds a comment from raw `///` text, for tests and tools without a syntax tree. Lines are
    /// numbered from `startLine` so diagnostics in tests read like real ones.
    ///
    /// - Parameters:
    ///   - text: The comment exactly as written, `///` prefixes included.
    ///   - startLine: The source line of the first entry; defaults to 1.
    /// - Returns: The parsed comment, or `nil` when no line carries a `///` prefix.
    public static func parse(_ text: String, startLine: Int = 1) -> DocComment? {
        var lines: [DocLine] = []
        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let stripped = Self.strip(String(raw)) else { continue }
            lines.append(DocLine(text: stripped, line: startLine + offset))
        }
        return lines.isEmpty ? nil : DocComment(lines: lines)
    }

    /// Reads the doc comment immediately preceding `node`, honoring the last contiguous run only. A
    /// blank line or an ordinary `//` comment between the run and the declaration ends the run,
    /// because Xcode stops attributing the comment to the declaration at that point too.
    ///
    /// - Parameters:
    ///   - node: The declaration whose leading trivia holds the comment.
    ///   - converter: Maps trivia positions to source lines for the file the node came from.
    /// - Returns: The comment, or `nil` when the declaration is undocumented.
    public static func leading(_ node: some SyntaxProtocol, converter: SourceLocationConverter) -> DocComment? {
        var position = node.position
        var run: [DocLine] = []
        var sawBlock = false
        for piece in node.leadingTrivia.pieces {
            let line = converter.location(for: position).line
            switch piece {
            case .docLineComment(let text):
                if sawBlock { run.removeAll() }
                sawBlock = false
                run.append(DocLine(text: strip(text) ?? "", line: line))
            case .docBlockComment(let text):
                run = block(text, startLine: line)
                sawBlock = true
            case .newlines(let count), .carriageReturnLineFeeds(let count), .carriageReturns(let count):
                if count > 1 {
                    run.removeAll()
                    sawBlock = false
                }
            case .lineComment, .blockComment:
                run.removeAll()
                sawBlock = false
            default:
                break
            }
            position += piece.sourceLength
        }
        if sawBlock { return DocComment(lines: run, isBlockComment: true) }
        return run.isEmpty ? nil : DocComment(lines: run)
    }

    /// Reads a `/** */` comment's lines as Xcode does: the delimiters dropped, then a leading `*` on every
    /// line when each one has it, else the indentation the lines share.
    ///
    /// - Parameters:
    ///   - text: The comment exactly as written, delimiters included.
    ///   - startLine: The source line the comment opens on.
    /// - Returns: The lines that hold text or lie between lines that do, in source order.
    static func block(_ text: String, startLine: Int) -> [DocLine] {
        var raw = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !raw.isEmpty else { return [] }
        raw[0] = String(raw[0].drop { $0 == " " || $0 == "\t" }.dropFirst(3))
        if let close = raw[raw.count - 1].range(of: "*/", options: .backwards) { raw[raw.count - 1].removeSubrange(close.lowerBound...) }
        func indent(_ line: String) -> Int { line.prefix { $0 == " " || $0 == "\t" }.count }
        let rest = raw.dropFirst().filter { !$0.isBlank }
        let starred = !rest.isEmpty && rest.allSatisfy { $0.drop { $0 == " " || $0 == "\t" }.hasPrefix("*") }
        let shared = rest.map(indent).min() ?? 0
        var lines = raw.enumerated().map { offset, line -> DocLine in
            var body = Substring(line)
            if offset == 0 {
                if body.first == " " { body = body.dropFirst() }
            } else if starred {
                body = body.drop { $0 == " " || $0 == "\t" }.dropFirst()
                if body.first == " " { body = body.dropFirst() }
            } else {
                body = body.dropFirst(min(shared, indent(line)))
            }
            return DocLine(text: String(body.reversed().drop { $0 == " " || $0 == "\t" }.reversed()), line: startLine + offset)
        }
        while lines.first?.text.isBlank == true { lines.removeFirst() }
        while lines.last?.text.isBlank == true { lines.removeLast() }
        return lines
    }

    /// Removes the `///` prefix and at most one following space, preserving deeper indentation. The
    /// one-space rule is what keeps nested `  - name:` entries distinguishable from top-level ones.
    ///
    /// - Parameter raw: One source line, leading whitespace allowed.
    /// - Returns: The comment text, or `nil` when the line is not a `///` line.
    static func strip(_ raw: String) -> String? {
        let trimmed = raw.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("///") else { return nil }
        var body = trimmed.dropFirst(3)
        if body.first == " " { body = body.dropFirst() }
        return String(body)
    }
}

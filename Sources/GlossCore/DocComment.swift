import SwiftSyntax

/// One line of a `///` comment with its `///` prefix removed, tagged with its source line.
///
/// Keeping the line number per entry lets a rule point at the exact offending line, not the block.
public struct DocLine: Sendable, Equatable {
    public var text: String
    public var line: Int

    /// Creates a line of comment text tagged with its source line.
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
    public var lines: [DocLine]
    public var isBlockComment: Bool

    /// Creates a comment from lines already stripped of their `///` prefixes.
    /// - Parameters:
    ///   - lines: The comment text in source order; empty for a block comment.
    ///   - isBlockComment: `true` when the source used `/** */`, which the rules refuse before reading `lines`.
    public init(lines: [DocLine], isBlockComment: Bool = false) {
        self.lines = lines
        self.isBlockComment = isBlockComment
    }

    /// The source line the comment starts on, or zero for an empty comment.
    public var startLine: Int { lines.first?.line ?? 0 }

    /// Builds a comment from raw `///` text, for tests and tools without a syntax tree. Lines are
    /// numbered from `startLine` so diagnostics in tests read like real ones.
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
                sawBlock = false
                run.append(DocLine(text: strip(text) ?? "", line: line))
            case .docBlockComment:
                run.removeAll()
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
        if sawBlock { return DocComment(lines: [], isBlockComment: true) }
        return run.isEmpty ? nil : DocComment(lines: run)
    }

    /// Removes the `///` prefix and at most one following space, preserving deeper indentation. The
    /// one-space rule is what keeps nested `  - name:` entries distinguishable from top-level ones.
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

extension StringProtocol {
    /// The text with leading and trailing whitespace removed.
    package var trimmed: String { String(self.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed()) }
    /// `true` when the text is empty or only whitespace.
    package var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

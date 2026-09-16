/// One rule a doc comment can break, keyed by the code that appears in the report.
///
/// Each case is a single, teachable failure: the message names the fix, never just the fact.
public enum Rule: String, CaseIterable, Sendable {
    case missingDoc = "missing-doc"
    case blockDoc = "block-doc"
    case summaryEmpty = "summary-empty"
    case summarySentences = "summary-sentences"
    case summaryTerminator = "summary-terminator"
    case summaryCapital = "summary-capital"
    case summaryOpener = "summary-opener"
    case markupOrder = "markup-order"
    case markupSpacing = "markup-spacing"
    case symbolLink = "symbol-link"
    case markupCase = "markup-case"
    case markupUnknown = "markup-unknown"
    case parameterMissing = "parameter-missing"
    case parameterUnknown = "parameter-unknown"
    case parameterEmpty = "parameter-empty"
    case parameterForm = "parameter-form"
    case returnsMissing = "returns-missing"
    case returnsUnexpected = "returns-unexpected"
    case returnsEmpty = "returns-empty"
    case throwsMissing = "throws-missing"
    case throwsUnexpected = "throws-unexpected"
    case throwsEmpty = "throws-empty"
    case exemptReason = "exempt-reason"
    case exemptDocumented = "exempt-documented"
}

/// A single violation, addressed the way Xcode and GitHub Actions parse diagnostics.
///
/// Rendering as `file:line:column: error: message [rule]` lets any CI surface the finding unchanged.
public struct Diagnostic: Sendable, Equatable {
    public var file: String
    public var line: Int
    public var column: Int
    public var rule: Rule
    public var message: String

    /// Creates a diagnostic at a source position.
    ///
    /// - Parameters:
    ///   - file: The path as given on the command line.
    ///   - line: The 1-based line: the offending comment line for a doc rule, the declaration for `missing-doc`.
    ///   - column: The 1-based column: 1 for comment lines, the name token's column for declarations.
    ///   - rule: The rule that fired.
    ///   - message: The fix in one or two sentences, quoting the fragment it names.
    public init(file: String, line: Int, column: Int, rule: Rule, message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.rule = rule
        self.message = message
    }

    /// Renders the diagnostic on one line in compiler format. The bracketed rule code at the end keeps
    /// the message human-first while staying greppable.
    ///
    /// - Returns: `file:line:column: error: message [rule]`.
    public var rendered: String {
        "\(file):\(line):\(column): error: \(message) [\(rule.rawValue)]"
    }
}

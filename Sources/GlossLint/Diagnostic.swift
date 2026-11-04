/// One rule a doc comment can break, keyed by the code that appears in the report.
///
/// Each case is a single, teachable failure: the message names the fix, never just the fact.
public enum Rule: String, CaseIterable, Sendable {
    /// A declaration that owes a doc comment has none.
    case missingDoc = "missing-doc"
    /// The doc comment is a `/** */` block instead of `///` lines.
    case blockDoc = "block-doc"
    /// The comment opens with a blank line or a callout, so it has no summary.
    case summaryEmpty = "summary-empty"
    /// The summary has no terminated sentence, or more than two.
    case summarySentences = "summary-sentences"
    /// The summary does not end with a period.
    case summaryTerminator = "summary-terminator"
    /// The summary starts with a lowercase letter.
    case summaryCapital = "summary-capital"
    /// The summary opens with a phrase such as `This method` instead of naming the behavior.
    case summaryOpener = "summary-opener"
    /// A callout appears after prose, splitting the markup block.
    case markupOrder = "markup-order"
    /// The markup block starts on the line right after the summary, with no blank `///` line between.
    case markupSpacing = "markup-spacing"
    /// A single-backticked span names one of the module's own symbols instead of linking it with double
    /// backticks.
    case symbolLink = "symbol-link"
    /// A callout keyword is not capitalized the way DocC spells it, as in `- returns:`.
    case markupCase = "markup-case"
    /// A callout keyword is a common misspelling, such as `- Return:` or `- Param:`.
    case markupUnknown = "markup-unknown"
    /// A parameter of the signature has no entry in the doc.
    case parameterMissing = "parameter-missing"
    /// An entry names something that is not a parameter, or a `- Parameter:` callout names nothing.
    case parameterUnknown = "parameter-unknown"
    /// A parameter entry has an empty description.
    case parameterEmpty = "parameter-empty"
    /// One comment mixes the `- Parameters:` and `- Parameter x:` forms.
    case parameterForm = "parameter-form"
    /// The parameter entries do not follow the signature's order.
    case parameterOrder = "parameter-order"
    /// One parameter has more than one entry.
    case parameterDuplicate = "parameter-duplicate"
    /// A callable that returns a value has no `- Returns:` entry.
    case returnsMissing = "returns-missing"
    /// A callable that returns nothing has a `- Returns:` entry.
    case returnsUnexpected = "returns-unexpected"
    /// The `- Returns:` entry has an empty description.
    case returnsEmpty = "returns-empty"
    /// A throwing callable has no `- Throws:` entry.
    case throwsMissing = "throws-missing"
    /// A callable that does not throw has a `- Throws:` entry.
    case throwsUnexpected = "throws-unexpected"
    /// The `- Throws:` entry has an empty description.
    case throwsEmpty = "throws-empty"
    /// A double-backticked link names nothing the scanned sources declare and no outside module.
    case deadLink = "dead-link"
    /// A `// gloss:exempt` marker gives no reason.
    case exemptReason = "exempt-reason"
    /// A declaration carries both a `// gloss:exempt` marker and a doc comment.
    case exemptDocumented = "exempt-documented"
}

/// A single violation, addressed the way Xcode and GitHub Actions parse diagnostics.
///
/// Rendering as `file:line:column: error: message [rule]` lets any CI surface the finding unchanged.
public struct Diagnostic: Sendable, Equatable {
    /// How loudly a finding is reported, as a project's ``HouseStyle`` sets its rule.
    public enum Severity: String, Sendable, Equatable, Codable {
        /// Reported as `error:`, failing the run.
        case error
        /// Reported as `warning:`, leaving the run passing.
        case warning
    }

    /// The path as given on the command line.
    public var file: String
    /// The 1-based line: the offending comment line for a doc rule, the declaration's line for `missing-doc`,
    /// `block-doc`, and the exemption rules.
    public var line: Int
    /// The 1-based column: 1 for a comment line, the declaration's name or introducing keyword for a finding
    /// on the declaration.
    public var column: Int
    /// The rule that fired, whose code closes the rendered line.
    public var rule: Rule
    /// The fix in one or two sentences, quoting the fragment it names.
    public var message: String
    /// How loudly it is reported; every rule is an error until a style says otherwise.
    public var severity: Severity = .error

    /// Creates a diagnostic at a source position.
    ///
    /// - Parameters:
    ///   - file: The path as given on the command line.
    ///   - line: The 1-based line: the offending comment line for a doc rule, the declaration for `missing-doc`.
    ///   - column: The 1-based column: 1 for comment lines, and for declarations the column of the name, or
    ///     of the keyword for an initializer, subscript, property, or enum case.
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
    /// - Returns: `file:line:column: error: message [rule]`, or `warning:` for a warning.
    public var rendered: String {
        "\(file):\(line):\(column): \(severity.rawValue): \(message) [\(rule.rawValue)]"
    }
}

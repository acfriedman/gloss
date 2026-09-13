/// The rule set, applied to one declaration and its doc comment.
///
/// Every check is a pure function of (`Declaration`, `DocComment`) so the harness can be pinned by
/// literal tests and so the CLI adds nothing but file walking.
public enum Rules {
    /// Runs every rule against one declaration.
    ///
    /// An undocumented declaration yields at most the `missing-doc` finding; the shape rules only
    /// speak once there is a comment to shape.
    /// - Parameters:
    ///   - declaration: The declaration under review.
    ///   - doc: Its doc comment, or `nil` when it has none.
    /// - Returns: Every violation found, in source order.
    public static func check(_ declaration: Declaration, doc: DocComment?) -> [Diagnostic] {
        guard let doc else {
            guard declaration.requiresDoc else { return [] }
            return [diagnostic(declaration, line: declaration.line, column: declaration.column, .missingDoc,
                               "`\(declaration.name)` has no doc comment. Write `///` lines: one sentence for what it does, one for why it exists, then `- Parameter`/`- Returns:`/`- Throws:` entries.")]
        }
        if doc.isBlockComment {
            return [diagnostic(declaration, line: declaration.line, column: declaration.column, .blockDoc,
                               "Use `///` line comments, not `/** */`.")]
        }
        let structure = DocStructure.parse(doc)
        var findings: [Diagnostic] = []
        findings += summaryRules(declaration, doc, structure)
        findings += markupRules(declaration, structure)
        findings += parameterRules(declaration, structure)
        findings += returnsRules(declaration, structure)
        findings += throwsRules(declaration, structure)
        return findings.sorted { ($0.line, $0.column, $0.rule.rawValue) < ($1.line, $1.column, $1.rule.rawValue) }
    }

    // MARK: Summary

    static func summaryRules(_ decl: Declaration, _ doc: DocComment, _ structure: DocStructure) -> [Diagnostic] {
        let line = doc.startLine
        guard !structure.summary.isEmpty else {
            return [diagnostic(decl, line: line, .summaryEmpty,
                               "The doc comment must open with its summary; a blank `///` or a `- Keyword:` line cannot come first.")]
        }
        let text = structure.summary.map(\.text).joined(separator: " ").trimmed
        var findings: [Diagnostic] = []
        let sentences = Sentences.count(in: text)
        if !Sentences.endsWithPeriod(text) {
            findings.append(diagnostic(decl, line: line, .summaryTerminator, "The summary must end with a period."))
        }
        if sentences == 0 || sentences > 2 {
            findings.append(diagnostic(decl, line: line, .summarySentences,
                                       "The summary has \(sentences) sentence\(sentences == 1 ? "" : "s"); write one sentence for what it does and one for why it exists. Move anything more below the markup block."))
        }
        if let first = text.first, first.isLetter, first.isLowercase {
            findings.append(diagnostic(decl, line: line, .summaryCapital, "Start the summary with a capital letter (or a backticked symbol)."))
        }
        if let opener = Self.forbiddenOpener(text) {
            findings.append(diagnostic(decl, line: line, .summaryOpener,
                                       "Do not open with \"\(opener)\"; name the behavior directly (`Records the probe…`, `The domain an event…`)."))
        }
        return findings
    }

    static func forbiddenOpener(_ text: String) -> String? {
        let words = text.split(separator: " ", maxSplits: 2).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard words.count >= 2, ["this", "these"].contains(words[0]) else { return nil }
        let nouns: Set<String> = ["method", "function", "func", "class", "struct", "enum", "protocol", "type", "property",
                                  "initializer", "init", "initialiser", "actor", "value", "variable", "field", "subscript", "case"]
        guard nouns.contains(words[1]) else { return nil }
        return text.split(separator: " ", maxSplits: 2).prefix(2).joined(separator: " ")
    }

    // MARK: Markup block

    static func markupRules(_ decl: Declaration, _ structure: DocStructure) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        if let split = structure.calloutAfterProse {
            findings.append(diagnostic(decl, line: split.line, .markupOrder,
                                       "`- \(split.keyword):` appears after prose. The markup block (`- Parameters:`/`- Returns:`/`- Throws:`…) comes right after the summary; notes go below it."))
        }
        for callout in structure.callouts {
            let normalized = callout.normalizedKeyword
            if let fix = DocStructure.commonMisspellings[normalized] {
                findings.append(diagnostic(decl, line: callout.line, .markupUnknown,
                                           "`- \(callout.keyword):` is not a callout; write `- \(fix):`."))
            } else if let canonical = canonicalSpelling[normalized], canonical != callout.keyword {
                findings.append(diagnostic(decl, line: callout.line, .markupCase,
                                           "Capitalize the callout: `- \(canonical):`, not `- \(callout.keyword):`."))
            }
        }
        return findings
    }

    static let canonicalSpelling: [String: String] = [
        "parameters": "Parameters", "parameter": "Parameter", "returns": "Returns", "throws": "Throws",
        "note": "Note", "important": "Important", "precondition": "Precondition", "postcondition": "Postcondition",
        "warning": "Warning", "attention": "Attention", "author": "Author", "authors": "Authors", "bug": "Bug",
        "complexity": "Complexity", "copyright": "Copyright", "date": "Date", "experiment": "Experiment",
        "invariant": "Invariant", "remark": "Remark", "requires": "Requires", "seealso": "SeeAlso", "since": "Since",
        "tip": "Tip", "todo": "ToDo", "version": "Version", "mutatingvariant": "MutatingVariant",
        "nonmutatingvariant": "NonMutatingVariant", "localizationkey": "LocalizationKey", "tag": "Tag"
    ]

    // MARK: Parameters

    static func parameterRules(_ decl: Declaration, _ structure: DocStructure) -> [Diagnostic] {
        guard let parameters = decl.parameters else { return [] }
        var findings: [Diagnostic] = []
        let grouped = structure.callouts.filter { $0.normalizedKeyword == "parameters" }
        let singles = structure.callouts.filter { $0.normalizedKeyword == "parameter" }
        if !grouped.isEmpty, !singles.isEmpty {
            findings.append(diagnostic(decl, line: singles[0].line, .parameterForm,
                                       "Mixing `- Parameters:` and `- Parameter x:`; use one form for the whole declaration."))
        }
        var written: [(name: String, text: String, line: Int)] = []
        for callout in grouped { written += callout.entries.map { ($0.name, $0.text, $0.line) } }
        for callout in singles {
            guard let name = callout.argument else {
                findings.append(diagnostic(decl, line: callout.line, .parameterUnknown,
                                           "`- Parameter:` names no parameter; write `- Parameter <name>: <contract>`."))
                continue
            }
            written.append((name, callout.text, callout.line))
        }
        let signature = "\(decl.name)(\(parameters.map { ($0.label ?? "_") + ":" }.joined()))"
        for parameter in parameters where !written.contains(where: { parameter.matches($0.name) }) {
            findings.append(diagnostic(decl, line: decl.docLineForParameters(structure), .parameterMissing,
                                       "Parameter `\(parameter.name)` of `\(signature)` is not documented. Add `- Parameter \(parameter.name): <what it is, its range or nil meaning>`."))
        }
        for entry in written {
            if !parameters.contains(where: { $0.matches(entry.name) }) {
                let names = parameters.map(\.name).joined(separator: ", ")
                findings.append(diagnostic(decl, line: entry.line, .parameterUnknown,
                                           "`\(entry.name)` is not a parameter of `\(signature)`; its parameters are: \(names.isEmpty ? "none" : names)."))
            } else if entry.text.isBlank {
                findings.append(diagnostic(decl, line: entry.line, .parameterEmpty,
                                           "Parameter `\(entry.name)` has an empty description; state its contract (what it is, its range, what nil or empty means)."))
            }
        }
        return findings
    }

    // MARK: Returns / Throws

    static func returnsRules(_ decl: Declaration, _ structure: DocStructure) -> [Diagnostic] {
        guard decl.parameters != nil else { return [] }
        let returns = structure.callouts.filter { $0.normalizedKeyword == "returns" }
        if decl.returnsValue {
            guard let first = returns.first else {
                return [diagnostic(decl, line: decl.docLineForParameters(structure), .returnsMissing,
                                   "`\(decl.name)` returns a value but has no `- Returns:` entry; say what comes back and what a nil, empty, or sentinel result means.")]
            }
            if first.text.isBlank {
                return [diagnostic(decl, line: first.line, .returnsEmpty, "`- Returns:` has an empty description.")]
            }
            return []
        }
        if let stray = returns.first {
            return [diagnostic(decl, line: stray.line, .returnsUnexpected,
                               "`\(decl.name)` returns nothing; remove the `- Returns:` entry.")]
        }
        return []
    }

    static func throwsRules(_ decl: Declaration, _ structure: DocStructure) -> [Diagnostic] {
        guard decl.parameters != nil else { return [] }
        let throwsEntries = structure.callouts.filter { $0.normalizedKeyword == "throws" }
        if decl.throwsErrors {
            guard let first = throwsEntries.first else {
                return [diagnostic(decl, line: decl.docLineForParameters(structure), .throwsMissing,
                                   "`\(decl.name)` throws but has no `- Throws:` entry; name each error and what triggers it.")]
            }
            if first.text.isBlank {
                return [diagnostic(decl, line: first.line, .throwsEmpty, "`- Throws:` has an empty description.")]
            }
            return []
        }
        if let stray = throwsEntries.first {
            return [diagnostic(decl, line: stray.line, .throwsUnexpected,
                               "`\(decl.name)` does not throw; remove the `- Throws:` entry.")]
        }
        return []
    }

    // MARK: Helpers

    static func diagnostic(_ decl: Declaration, line: Int, column: Int = 1, _ rule: Rule, _ message: String) -> Diagnostic {
        Diagnostic(file: decl.file, line: line, column: column, rule: rule, message: message)
    }
}

extension Declaration {
    /// The line a missing markup entry should be reported on: after the last callout, else the summary.
    /// - Parameter structure: The parsed comment.
    /// - Returns: A line inside the comment, never the declaration itself.
    func docLineForParameters(_ structure: DocStructure) -> Int {
        structure.callouts.last?.line ?? structure.summary.last?.line ?? line
    }
}

/// Sentence counting that ignores code spans and common abbreviations.
///
/// Counting naively on `.` would split `e.g.` and `Foo.bar()`; the summary rule is only fair if it
/// counts the way a reader does.
public enum Sentences {
    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "vs", "cf", "approx", "no", "fig"]

    /// Counts sentences in `text`, treating `.`, `!`, and `?` followed by whitespace or the end as terminators.
    /// - Parameter text: A summary paragraph; backticked spans are ignored wholesale.
    /// - Returns: The number of terminated sentences, which is zero for a bare fragment.
    public static func count(in text: String) -> Int {
        let plain = Array(stripCodeSpans(text))
        var count = 0
        var index = 0
        while index < plain.count {
            let char = plain[index]
            if ".!?".contains(char) {
                var end = index
                while end + 1 < plain.count, ".!?".contains(plain[end + 1]) { end += 1 }
                let atEnd = end + 1 >= plain.count || plain[end + 1].isWhitespace
                if atEnd, !isAbbreviation(plain, before: index) { count += 1 }
                index = end + 1
                continue
            }
            index += 1
        }
        return count
    }

    /// Whether `text` ends with a period, after dropping a trailing code span or closing quote.
    /// - Parameter text: A summary paragraph.
    /// - Returns: `true` when the last visible character is `.`.
    public static func endsWithPeriod(_ text: String) -> Bool {
        let stripped = stripCodeSpans(text).trimmed
        var chars = Substring(stripped)
        while let last = chars.last, "\"')”".contains(last) { chars = chars.dropLast() }
        return chars.last == "."
    }

    static func stripCodeSpans(_ text: String) -> String {
        var out = ""
        var inCode = false
        for char in text {
            if char == "`" { inCode.toggle(); out.append("`"); continue }
            if !inCode { out.append(char) }
        }
        return out
    }

    static func isAbbreviation(_ chars: [Character], before index: Int) -> Bool {
        var start = index
        while start > 0, chars[start - 1].isLetter || chars[start - 1] == "." { start -= 1 }
        let word = String(chars[start..<index]).lowercased()
        return abbreviations.contains(word)
    }
}

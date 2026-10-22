/// The rule set, applied to one declaration and its doc comment.
///
/// Every check is a pure function of (`Declaration`, `DocComment`) so the harness can be pinned by
/// literal tests and so the CLI adds nothing but file walking.
public enum Rules {
    /// Runs every rule against one declaration. An undocumented declaration yields at most the
    /// `missing-doc` finding; the shape rules only speak once there is a comment to shape, and a
    /// memberwise initializer gets only the summary and markup rules, never the parameter ones.
    ///
    /// - Parameters:
    ///   - declaration: The declaration under review.
    ///   - doc: Its doc comment, or `nil` when it has none.
    /// - Returns: Every violation found, in source order.
    public static func check(_ declaration: Declaration, doc: DocComment?) -> [Diagnostic] {
        switch declaration.exemption {
        case .knownRequirement:
            return []
        case .marker(let reason):
            if reason.isBlank {
                return [diagnostic(declaration, line: declaration.line, column: declaration.column, .exemptReason,
                                   "`// gloss:exempt` needs a reason: `// gloss:exempt implements Foo.bar, documented there`.")]
            }
            if doc != nil {
                return [diagnostic(declaration, line: declaration.line, column: declaration.column, .exemptDocumented,
                                   "`\(declaration.name)` is both exempted and documented; keep one. Drop the marker if the doc is real.")]
            }
            return []
        case .conformanceExtension, .memberwiseInit, .none:
            break
        }
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
        findings += symbolLinkRules(declaration, doc)
        findings += markupRules(declaration, structure)
        if declaration.exemption != .memberwiseInit {
            findings += parameterRules(declaration, structure)
            findings += returnsRules(declaration, structure)
            findings += throwsRules(declaration, structure)
        }
        return findings.sorted { ($0.line, $0.column, $0.rule.rawValue) < ($1.line, $1.column, $1.rule.rawValue) }
    }

    // MARK: Summary

    /// Checks the summary paragraph: present, one or two sentences, terminated, capitalized, and not
    /// opening with `This method`. Every finding anchors to the comment's first line.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - doc: Its comment, for the line the findings anchor to.
    ///   - structure: The parsed comment.
    /// - Returns: The summary findings; one paragraph can break several rules at once.
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
                                       "Do not open with \"\(opener)\"; name the behavior directly (`Stores the item…`, `The queue an item…`)."))
        }
        return findings
    }

    /// Detects a summary that opens with `This method`, `This class`, and the like.
    ///
    /// - Parameter text: The summary paragraph.
    /// - Returns: The two offending words as written, or `nil` when the opener is fine.
    static func forbiddenOpener(_ text: String) -> String? {
        let words = text.split(separator: " ", maxSplits: 2).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard words.count >= 2, ["this", "these"].contains(words[0]) else { return nil }
        let nouns: Set<String> = ["method", "function", "func", "class", "struct", "enum", "protocol", "type", "property",
                                  "initializer", "init", "initialiser", "actor", "value", "variable", "field", "subscript", "case"]
        guard nouns.contains(words[1]) else { return nil }
        return text.split(separator: " ", maxSplits: 2).prefix(2).joined(separator: " ")
    }

    // MARK: Symbol links

    /// Checks that a span naming one of the module's own symbols is a DocC link, not plain code.
    /// Only the two shapes a reader always means as a reference are checked, a call with its argument
    /// labels and a type path ending in a member, so literals and prose code stay untouched.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - doc: Its comment; every line is scanned, notes included.
    /// - Returns: One finding per single-backticked reference, naming the link form to write.
    static func symbolLinkRules(_ decl: Declaration, _ doc: DocComment) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        for line in doc.lines {
            for span in SymbolReference.singleBacktickSpans(in: line.text) where SymbolReference.isReference(span) {
                findings.append(diagnostic(decl, line: line.line, .symbolLink,
                                           "`\(span)` names a symbol; write ``\(SymbolReference.linkForm(span))`` so DocC links it. Single backticks are for literals, keywords, and other modules' symbols."))
            }
        }
        return findings
    }

    // MARK: Markup block

    /// Checks callout placement and spelling: the block must follow the summary after one blank line,
    /// and keywords must be capitalized and real.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - structure: The parsed comment.
    /// - Returns: One finding for a misplaced block and one per misspelled keyword.
    static func markupRules(_ decl: Declaration, _ structure: DocStructure) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        if let first = structure.callouts.first, let summaryEnd = structure.summary.last,
           first.line == summaryEnd.line + 1 {
            findings.append(diagnostic(decl, line: first.line, .markupSpacing,
                                       "Leave one blank `///` line between the summary and `- \(first.keyword):`."))
        }
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

    /// Checks that every parameter has one documented entry, all in one form. A declaration without a
    /// parameter list yields nothing.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - structure: The parsed comment.
    /// - Returns: Findings for missing, unknown, empty, and mixed-form entries.
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

    /// Checks that `- Returns:` is present exactly when the callable returns a value, and is not empty.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - structure: The parsed comment.
    /// - Returns: At most one finding; nothing for a declaration without a parameter list.
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

    /// Checks that `- Throws:` is present exactly when the callable throws, and is not empty.
    ///
    /// - Parameters:
    ///   - decl: The declaration under review.
    ///   - structure: The parsed comment.
    /// - Returns: At most one finding; nothing for a declaration without a parameter list.
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

    /// Builds a diagnostic in the declaration's file.
    ///
    /// - Parameters:
    ///   - decl: The declaration, which supplies the file.
    ///   - line: The line to report.
    ///   - column: The column to report; 1, the default, for a comment line.
    ///   - rule: The rule that fired.
    ///   - message: The fix, quoting the fragment it names.
    /// - Returns: The diagnostic, ready to render.
    static func diagnostic(_ decl: Declaration, line: Int, column: Int = 1, _ rule: Rule, _ message: String) -> Diagnostic {
        Diagnostic(file: decl.file, line: line, column: column, rule: rule, message: message)
    }
}

extension Declaration {
    /// The line a missing markup entry should be reported on: after the last callout, else the summary.
    ///
    /// - Parameter structure: The parsed comment.
    /// - Returns: A line inside the comment, never the declaration itself.
    func docLineForParameters(_ structure: DocStructure) -> Int {
        structure.callouts.last?.line ?? structure.summary.last?.line ?? line
    }
}

/// Recognition of the code spans that DocC would only link if written with double backticks.
///
/// A reference is recognized by shape alone: a call-style name with argument labels, or a
/// capitalized type path ending in a lowercase member. A bare type name is left alone, since the
/// same spelling names Foundation's types as often as the module's own.
public enum SymbolReference {
    /// Types whose members no module-local DocC link can resolve, so a dotted path under them is
    /// plain code. Extend it when a new framework's symbols start appearing in docs.
    public static let externalPrefixes: Set<String> = [
        "Swift", "Foundation", "Dispatch", "Combine", "XCTest", "Testing", "CoreData", "SwiftUI", "UIKit",
        "AppKit", "NotificationCenter", "DispatchQueue", "DispatchGroup", "DispatchTime", "Thread",
        "ProcessInfo", "FileManager", "URLSession", "URLProtocol", "URLRequest", "URL", "JSONEncoder",
        "JSONDecoder", "Date", "Data", "Task", "MainActor", "NSObject", "Bundle", "RunLoop", "Timer",
        "OperationQueue", "UserDefaults", "NSLock", "NSManagedObjectContext", "NSPersistentContainer",
        "String", "Array", "Dictionary", "Set", "Optional", "Result", "Int", "Double", "Bool", "Character"
    ]

    /// Extensions that make a dotted span a file name rather than a type path.
    public static let fileExtensions: Set<String> = ["swift", "json", "md", "yml", "yaml", "gz", "txt", "plist", "html", "xcodeproj", "h", "m"]

    /// Whether a span is one of the two reference shapes and not under an external type.
    ///
    /// - Parameter span: The text between single backticks.
    /// - Returns: `true` for a call with argument labels, with or without a type prefix, and for a
    ///   capitalized type path ending in a lowercase member; `false` otherwise.
    public static func isReference(_ span: String) -> Bool {
        let isCall = span.wholeMatch(of: /(?:[A-Z][A-Za-z0-9_]*\.)*[a-z_][A-Za-z0-9_]*\([A-Za-z0-9_:]*\)/) != nil
        let isMember = span.wholeMatch(of: /[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*\.[a-z_][A-Za-z0-9_]*/) != nil
        guard isCall || isMember else { return false }
        let segments = span.split(separator: ".").map(String.init)
        if let last = segments.last, fileExtensions.contains(last) { return false }
        return !externalPrefixes.contains(segments[0])
    }

    /// The DocC spelling of a reference: dots between path segments become slashes.
    ///
    /// - Parameter span: A span `isReference` accepted.
    /// - Returns: The path to place between double backticks.
    public static func linkForm(_ span: String) -> String {
        span.replacingOccurrences(of: ".", with: "/")
    }

    /// Extracts the contents of every single-backtick span, ignoring spans opened by longer runs.
    ///
    /// - Parameter text: One doc line.
    /// - Returns: The span bodies in order, without their backticks.
    static func singleBacktickSpans(in text: String) -> [String] {
        let chars = Array(text)
        var spans: [String] = []
        var index = 0
        while index < chars.count {
            guard chars[index] == "`" else { index += 1; continue }
            let run = Sentences.backtickRun(chars, at: index)
            var search = index + run
            var close: Int?
            while search < chars.count, close == nil {
                guard chars[search] == "`" else { search += 1; continue }
                let candidate = Sentences.backtickRun(chars, at: search)
                if candidate == run { close = search } else { search += candidate }
            }
            guard let close else { index += run; continue }
            if run == 1 { spans.append(String(chars[(index + 1)..<close])) }
            index = close + run
        }
        return spans
    }
}

/// Sentence counting that ignores code spans and common abbreviations.
///
/// Counting naively on `.` would split `e.g.` and a dotted call; the summary rule is only fair if it
/// counts the way a reader does.
public enum Sentences {
    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "vs", "cf", "approx", "no", "fig"]

    /// Counts sentences in `text`, treating `.`, `!`, and `?` followed by whitespace or the end as terminators.
    ///
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
    ///
    /// - Parameter text: A summary paragraph.
    /// - Returns: `true` when the last visible character is `.`.
    public static func endsWithPeriod(_ text: String) -> Bool {
        let stripped = stripCodeSpans(text).trimmed
        var chars = Substring(stripped)
        while let last = chars.last, "\"')”".contains(last) { chars = chars.dropLast() }
        return chars.last == "."
    }

    /// Replaces every code span with a single backtick, so its contents cannot end or start a sentence.
    /// A span opened by a run of N backticks closes only on a run of exactly N, as CommonMark reads it,
    /// so a double-backtick span may contain a literal backtick.
    ///
    /// - Parameter text: A summary paragraph.
    /// - Returns: The paragraph with each span collapsed; an unmatched run is kept as literal text.
    static func stripCodeSpans(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == "`" else { out.append(chars[index]); index += 1; continue }
            let run = backtickRun(chars, at: index)
            var search = index + run
            var close: Int?
            while search < chars.count, close == nil {
                guard chars[search] == "`" else { search += 1; continue }
                let candidate = backtickRun(chars, at: search)
                if candidate == run { close = search } else { search += candidate }
            }
            if let close {
                out.append("`")
                index = close + run
            } else {
                out.append(String(repeating: "`", count: run))
                index += run
            }
        }
        return out
    }

    /// Counts the consecutive backticks starting at `index`.
    ///
    /// - Parameters:
    ///   - chars: The paragraph as characters.
    ///   - index: A position holding a backtick.
    /// - Returns: The run length, at least one.
    static func backtickRun(_ chars: [Character], at index: Int) -> Int {
        var end = index
        while end < chars.count, chars[end] == "`" { end += 1 }
        return end - index
    }

    /// Whether the period at `index` closes an abbreviation such as `e.g.` rather than a sentence.
    ///
    /// - Parameters:
    ///   - chars: The paragraph, code spans already stripped.
    ///   - index: The position of the period.
    /// - Returns: `true` when the letters before the period spell a listed abbreviation.
    static func isAbbreviation(_ chars: [Character], before index: Int) -> Bool {
        var start = index
        while start > 0, chars[start - 1].isLetter || chars[start - 1] == "." { start -= 1 }
        let word = String(chars[start..<index]).lowercased()
        return abbreviations.contains(word)
    }
}

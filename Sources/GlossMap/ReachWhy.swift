import GlossRead
import GlossLint
import GlossModel

/// Why a change reaches a type, in two short answers: why the thing it relies on changed, from the
/// branch's story, and why it relies on that thing, from the docs where it does.
///
/// Each answer leads with at most two sentences and keeps the rest to unfold, so a reader zoomed in on
/// one reach takes in one thought at a time. Both come from text already written: the story's notes and
/// themes, or the commits behind the change, and the doc entries the house style asks for at each use.
public struct ReachWhy: Sendable, Equatable {
    /// One answer: its lead, where it was written, and what follows the lead there.
    public struct Answer: Sendable, Equatable {
        /// At most two sentences.
        public var lead: String
        /// Where the answer was written, such as `the note on Cart/total()` or `charge(_:)'s parameter
        /// amount`.
        public var source: String
        /// The rest of what was written there, paragraph by paragraph; empty when the lead is all of it.
        public var more: [String]
    }

    /// Why one declaration relies on what changed.
    public struct Use: Sendable, Equatable {
        /// The declaration, as a caller writes it.
        public var name: String
        /// What its doc says about the type, or `nil` when it says nothing.
        public var answer: Answer?
    }

    /// Why the change was made, or `nil` when neither the story nor a commit says.
    public var changed: Answer?
    /// Which side of the reach relies on the other: the reached type's id, or the changed type's when the
    /// changed type is the one that now relies on the reached one.
    public var user: String
    /// Why it relies on the other, one per declaration of it that does, the ones named by the reach first.
    public var uses: [Use]

    /// Makes an answer of a paragraph run, its first two sentences leading.
    ///
    /// - Parameters:
    ///   - paragraphs: What was written, in order.
    ///   - source: Where it was written.
    /// - Returns: The answer, or `nil` when nothing was written.
    static func answer(_ paragraphs: [String], from source: String) -> Answer? {
        guard let first = paragraphs.first(where: { !$0.isBlank }) else { return nil }
        let (lead, rest) = Sentences.split(first, after: 2)
        let after = paragraphs.drop { $0 != first }.dropFirst().filter { !$0.isBlank }
        return Answer(lead: lead, source: source, more: (rest.isEmpty ? [] : [rest]) + after)
    }
}

extension Atlas {
    /// Answers why a change reaches a type.
    ///
    /// - Parameters:
    ///   - reason: One way the change reaches the type, from ``changeReasons(of:in:)``.
    ///   - id: The reached type's id.
    ///   - diff: The change.
    ///   - story: The branch's story, or `nil` when it has none.
    ///   - coverage: What the story's links resolve to, or `nil` without a story.
    ///   - commits: The commits behind each change, or `nil` when git could not say.
    /// - Returns: Why it changed, from the story's note on the member, else on the type or a type it is
    ///   nested in, else the theme that explains it, else the commit that made it; and why the type relies
    ///   on it, from each relying declaration's doc.
    public func why(_ reason: ChangeReason, reaching id: String, in diff: InterfaceDiff, story: ChangeStory?,
                    coverage: StoryCoverage?, commits: ChangeCommits?) -> ReachWhy {
        let changedName = byID[reason.changed].map(label) ?? reason.changed
        var declaration: InterfaceDiff.DeclarationChange?
        var user = id
        var used = reason.changed
        switch reason.kind {
        case .member(let member), .declaration(let member):
            declaration = member
        case .dependency(let edge):
            // The changed type may be the one that now relies on the reached type.
            if edge.from == reason.changed { (user, used) = (reason.changed, id) }
        }

        func note(_ place: StoryCoverage.NotePlace?, _ source: String) -> ReachWhy.Answer? {
            guard let place, let story, story.themes.indices.contains(place.theme),
                  story.themes[place.theme].notes.indices.contains(place.note) else { return nil }
            return ReachWhy.answer(story.themes[place.theme].notes[place.note].paragraphs, from: source)
        }
        var changed: ReachWhy.Answer?
        if let coverage {
            if case .member(let member) = reason.kind {
                changed = note(coverage.memberNotes[StoryCoverage.MemberLink(node: reason.changed, name: member.name)]?.first,
                               "the note on \(changedName)/\(member.name)")
            }
            // A note on a type it is nested in speaks for a nested type too.
            var node = reason.changed
            while changed == nil {
                changed = note(coverage.typeNotes[node]?.first, "the note on \(byID[node].map(label) ?? node)")
                guard let dot = node.lastIndex(of: ".") else { break }
                node = String(node[..<dot])
            }
            if changed == nil, let story, let theme = coverage.themes(explaining: reason.changed).first {
                changed = ReachWhy.answer(story.themes[theme].paragraphs, from: "the theme \(story.themes[theme].title)")
            }
        }
        if changed == nil, let commits {
            let made = declaration.map(commits.commits(for:)) ?? diff.change(ofNode: reason.changed).map(commits.commits(for:)) ?? []
            if let commit = made.last {
                changed = ReachWhy.answer([commit.subject + "."] + (commit.body.isEmpty ? [] : commit.body.components(separatedBy: "\n\n")),
                                          from: "commit \(commit.shortHash)")
            }
        }

        // The declarations the reach names first, then any other that relies on it.
        let named = reason.via.map { String($0.split(separator: ".").last ?? Substring($0)) }
        let reasons = reasons(from: user, to: used)
        func base(_ name: String) -> String { String(name.prefix { $0 != "(" }) }
        let ordered = reasons.filter { named.contains(base($0.name)) } + reasons.filter { !named.contains(base($0.name)) }
        let uses = ordered.map { reason -> ReachWhy.Use in
            if let entry = reason.entries.first(where: { $0.text != nil }), let text = entry.text {
                let part = switch entry.role {
                case .parameter: "parameter \(entry.parameter ?? "")"
                case .returns: "return"
                default: "throws"
                }
                return ReachWhy.Use(name: reason.name, answer: ReachWhy.answer([text], from: "\(reason.name)'s \(part)"))
            }
            if let summary = reason.summary {
                return ReachWhy.Use(name: reason.name, answer: ReachWhy.answer([summary], from: "\(reason.name)'s doc"))
            }
            if let forward = reason.forwarded.first {
                return ReachWhy.Use(name: reason.name, answer: ReachWhy.answer([forward.summary], from: "\(forward.name)'s doc"))
            }
            return ReachWhy.Use(name: reason.name, answer: nil)
        }
        return ReachWhy(changed: changed, user: user, uses: uses)
    }
}

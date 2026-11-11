import LucidRead
import Foundation

/// The story of a change in its author's words: a headline, a summary, and themes, each explaining one
/// part of the change in prose that links the types and members it is about, so the prose can be set
/// beside exactly those changes.
///
/// A branch's story lives in its repository at `.gloss/changes/<branch>.md`, committed with the branch,
/// so it travels to review and stays behind as the record of why the change was made:
///
/// ```markdown
/// ---
/// pr: 42
/// ---
/// # Say why each change was made
///
/// Reviewers read the authors' reasons beside each change, rather than guessing them from code.
///
/// ## Read the why from commits
///
/// ``ChangeCommits`` matches each change to the commits that wrote its lines, and
/// ``InterfaceDiff/DeclarationChange`` now knows where each declaration is.
/// ```
///
/// The `#` line is the headline, the paragraphs before the first `##` the summary, and each `##` a theme.
/// A theme's links are written as DocC links, between double backticks, with `/` between a type and
/// its member; ``StoryCoverage`` resolves them to the changes they explain.
public struct ChangeStory: Sendable, Equatable {
    /// One part of the change: what it is called, what it says, and what it links.
    public struct Theme: Sendable, Equatable {
        /// The theme's title, its `##` line.
        public var title: String
        /// The theme's paragraphs, each joined onto one line.
        public var paragraphs: [String]
        /// The theme's links, as written between double backticks, in order and each once: its prose's,
        /// then each note's own and its prose's.
        public var links: [String]
        /// The theme's notes, each the change told from one type's or member's side.
        public var notes: [Note] = []
    }

    /// One type's or member's side of a theme: a `###` heading that is one link, and the paragraphs under
    /// it, shown on that type's page beside the theme, so a reader zoomed in on the type reads the change
    /// from where it stands.
    public struct Note: Sendable, Equatable {
        /// The link the heading is, as written between double backticks.
        public var link: String
        /// The note's paragraphs, each joined onto one line.
        public var paragraphs: [String]
    }

    /// The headline, the `#` line, or `nil` when there is none.
    public var headline: String?
    /// The paragraphs before the first theme.
    public var summary: [String] = []
    /// The themes, in order.
    public var themes: [Theme] = []
    /// The pull request the change is reviewed in, from the front matter's `pr:` line, once there is one.
    public var pullRequest: Int?

    /// Where a branch's story is, relative to the repository's top.
    ///
    /// - Parameter branch: The branch, slashes and all, as in `feature/story`.
    /// - Returns: `.gloss/changes/` and the branch, with `.md`.
    public static func path(forBranch branch: String) -> String {
        ".gloss/changes/" + branch + ".md"
    }

    /// Reads a story.
    ///
    /// - Parameter text: The story's Markdown.
    /// - Returns: The story; one with nothing recognized has no headline and no themes.
    public static func parse(_ text: String) -> ChangeStory {
        var story = ChangeStory()
        var lines = text.components(separatedBy: .newlines)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[lines.startIndex + 1..<end] {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == "pr" { story.pullRequest = Int(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }
            }
            lines = lines[(end + 1)...]
        }
        var paragraph: [String] = []
        var inFence = false
        func endParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            paragraph = []
            guard !text.isEmpty else { return }
            guard let theme = story.themes.indices.last else { return story.summary.append(text) }
            if let note = story.themes[theme].notes.indices.last { story.themes[theme].notes[note].paragraphs.append(text) }
            else { story.themes[theme].paragraphs.append(text) }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Fenced code is an example, not prose, and its spans are not links.
            if trimmed.hasPrefix("```") {
                endParagraph()
                inFence.toggle()
                continue
            }
            if inFence { continue }
            // A `###` heading that is one link opens a note, in the theme above it; any other is prose.
            if trimmed.hasPrefix("### "), !story.themes.isEmpty,
               case let heading = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces),
               heading.hasPrefix("``"), heading.hasSuffix("``"), let link = links(in: heading).first, links(in: heading).count == 1 {
                endParagraph()
                story.themes[story.themes.count - 1].notes.append(Note(link: link, paragraphs: []))
            } else if trimmed.hasPrefix("## ") {
                endParagraph()
                story.themes.append(Theme(title: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), paragraphs: [], links: []))
            } else if trimmed.hasPrefix("# "), story.headline == nil, story.themes.isEmpty {
                endParagraph()
                story.headline = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.isEmpty {
                endParagraph()
            } else if trimmed.hasPrefix("### ") {
                // A heading that is not one link stands as a paragraph of its own, without its marker.
                endParagraph()
                paragraph.append(String(trimmed.dropFirst(4)))
                endParagraph()
            } else {
                paragraph.append(trimmed)
            }
        }
        endParagraph()
        for index in story.themes.indices {
            var seen: Set<String> = []
            let theme = story.themes[index]
            story.themes[index].links = (theme.paragraphs.flatMap(links(in:)) + theme.notes.flatMap { [$0.link] + $0.paragraphs.flatMap(links(in:)) })
                .filter { seen.insert($0).inserted }
        }
        return story
    }

    /// The double-backticked spans in some prose.
    ///
    /// - Parameter text: The prose.
    /// - Returns: Each span's text, in order.
    static func links(in text: String) -> [String] {
        var links: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "``") {
            guard let close = rest[open.upperBound...].range(of: "``") else { break }
            let link = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if !link.isEmpty { links.append(link) }
            rest = rest[close.upperBound...]
        }
        return links
    }

    /// A first draft of a branch's story, to edit rather than write from nothing: a headline and summary
    /// to fill in, then one theme per commit, its subject as the title, its body as the prose, and links to
    /// the types it changed; then one theme per module for what no commit made, which is everything when
    /// there are no commits. Every change gets a note to fill in under the first theme that names its type:
    /// a type's own change, once even when it moved modules, and each member's, file scope's by name.
    ///
    /// - Parameters:
    ///   - diff: How the branch differs from its base.
    ///   - commits: The commits behind each change, or `nil` when git could not say.
    /// - Returns: The draft's Markdown.
    public static func draft(for diff: InterfaceDiff, commits: ChangeCommits?) -> String {
        // A type is linked by its bare name, which covers it in every module, so a type that moved is one
        // link; file scope has no name, so it is linked by the declarations in it that changed.
        func links(_ ids: [String]) -> [String] {
            var seen: Set<String> = []
            return ids.flatMap { id -> [String] in
                guard let change = diff.change(ofNode: id), change.node.name.isEmpty else {
                    return ["``" + (id.split(separator: "/", maxSplits: 1).last.map(String.init) ?? id).replacingOccurrences(of: ".", with: "/") + "``"]
                }
                return change.declarations.filter { $0.change != .implementation }.map { "``" + $0.name + "``" }
            }.filter { seen.insert($0).inserted }
        }
        func sentence(_ ids: [String]) -> String {
            ids.isEmpty ? "" : "Changes " + links(ids).joined(separator: ", ") + "."
        }
        // Each change gets a note to give its reason, the type's own and each member's, under the first
        // theme that names the type.
        let owing = Dictionary(grouping: StoryCoverage.membersOwingNotes(diff), by: \.node)
        let typesOwing = Set(StoryCoverage.typesOwingNotes(diff))
        var noted: Set<String> = []
        func notes(_ ids: [String]) -> String {
            let stubs = ids.flatMap { id -> [(link: String, prompt: String)] in
                // The type's path after its module, empty for file scope, which has no name of its own.
                let path = (id.firstIndex(of: "/").map { String(id[id.index(after: $0)...]) } ?? id).replacingOccurrences(of: ".", with: "/")
                guard !path.isEmpty else {
                    // A note on a file-scope declaration is file scope's own too, so each one changed gets one.
                    return (diff.change(ofNode: id)?.declarations ?? []).map { ("``" + $0.name + "``", "Why it changed, in a sentence or two.") }
                }
                let own = typesOwing.contains(id) ? [("``" + path + "``", "Why the type itself changed, in a sentence or two.")] : []
                return own + (owing[id] ?? []).map { ("``" + path + "/" + $0.name + "``", "Why it changed, in a sentence or two.") }
            }
            return stubs.filter { noted.insert($0.link).inserted }.map { "\n### " + $0.link + "\n\n" + $0.prompt + "\n" }.joined()
        }
        var text = "# What this change does, in a line\n\nWhy it was made, and what a reviewer should look at first.\n"
        // Every change needs a reason, a body's included, so every type that differs is drafted.
        let changed = diff.nodes
        var named: Set<String> = []
        if let commits, !commits.commits.isEmpty {
            for commit in commits.commits {
                let ids = changed.filter { commits.commits(for: $0).contains(commit) }.map(\.node.id)
                guard !ids.isEmpty else { continue }
                named.formUnion(ids)
                text += "\n## \(commit.subject)\n\n"
                if !commit.body.isEmpty { text += commit.body.components(separatedBy: "\n\n").first.map { $0.replacingOccurrences(of: "\n", with: " ") + "\n\n" } ?? "" }
                text += sentence(ids) + "\n" + notes(ids)
            }
        }
        // What no commit in the range made, such as edits not committed yet or a move git follows back
        // to the lines' first commits, gets a theme per module.
        let rest = changed.filter { !named.contains($0.node.id) }
        var seen: Set<String> = []
        for module in rest.map(\.node.module) where seen.insert(module).inserted {
            let ids = rest.filter { $0.node.module == module }.map(\.node.id)
            let from = Set(rest.filter { $0.node.module == module }.compactMap { $0.movedFrom?.module }).sorted()
            let prose = from.isEmpty ? "What changed here, and why." : "What moved here from \(from.joined(separator: " and ")), and why."
            text += "\n## \(module)\n\n\(prose)\n\n" + sentence(ids) + "\n" + notes(ids)
        }
        return text
    }
}

/// What a story says about a diff: which changes each theme explains, which changes no theme does, and
/// which links name nothing, so a review can see the story covers the change.
///
/// A link names a type when its path, with `/` between names, is a type's name in the head or the base,
/// and a member when the rest is one of the type's members as a caller writes it, with its argument
/// labels; a member neither side declares names nothing. A bare name names the type of that name in every
/// module, and a module first narrows it to that module's type; a type the diff sees as moved is
/// explained by a link to either module. A link with no type in front names a declaration at file scope,
/// such as a free function, and stands for its module's file scope, which has no name of its own. A theme
/// explains the types it links and their nested types, and the members it links. Every type whose
/// interface changed, new, gone, moved, or changed, needs a theme and a note of its own, or one on a type
/// it is nested in; a type changed only inside its bodies needs no theme. Every change also needs a reason
/// of its own, a note that sits beside it: each declaration that differs, a member's in a note that links
/// it and a type's own, gone, moved, or declared differently, in a note that links the type; a new type's
/// reason is its theme and its members' notes.
public struct StoryCoverage: Sendable, Equatable {
    /// For each theme, in order, the ids of the changed types it explains, in the order it links them.
    public var types: [[String]]
    /// For each theme, the changed declarations it links by name, as their type's id and their name.
    public var members: [[MemberLink]]
    /// The ids of the types whose interface changed and that no theme explains, in the diff's order.
    public var unexplained: [String]
    /// The links that name no type in the head or the base, by theme title.
    public var deadLinks: [(theme: String, link: String)]
    /// The ids of the types whose own change, gone, moved, or declared differently, has no note of its
    /// own, in the diff's order.
    public var withoutNotes: [String]
    /// The members whose change has no note of its own: every declaration that differs from the base, in
    /// a type that is not gone; in the diff's order.
    public var membersWithoutNotes: [MemberLink]
    /// Where each type's notes are, by its id, as the theme and the note within it.
    public var typeNotes: [String: [NotePlace]]
    /// Where each member's notes are, by its link.
    public var memberNotes: [MemberLink: [NotePlace]]

    /// Where a note is in the story: its theme's index and its own within the theme.
    public struct NotePlace: Sendable, Equatable, Hashable {
        /// The theme's index.
        public var theme: Int
        /// The note's index in the theme.
        public var note: Int
    }

    /// A link to a member: its type's id and its name as a caller writes it.
    public struct MemberLink: Sendable, Equatable, Hashable {
        /// The id of the member's type.
        public var node: String
        /// The member's name as a caller writes it.
        public var name: String

        /// Names a member.
        ///
        /// - Parameters:
        ///   - node: The id of the member's type.
        ///   - name: The member's name as a caller writes it.
        public init(node: String, name: String) {
            self.node = node
            self.name = name
        }
    }

    /// Resolves a story's links against both sides of a diff.
    ///
    /// - Parameters:
    ///   - story: The story.
    ///   - diff: How the head differs from the base.
    ///   - head: The interface now.
    ///   - base: The interface the diff compares with.
    public init(story: ChangeStory, diff: InterfaceDiff, head: Interface, base: Interface) {
        var byName: [String: [String]] = [:]
        var modules: Set<String> = []
        for node in head.graph.nodes + base.graph.nodes {
            modules.insert(node.module)
            if !(byName[node.name]?.contains(node.id) ?? false) { byName[node.name, default: []].append(node.id) }
        }
        // The declarations at file scope, by name as a caller writes it, to the file scope of each module
        // that declares one.
        var fileScope: [String: [String]] = [:]
        for contract in head.contracts + base.contracts where !contract.opensScope && contract.container.isEmpty {
            let id = Graph.id(contract.module, "")
            if !(fileScope[contract.callName]?.contains(id) ?? false) { fileScope[contract.callName, default: []].append(id) }
        }
        // Each type's members by the name a caller writes, in the head or the base, so a link names only a
        // member that one of them declares; a case with values or a synthesized member is named bare too.
        var declared: [String: Set<String>] = [:]
        for contract in head.contracts + base.contracts where !contract.opensScope {
            declared[Graph.id(contract.module, Graph.key(of: contract)), default: []].insert(contract.callName)
        }
        func declares(_ id: String, _ member: String) -> Bool {
            let bare = String(member.prefix { $0 != "(" })
            return declared[id].map { $0.contains(member) || $0.contains(bare) } ?? false
                || Declaration.knownRequirements.contains(member) || Declaration.knownRequirements.contains(bare)
        }
        let changed = Set(diff.nodes.map(\.node.id))
        // A moved type's id in the base stands for its move, so a link that names the module it left
        // explains it too.
        let movedTo = Dictionary(diff.nodes.compactMap { change in change.movedFrom.map { ($0.id, change.node.id) } },
                                 uniquingKeysWith: { first, _ in first })
        func following(_ ids: [String]) -> [String] {
            var seen: Set<String> = []
            return ids.map { movedTo[$0] ?? $0 }.filter { seen.insert($0).inserted }
        }
        // A link names the longest leading run of names that is a type, in every module or in the one it
        // starts with, and what follows is one of its members; a lone name that is no type may be a
        // declaration at file scope.
        func resolve(_ link: String) -> (ids: [String], member: String?, atFileScope: Bool)? {
            var parts = link.split(separator: "/").map { SymbolIndex.dropDisambiguation(String($0)) }
            var module: String?
            if parts.count > 1, modules.contains(parts[0]) { module = parts.removeFirst() }
            func ids(_ name: String, in table: [String: [String]]) -> [String] {
                (table[name] ?? []).filter { id in module.map { id.hasPrefix($0 + "/") } ?? true }
            }
            guard !parts.isEmpty else { return nil }
            if let length = (1...parts.count).reversed().first(where: { !ids(parts.prefix($0).joined(separator: "."), in: byName).isEmpty }) {
                let types = ids(parts.prefix(length).joined(separator: "."), in: byName)
                guard length < parts.count else { return (types, nil, false) }
                // A member names nothing unless the type declares it, so a mistyped note is caught, not shown nowhere.
                let member = parts[length...].joined(separator: "/")
                let declaring = types.filter { declares($0, member) }
                return declaring.isEmpty ? nil : (declaring, member, false)
            }
            let scopes = parts.count == 1 ? ids(parts[0], in: fileScope) : []
            return scopes.isEmpty ? nil : (scopes, parts[0], true)
        }
        var types: [[String]] = []
        var members: [[MemberLink]] = []
        var dead: [(theme: String, link: String)] = []
        var linked: Set<String> = []
        var typeNotes: [String: [NotePlace]] = [:]
        var memberNotes: [MemberLink: [NotePlace]] = [:]
        for (themeIndex, theme) in story.themes.enumerated() {
            var themeTypes: [String] = []
            var themeMembers: [MemberLink] = []
            for link in theme.links {
                guard let (ids, member, _) = resolve(link) else {
                    dead.append((theme.title, link))
                    continue
                }
                for id in following(ids) {
                    linked.insert(id)
                    let explained = changed.filter { $0 == id || $0.hasPrefix(id + ".") }
                    for each in [id] + explained.sorted() where changed.contains(each) && !themeTypes.contains(each) { themeTypes.append(each) }
                    if let member { themeMembers.append(MemberLink(node: id, name: member)) }
                }
            }
            for (noteIndex, note) in theme.notes.enumerated() {
                guard let (ids, member, atFileScope) = resolve(note.link) else { continue }
                let place = NotePlace(theme: themeIndex, note: noteIndex)
                for id in following(ids) {
                    if let member { memberNotes[MemberLink(node: id, name: member), default: []].append(place) }
                    // File scope has no name to head a note with, so a note on one of its declarations is its own too.
                    if member == nil || atFileScope { typeNotes[id, default: []].append(place) }
                }
            }
            types.append(themeTypes)
            members.append(themeMembers)
        }
        self.types = types
        self.members = members
        self.typeNotes = typeNotes
        self.memberNotes = memberNotes
        deadLinks = dead
        // Whether a changed type or a type it is nested in is in a set of ids.
        func coveredBy(_ ids: Set<String>, _ change: InterfaceDiff.NodeChange) -> Bool {
            var name = change.node.name
            while true {
                if ids.contains(Graph.id(change.node.module, name)) { return true }
                guard let dot = name.lastIndex(of: ".") else { return false }
                name = String(name[..<dot])
            }
        }
        let interface = diff.nodes.filter { $0.change != .implementation }
        unexplained = interface.filter { !coveredBy(linked, $0) }.map(\.node.id)
        withoutNotes = Self.typesOwingNotes(diff).filter { typeNotes[$0] == nil }
        membersWithoutNotes = Self.membersOwingNotes(diff).filter { memberNotes[$0] == nil }
    }

    /// The declarations that open a type, whose change is the type's own rather than a member's.
    static let typeKeywords: Set<String> = ["struct", "class", "enum", "protocol", "actor"]

    /// The types whose own change a note should tell: one that is gone or moved, or whose declaration is
    /// declared differently, changes no member row carries; a new type's reason is its theme's blurb and
    /// its members' notes.
    ///
    /// - Parameter diff: How the head differs from the base.
    /// - Returns: Their ids, in the diff's order.
    static func typesOwingNotes(_ diff: InterfaceDiff) -> [String] {
        diff.nodes.filter { node in
            node.change == .moved || node.change == .removed
                || (node.change != .added && node.declarations.contains { typeKeywords.contains($0.keyword) })
        }.map(\.node.id)
    }

    /// The members whose change a note should tell: every declaration that differs from the base, new,
    /// gone, declared differently, or changed only in its body, whatever its access, in a type that is not
    /// gone; a gone type's members go with it, which its own note tells.
    ///
    /// - Parameter diff: How the head differs from the base.
    /// - Returns: Each member as a link, each once, in the diff's order.
    static func membersOwingNotes(_ diff: InterfaceDiff) -> [MemberLink] {
        var seen: Set<MemberLink> = []
        return diff.nodes.filter { $0.change != .removed }.flatMap { node in
            node.declarations.filter { !typeKeywords.contains($0.keyword) }.map { MemberLink(node: node.node.id, name: $0.name) }
        }.filter { seen.insert($0).inserted }
    }

    /// Whether the story explains every type whose interface changed, gives every change a note of its own,
    /// and every link names something.
    public var isComplete: Bool {
        unexplained.isEmpty && deadLinks.isEmpty && withoutNotes.isEmpty && membersWithoutNotes.isEmpty
    }

    /// The themes that explain a type, by index.
    ///
    /// - Parameter id: A node id.
    /// - Returns: The indexes of the themes whose links explain it, in order.
    public func themes(explaining id: String) -> [Int] {
        types.indices.filter { types[$0].contains(id) }
    }

    /// Compares two coverages, their dead links by theme and link.
    ///
    /// - Parameters:
    ///   - lhs: One coverage.
    ///   - rhs: Another.
    /// - Returns: `true` when they say the same.
    public static func == (lhs: StoryCoverage, rhs: StoryCoverage) -> Bool {
        lhs.types == rhs.types && lhs.members == rhs.members && lhs.unexplained == rhs.unexplained && lhs.withoutNotes == rhs.withoutNotes
            && lhs.membersWithoutNotes == rhs.membersWithoutNotes
            && lhs.typeNotes == rhs.typeNotes && lhs.memberNotes == rhs.memberNotes
            && lhs.deadLinks.map { [$0.theme, $0.link] } == rhs.deadLinks.map { [$0.theme, $0.link] }
    }
}

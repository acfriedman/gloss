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
        /// The theme's links, as written between double backticks, in order and each once.
        public var links: [String]
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
            if story.themes.isEmpty { story.summary.append(text) } else { story.themes[story.themes.count - 1].paragraphs.append(text) }
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
            if trimmed.hasPrefix("## ") {
                endParagraph()
                story.themes.append(Theme(title: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), paragraphs: [], links: []))
            } else if trimmed.hasPrefix("# "), story.headline == nil, story.themes.isEmpty {
                endParagraph()
                story.headline = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.isEmpty {
                endParagraph()
            } else {
                paragraph.append(trimmed)
            }
        }
        endParagraph()
        for index in story.themes.indices {
            var seen: Set<String> = []
            story.themes[index].links = story.themes[index].paragraphs.flatMap(links(in:)).filter { seen.insert($0).inserted }
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
    /// the types it changed; or, with no commits, one theme per module.
    ///
    /// - Parameters:
    ///   - diff: How the branch differs from its base.
    ///   - commits: The commits behind each change, or `nil` when git could not say.
    /// - Returns: The draft's Markdown.
    public static func draft(for diff: InterfaceDiff, commits: ChangeCommits?) -> String {
        func link(_ id: String) -> String {
            "``" + (id.split(separator: "/", maxSplits: 1).last.map(String.init) ?? id).replacingOccurrences(of: ".", with: "/") + "``"
        }
        func sentence(_ ids: [String]) -> String {
            ids.isEmpty ? "" : "Changes " + ids.map(link).joined(separator: ", ") + "."
        }
        var text = "# What this change does, in a line\n\nWhy it was made, and what a reviewer should look at first.\n"
        let changed = diff.nodes.filter { $0.change != .implementation }
        if let commits, !commits.commits.isEmpty {
            for commit in commits.commits {
                let ids = changed.filter { commits.commits(for: $0).contains(commit) }.map(\.node.id)
                guard !ids.isEmpty else { continue }
                text += "\n## \(commit.subject)\n\n"
                if !commit.body.isEmpty { text += commit.body.components(separatedBy: "\n\n").first.map { $0.replacingOccurrences(of: "\n", with: " ") + "\n\n" } ?? "" }
                text += sentence(ids) + "\n"
            }
        }
        if !text.contains("\n## ") {
            var seen: Set<String> = []
            for module in changed.map(\.node.module) where seen.insert(module).inserted {
                text += "\n## \(module)\n\nWhat changed here, and why.\n\n" + sentence(changed.filter { $0.node.module == module }.map(\.node.id)) + "\n"
            }
        }
        return text
    }
}

/// What a story says about a diff: which changes each theme explains, which changes no theme does, and
/// which links name nothing, so a review can see the story covers the change.
///
/// A link names a type when its path, with `/` between names, is a type's name in the head or the base,
/// with or without its module first, and a member when the rest is one of the type's members as a
/// caller writes it, with its argument labels. A theme explains the types it links and their nested
/// types, and the members it links. Every type whose interface changed, new, gone, or changed, needs a
/// theme; a type changed only inside its bodies needs none.
public struct StoryCoverage: Sendable, Equatable {
    /// For each theme, in order, the ids of the changed types it explains, in the order it links them.
    public var types: [[String]]
    /// For each theme, the changed declarations it links by name, as their type's id and their name.
    public var members: [[MemberLink]]
    /// The ids of the types whose interface changed and that no theme explains, in the diff's order.
    public var unexplained: [String]
    /// The links that name no type in the head or the base, by theme title.
    public var deadLinks: [(theme: String, link: String)]

    /// A link to a member: its type's id and its name as a caller writes it.
    public struct MemberLink: Sendable, Equatable, Hashable {
        /// The id of the member's type.
        public var node: String
        /// The member's name as a caller writes it.
        public var name: String
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
        let changed = Set(diff.nodes.map(\.node.id))
        var types: [[String]] = []
        var members: [[MemberLink]] = []
        var dead: [(theme: String, link: String)] = []
        var linked: Set<String> = []
        for theme in story.themes {
            var themeTypes: [String] = []
            var themeMembers: [MemberLink] = []
            for link in theme.links {
                var parts = link.split(separator: "/").map { SymbolIndex.dropDisambiguation(String($0)) }
                if parts.count > 1, modules.contains(parts[0]) { parts.removeFirst() }
                // The longest leading run of names that is a type; what follows is one of its members.
                guard !parts.isEmpty,
                      let length = (1...parts.count).reversed().first(where: { byName[parts.prefix($0).joined(separator: ".")] != nil }),
                      let id = byName[parts.prefix(length).joined(separator: ".")]?.first else {
                    dead.append((theme.title, link))
                    continue
                }
                linked.insert(id)
                let explained = changed.filter { $0 == id || $0.hasPrefix(id + ".") }
                for each in [id] + explained.sorted() where changed.contains(each) && !themeTypes.contains(each) { themeTypes.append(each) }
                if length < parts.count { themeMembers.append(MemberLink(node: id, name: parts[length...].joined(separator: "/"))) }
            }
            types.append(themeTypes)
            members.append(themeMembers)
        }
        self.types = types
        self.members = members
        deadLinks = dead
        unexplained = diff.nodes.filter { change in
            guard change.change != .implementation else { return false }
            // A type is explained by a link to it or to a type it is nested in.
            var name = change.node.name
            while true {
                if linked.contains(Graph.id(change.node.module, name)) { return false }
                guard let dot = name.lastIndex(of: ".") else { return true }
                name = String(name[..<dot])
            }
        }.map(\.node.id)
    }

    /// Whether the story explains every type whose interface changed, and every link names something.
    public var isComplete: Bool {
        unexplained.isEmpty && deadLinks.isEmpty
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
        lhs.types == rhs.types && lhs.members == rhs.members && lhs.unexplained == rhs.unexplained
            && lhs.deadLinks.map { [$0.theme, $0.link] } == rhs.deadLinks.map { [$0.theme, $0.link] }
    }
}

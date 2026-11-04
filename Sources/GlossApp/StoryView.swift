import GlossCore
import GlossMap
import SwiftUI

/// The story of the change at the top of the changes page: its headline and summary, then each theme
/// with its prose and the changed types it explains, lighting them on the map while hovered; then what
/// the story leaves out.
struct StoryOverviewView: View {
    @Environment(Workspace.self) private var workspace
    /// The story.
    var story: ChangeStory
    /// Which changes each theme explains.
    var coverage: StoryCoverage
    /// How the interface differs from the base.
    var diff: InterfaceDiff
    /// The arranged interface the chips read their names from.
    var atlas: Atlas

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let headline = story.headline {
                    Text(headline).font(.title2.weight(.semibold))
                }
                ForEach(Array(story.summary.enumerated()), id: \.offset) { _, paragraph in
                    DocTextView(text: StoryProse.markdown(paragraph)).font(.body)
                }
                HStack(spacing: 10) {
                    if let pullRequest = story.pullRequest {
                        Text("Pull request #\(pullRequest)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Edit the Story") { workspace.writeStory() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help(workspace.storyFile?.path ?? "")
                }
            }
            ForEach(Array(story.themes.enumerated()), id: \.offset) { index, theme in
                ThemeView(title: theme.title, paragraphs: theme.paragraphs, types: coverage.types[index], diff: diff, atlas: atlas,
                          caption: theme.notes.isEmpty ? nil : "\(theme.notes.count) note\(theme.notes.count == 1 ? "" : "s"), on each type's page")
            }
            StoryGapsView(coverage: coverage, diff: diff, atlas: atlas)
        }
    }
}

/// One theme of the story, or one commit standing in for a theme: its title, its prose, and the changed
/// types it is about, which light together on the map while the pointer is on it.
struct ThemeView: View {
    @Environment(Workspace.self) private var workspace
    @State private var isHovered = false
    /// The theme's title.
    var title: String
    /// The theme's paragraphs, links between double backticks.
    var paragraphs: [String]
    /// The ids of the changed types the theme is about, in order.
    var types: [String]
    /// How the interface differs from the base, for each type's mark.
    var diff: InterfaceDiff
    /// The arranged interface the chips read their names from.
    var atlas: Atlas
    /// A caption beside the title, such as a commit's short hash, or `nil` for none.
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.tertiary)
                }
            }
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).font(.callout).foregroundStyle(.secondary)
            }
            if !types.isEmpty {
                Wrap(spacing: 6) {
                    ForEach(types, id: \.self) { id in
                        HStack(spacing: 3) {
                            ChangeBadgeView(change: diff.change(ofNode: id)?.change ?? .changed)
                            if atlas.byID[id] != nil {
                                ChipView(unit: .type(id), atlas: atlas)
                            } else {
                                Text(diff.change(ofNode: id)?.node.name ?? id)
                                    .font(.system(.callout, design: .monospaced))
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isHovered ? 0.07 : 0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Palette.accent.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            workspace.litGroup = inside ? Set(types) : []
        }
    }
}

/// What the story leaves out: the types whose interface changed that no theme links, those with no note
/// of their own, and the links that name nothing, so an author can see the story covers the change.
struct StoryGapsView: View {
    /// Which changes the story explains.
    var coverage: StoryCoverage
    /// How the interface differs from the base.
    var diff: InterfaceDiff
    /// The arranged interface the rows read their names from.
    var atlas: Atlas

    var body: some View {
        if !coverage.unexplained.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowView(text: "Not in the story · \(coverage.unexplained.count)")
                Text("These changed what they declare, and no theme links them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(coverage.unexplained, id: \.self) { id in
                    if let change = diff.change(ofNode: id) { NodeChangeView(change: change, atlas: atlas) }
                }
            }
        }
        if !coverage.withoutNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowView(text: "No note of its own · \(coverage.withoutNotes.count)")
                Text("A theme explains these, but none tells the change from their side under a ### heading that links them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Wrap(spacing: 6) {
                    ForEach(coverage.withoutNotes, id: \.self) { id in
                        if atlas.byID[id] != nil {
                            ChipView(unit: .type(id), atlas: atlas)
                        } else {
                            Text(diff.change(ofNode: id)?.node.name ?? id).font(.system(.callout, design: .monospaced)).strikethrough()
                        }
                    }
                }
            }
        }
        if !coverage.deadLinks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowView(text: "Links that name nothing · \(coverage.deadLinks.count)")
                ForEach(Array(coverage.deadLinks.enumerated()), id: \.offset) { _, dead in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(dead.link).font(.system(.callout, design: .monospaced)).foregroundStyle(Palette.danger)
                        Text("in \(dead.theme)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The top of the changes page with no story: where one would go, a button that drafts it from the
/// commits, and meanwhile the commits themselves as the outline, each with the types it changed.
struct StoryPromptView: View {
    @Environment(Workspace.self) private var workspace
    /// How the interface differs from the base.
    var diff: InterfaceDiff
    /// The arranged interface the chips read their names from.
    var atlas: Atlas

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No story yet").font(.title3.weight(.semibold))
                Text("Say why this change was made in \(workspace.storyFile.map { StoryProse.shortPath($0) } ?? "a story file"): a headline, then a theme for each part, linking the types it is about. The page then leads with it, and each type's page with its theme.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Draft the Story from the Commits") { workspace.writeStory() }
                    .disabled(workspace.storyFile == nil)
                    .help(workspace.storyFile == nil ? "There is no branch to write a story for" : "Write a first draft and open it")
            }
            if let commits = workspace.changeCommits, !commits.commits.isEmpty {
                EyebrowView(text: "Commits · \(commits.commits.count)")
                ForEach(commits.commits, id: \.hash) { commit in
                    let types = diff.nodes.filter { commits.commits(for: $0).contains(commit) }.map(\.node.id)
                    let first = commit.body.components(separatedBy: "\n\n").first?.replacingOccurrences(of: "\n", with: " ")
                    ThemeView(title: commit.subject, paragraphs: first.map { [$0] } ?? [], types: types, diff: diff, atlas: atlas,
                              caption: commit.shortHash)
                }
            }
        }
    }
}

/// Every change, module by module, then the dependencies that entered, left, or were dropped: open at
/// first without a story, and folded under one with, since the story leads.
struct EveryChangeView: View {
    /// How the interface differs from the base.
    var diff: InterfaceDiff
    /// The arranged interface the rows read names and modules from.
    var atlas: Atlas
    /// Whether the list starts open.
    var startsOpen: Bool
    @State private var isOpen: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isOpen ?? startsOpen }, set: { isOpen = $0 })) {
            VStack(alignment: .leading, spacing: 18) {
                let modules = atlas.modules + Set(diff.nodes.map(\.node.module)).subtracting(atlas.modules).sorted()
                ForEach(modules, id: \.self) { module in
                    let changes = diff.nodes.filter { $0.node.module == module }
                    if !changes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                ModuleDotView(module: module)
                                EyebrowView(text: module)
                            }
                            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                                NodeChangeView(change: change, atlas: atlas)
                            }
                        }
                    }
                }
                let added = Set(diff.nodes.filter { $0.change == .added }.map(\.node.id))
                let entering = diff.edges.filter { $0.entersInterface && !added.contains($0.from) }
                let leaving = diff.edges.filter(\.leavesInterface)
                if !entering.isEmpty || !leaving.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowView(text: "Interface dependencies of existing types")
                        ForEach(Array((entering + leaving).enumerated()), id: \.offset) { _, edge in
                            EdgeChangeView(edge: edge, atlas: atlas)
                        }
                    }
                }
                // A dependency that lived only in bodies leaves the interface as it was, so it is listed on
                // its own: between types still there, since a gone type's dependencies go with it.
                let dropped = diff.edges.filter { $0.change == .removed && $0.before == [.body] && atlas.byID[$0.from] != nil && atlas.byID[$0.to] != nil }
                if !dropped.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        EyebrowView(text: "Dependencies dropped from bodies")
                        ForEach(Array(dropped.enumerated()), id: \.offset) { _, edge in
                            DependencyChangeView(edge: edge, atlas: atlas)
                        }
                    }
                }
            }
            .padding(.top, 10)
            // A disclosure group centers content narrower than itself, so the rows are pinned to its leading edge.
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            EyebrowView(text: "Every change · \(diff.nodes.count) type\(diff.nodes.count == 1 ? "" : "s")")
        }
    }
}

/// The story on one type's page: each theme that explains it, its title over its prose, and the note
/// that tells the theme from the type's own side, or from the side of a type it is nested in.
struct StoryThemesView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the type.
    var id: String

    /// The notes on the type, or failing those on the nearest type it is nested in, within one theme.
    ///
    /// - Parameters:
    ///   - theme: The theme's index.
    ///   - coverage: Where the story's notes are.
    /// - Returns: The notes' places, in the story's order.
    private func notes(in theme: Int, coverage: StoryCoverage) -> [StoryCoverage.NotePlace] {
        var outer = id
        while true {
            if let places = coverage.typeNotes[outer], !places.isEmpty { return places.filter { $0.theme == theme } }
            guard let dot = outer.lastIndex(of: ".") else { return [] }
            outer = String(outer[..<dot])
        }
    }

    var body: some View {
        if let story = workspace.story, let coverage = workspace.storyCoverage {
            let themes = coverage.themes(explaining: id)
            if !themes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowView(text: "From the story")
                    ForEach(themes, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(story.themes[index].title).font(.headline)
                            ForEach(Array(story.themes[index].paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            // The change told from this type's side, beside the theme it belongs to.
                            ForEach(notes(in: index, coverage: coverage), id: \.self) { place in
                                StoryNoteView(note: story.themes[place.theme].notes[place.note])
                                    .padding(.top, 6)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft.opacity(0.6)))
                    }
                }
            }
        }
    }
}

/// How a story's prose is drawn.
enum StoryProse {
    /// A paragraph as inline Markdown, its double-backticked links as code spans.
    ///
    /// - Parameter paragraph: A paragraph as the story writes it.
    /// - Returns: The Markdown to draw.
    static func markdown(_ paragraph: String) -> String {
        paragraph.replacingOccurrences(of: "``", with: "`")
    }

    /// A story file's path from the repository's top, for prose that names it.
    ///
    /// - Parameter file: The story file.
    /// - Returns: The path from `.gloss` on.
    static func shortPath(_ file: URL) -> String {
        file.path.range(of: "/.gloss/").map { String(file.path[file.path.index(after: $0.lowerBound)...]) } ?? file.lastPathComponent
    }
}

/// One note of the story: the change told from one type's or member's side, set off from the theme
/// around it by a bar in the accent color.
struct StoryNoteView: View {
    /// The note.
    var note: ChangeStory.Note

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.link).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(Palette.accent)
                ForEach(Array(note.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).font(.callout)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The story's notes on one member, under its row on its type's page.
struct MemberNotesView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the member's type.
    var node: String
    /// The member's name as a caller writes it.
    var name: String

    var body: some View {
        if let story = workspace.story,
           let places = workspace.storyCoverage?.memberNotes[StoryCoverage.MemberLink(node: node, name: name)], !places.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(places, id: \.self) { place in StoryNoteView(note: story.themes[place.theme].notes[place.note]) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft.opacity(0.6)))
        }
    }
}

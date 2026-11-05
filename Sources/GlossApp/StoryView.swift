import GlossRead
import GlossModel
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
                    Text(headline).textStyle(.title2, weight: .semibold)
                }
                ForEach(Array(story.summary.enumerated()), id: \.offset) { _, paragraph in
                    DocTextView(text: StoryProse.markdown(paragraph)).textStyle(.body)
                }
                HStack(spacing: 10) {
                    if let pullRequest = story.pullRequest {
                        Text("Pull request #\(pullRequest)").textStyle(.caption).foregroundStyle(.secondary)
                    }
                    Button("Edit the Story") { workspace.writeStory() }
                        .buttonStyle(.link)
                        .textStyle(.caption)
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
                Text(title).textStyle(.headline)
                if let caption {
                    Text(caption).textStyle(.caption).foregroundStyle(.tertiary)
                }
            }
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).textStyle(.callout).foregroundStyle(.secondary)
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
                                    .textStyle(.callout, design: .monospaced)
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
                    .textStyle(.callout)
                    .foregroundStyle(.secondary)
                ForEach(coverage.unexplained, id: \.self) { id in
                    if let change = diff.change(ofNode: id) { NodeChangeView(change: change, atlas: atlas) }
                }
            }
        }
        if !coverage.withoutNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowView(text: "No note of its own · \(coverage.withoutNotes.count)")
                Text("Each is gone, moved, or declared differently; a ### heading that links it puts the reason beside it.")
                    .textStyle(.callout)
                    .foregroundStyle(.secondary)
                Wrap(spacing: 6) {
                    ForEach(coverage.withoutNotes, id: \.self) { id in
                        if atlas.byID[id] != nil {
                            ChipView(unit: .type(id), atlas: atlas)
                        } else {
                            Text(diff.change(ofNode: id)?.node.name ?? id).textStyle(.callout, design: .monospaced).strikethrough()
                        }
                    }
                }
            }
        }
        if !coverage.membersWithoutNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowView(text: "Members without a note · \(coverage.membersWithoutNotes.count)")
                Text("Every change needs a reason; a ### heading that links each one puts it under its row.")
                    .textStyle(.callout)
                    .foregroundStyle(.secondary)
                Wrap(spacing: 6) {
                    ForEach(coverage.membersWithoutNotes, id: \.self) { member in
                        Text(atlas.byID[member.node].map { "\(atlas.label($0)).\(member.name)" } ?? member.name)
                            .textStyle(.callout, design: .monospaced)
                    }
                }
            }
        }
        if !coverage.deadLinks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                EyebrowView(text: "Links that name nothing · \(coverage.deadLinks.count)")
                ForEach(Array(coverage.deadLinks.enumerated()), id: \.offset) { _, dead in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(dead.link).textStyle(.callout, design: .monospaced).foregroundStyle(Palette.danger)
                        Text("in \(dead.theme)").textStyle(.caption).foregroundStyle(.secondary)
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
                Text("No story yet").textStyle(.title3, weight: .semibold)
                Text("Say why this change was made in \(workspace.storyFile.map { StoryProse.shortPath($0) } ?? "a story file"): a headline, then a theme for each part, linking the types it is about. The page then leads with it, and each type's page with its theme.")
                    .textStyle(.callout)
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

/// The story on one type's page: a short blurb, each theme that explains it, its title over its prose.
/// The reasons for each change sit beside the change itself, not here.
struct StoryThemesView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the type.
    var id: String

    var body: some View {
        if let story = workspace.story, let coverage = workspace.storyCoverage {
            let themes = coverage.themes(explaining: id)
            if !themes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowView(text: "From the story")
                    ForEach(themes, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(story.themes[index].title).textStyle(.headline)
                            ForEach(Array(story.themes[index].paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).textStyle(.callout)
                                    .foregroundStyle(.secondary)
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
    /// `false` under a member's own row, which names the member already.
    var showsLink = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                if showsLink {
                    Text(note.link).textStyle(.caption, design: .monospaced, weight: .semibold).foregroundStyle(Palette.accent)
                }
                ForEach(Array(note.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).textStyle(.callout)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The story's notes on a type's own change, beside its declaration on its page: why it is new, gone,
/// moved, or declared differently.
struct TypeNotesView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the type.
    var node: String

    var body: some View {
        if let story = workspace.story, let places = workspace.storyCoverage?.typeNotes[node], !places.isEmpty {
            NotesBoxView(story: story, places: places).padding(.bottom, 10)
        }
    }
}

/// A reason for a change set as the story's notes are, an accent bar beside it in the quiet box, so a
/// reason reads the same wherever it shows: under a member's row, or under a reach.
struct StoryReasonView: View {
    /// The reason, as the story or a commit writes it, its links as code.
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1).fill(Palette.accent).frame(width: 2)
            DocTextView(text: StoryProse.markdown(text), codeColor: Palette.accent).textStyle(.callout)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft.opacity(0.6)))
    }
}

/// Notes in the quiet box that sets a reason beside the change it belongs to, each without its link,
/// which the row above names already.
struct NotesBoxView: View {
    /// The story the notes are in.
    var story: ChangeStory
    /// Where the notes are.
    var places: [StoryCoverage.NotePlace]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(places, id: \.self) { place in StoryNoteView(note: story.themes[place.theme].notes[place.note], showsLink: false) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft.opacity(0.6)))
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
            NotesBoxView(story: story, places: places)
        }
    }
}

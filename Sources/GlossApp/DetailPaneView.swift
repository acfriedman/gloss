import GlossRead
import GlossLint
import GlossModel
import GlossMap
import SwiftUI

/// The middle pane: the text of whatever is selected, from the overview down to one type's members.
///
/// A preview is laid over the selection rather than replacing it, so when the preview ends the
/// selection is back where the reader left it: scrolled to the same place, members still open. In a
/// focus, a pinned type's tie to the focused type takes the selection's place until it is closed.
struct DetailPaneView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ZStack(alignment: .top) {
            if let inspected = workspace.inspected {
                VStack(spacing: 0) {
                    InspectionBarView(inspected: inspected)
                    Divider()
                    let why = workspace.inspectedTrails
                    DetailPageView(target: .type(inspected), trails: why.trails, more: why.more)
                }
                .id("inspected " + inspected)
            } else {
                VStack(spacing: 0) {
                    if workspace.scopeID == Workspace.changes, workspace.diff != nil, case .type(let id) = workspace.selection {
                        ChangePageBarView(id: id)
                        Divider()
                    }
                    DetailPageView(target: workspace.selection, changes: workspace.changesOnly(for: workspace.selection))
                }
                .id(workspace.selection)
            }
            if let preview = workspace.preview {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                        Text("Previewing. Click it to keep it here.")
                        Spacer()
                        Button("Keep") { workspace.keep(preview) }
                            .controlSize(.small)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(.bar)
                    Divider()
                    let why = workspace.previewTrails
                    DetailPageView(target: preview, trails: why.trails, more: why.more, changes: workspace.changesOnly(for: preview))
                }
                .id(preview)
            }
        }
        .onHover { workspace.detailsHovered($0) }
    }
}

/// The bar over a pinned type's tie to the focused type, naming both and closing back to the focused
/// type's page from its button or Esc.
struct InspectionBarView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the pinned type.
    var inspected: String

    var body: some View {
        let name = { (id: String?) in id.flatMap { workspace.atlas?.byID[$0] }.map { workspace.atlas?.label($0) ?? "" } ?? "" }
        let root = name(workspace.anchorID)
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            Text("How \(name(inspected)) ties to \(root)")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button { workspace.closeInspection() } label: {
                Label("Close", systemImage: "xmark")
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            .disabled(workspace.isQuickOpenShown)
            .help("Back to \(root)'s page (Esc)")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// One page of the details pane, scrolled from its top.
struct DetailPageView: View {
    @Environment(Workspace.self) private var workspace
    /// What the page shows, the selection or the preview laid over it; a type the atlas no longer holds
    /// leaves the page empty.
    var target: Workspace.Selection
    /// The trails that bring a previewed type into the focus, which turn its page into how it ties to
    /// the focused type; empty shows the type's whole page.
    var trails: [[GraphLayout.Link]] = []
    /// How many more trails the type has than are given.
    var more = 0
    /// The comparison whose changes a type's page shows instead of the whole page, as the changes level
    /// asks; `nil` shows the whole page.
    var changes: InterfaceDiff?

    var body: some View {
        ScrollView {
            // Lazy, so a type of hundreds of members and neighbors builds only the rows on screen.
            LazyVStack(alignment: .leading, spacing: 24) {
                if let atlas = workspace.atlas {
                    switch target {
                    case .overview: OverviewView(atlas: atlas)
                    case .summary: SummaryPageView(atlas: atlas)
                    case .changes: ChangesView(atlas: atlas)
                    case .modules: ModulesView(atlas: atlas)
                    case .module(let module): ModuleView(atlas: atlas, module: module)
                    case .folder(let module, let folder): FolderView(atlas: atlas, module: module, folder: folder)
                    case .type(let id):
                        if let node = atlas.byID[id] {
                            if let changes {
                                ChangePageView(atlas: atlas, node: node, diff: changes)
                            } else if trails.isEmpty {
                                TypeView(atlas: atlas, node: node)
                            } else {
                                RelationView(atlas: atlas, node: node, trails: trails, more: more, root: workspace.anchorID)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: Levels

/// The overview: each module's entry points, the types other code reaches first.
struct OverviewView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the overview reads the modules and each one's entry points from.
    var atlas: Atlas

    var body: some View {
        HeadingView(title: "Overview")
        ForEach(atlas.modules, id: \.self) { module in
            let entries = atlas.entryPoints(in: module).filter(workspace.isShown)
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ModuleDotView(module: module)
                        EyebrowView(text: module)
                    }
                    ForEach(entries, id: \.id) { node in
                        CardView(atlas: atlas, node: node)
                    }
                }
            }
        }
    }
}

/// What changed since the comparison's base, leading with why: the branch's story, its headline and
/// themes, or without one the commits, each with the types it changed; then every change.
///
/// Every change is listed module by module, each type new, gone, changed, or changed only inside, then
/// the dependencies of types already there that entered or left the interface, the changes a reviewer
/// most needs to see, and those dropped from bodies.
struct ChangesView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the rows read names and modules from.
    var atlas: Atlas

    var body: some View {
        let phrase = workspace.comparisonPhrase
        if let diff = workspace.diff {
            let count = { (change: InterfaceDiff.Change) in diff.nodes.filter { $0.change == change }.count }
            HeadingView(title: "Changes",
                        lede: diff.isEmpty ? "Nothing changed \(phrase)."
                            : "\(phrase.prefix(1).uppercased() + phrase.dropFirst()): \(count(.added)) new, \(count(.changed)) changed, "
                            + "\(count(.removed)) gone, \(count(.implementation)) changed only inside.")
            // The story leads when there is one; without, the commits stand in for its themes.
            if !diff.isEmpty {
                if let story = workspace.story, let coverage = workspace.storyCoverage {
                    StoryOverviewView(story: story, coverage: coverage, diff: diff, atlas: atlas)
                } else {
                    StoryPromptView(diff: diff, atlas: atlas)
                }
                EveryChangeView(diff: diff, atlas: atlas, startsOpen: workspace.story == nil)
            }
        } else {
            HeadingView(title: "Changes", lede: workspace.comparison == .off ? "Pick a base under Changes in the toolbar."
                        : workspace.comparisonProblem ?? "Reading what changed \(phrase)…")
        }
    }
}

/// A mark for how something differs from the base: `+`, `~`, or `−` in the change's color, and a light
/// gray `~` for a change made only inside.
struct ChangeBadgeView: View {
    /// The change the mark stands for.
    var change: InterfaceDiff.Change

    var body: some View {
        Text(Palette.glyph(of: change))
            .font(.system(.callout, design: .monospaced).weight(change == .implementation ? .regular : .heavy))
            .foregroundStyle(Palette.color(of: change))
            .frame(width: 14)
    }
}

/// One type that differs from the base: a link to it while it exists, then for a changed one each
/// declaration that changed and how.
struct NodeChangeView: View {
    /// The type's change.
    var change: InterfaceDiff.NodeChange
    /// The arranged interface the type's link reads its name from.
    var atlas: Atlas

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ChangeBadgeView(change: change.change)
                if change.change == .removed {
                    Text(change.node.name)
                        .font(.system(.callout, design: .monospaced))
                        .strikethrough()
                        .foregroundStyle(.secondary)
                } else {
                    ChipView(unit: .type(change.node.id), atlas: atlas)
                }
                if change.change == .added || change.change == .removed {
                    Text("\(change.declarations.count) declaration\(change.declarations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if change.change == .changed || change.change == .implementation {
                ForEach(Array(change.declarations.enumerated()), id: \.offset) { _, declaration in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        ChangeBadgeView(change: declaration.change)
                        Text("\(declaration.keyword) \(declaration.name)").font(.system(.callout, design: .monospaced))
                        if declaration.change == .changed || declaration.change == .implementation {
                            Text(DeclarationChangesView.what(declaration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
    }
}

/// One dependency that entered or left the interface: who depends on whom, and how before and now.
struct EdgeChangeView: View {
    /// The dependency's change.
    var edge: InterfaceDiff.EdgeChange
    /// The arranged interface the links read their names from.
    var atlas: Atlas

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ChangeBadgeView(change: edge.entersInterface ? .added : .removed)
            Wrap(spacing: 6) {
                ChipView(unit: .type(edge.from), atlas: atlas)
                Text(edge.entersInterface ? "now \(Wording.words(edge.after))" : "no longer \(Wording.words(edge.before))")
                    .font(.callout)
                ChipView(unit: .type(edge.to), atlas: atlas)
                // What it was is news only when it was something: a body use, or a role it gave up.
                if !edge.before.isEmpty, !edge.after.isEmpty {
                    Text("(was: \(Wording.words(edge.before)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A type on the overview: its kind, name, first sentence, and who uses it.
struct CardView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the card reads its type's summary, operation count, and users from.
    var atlas: Atlas
    /// The entry point the card describes, which clicking selects and hovering lights on the map.
    var node: Graph.Node

    var body: some View {
        let group = atlas.group(node.id)
        let operations = group.members.filter { Wording.isCallable($0.keyword) && Contract.rank($0.access) >= 1 && !$0.isOverride }.count
        let users = atlas.users(of: node.id)
        let summary = group.head?.summary.map(Wording.firstSentence)
        let facts = (operations > 0 ? ["\(operations) operation\(operations == 1 ? "" : "s")"] : [])
            + (users.isEmpty ? [] : ["used by " + users.map(atlas.label).joined(separator: ", ")])
        Button { workspace.select(.type(node.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Wording.kind(of: node).uppercased())
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Text(atlas.label(node)).font(.system(.body, design: .monospaced).weight(.semibold))
                if let summary { DocTextView(text: summary).foregroundStyle(.primary) }
                if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { workspace.hovered = $0 ? node.root : nil }
    }
}

/// Every module, with the modules each depends on.
struct ModulesView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the page reads each module, its summary, and the modules it depends on from.
    var atlas: Atlas

    var body: some View {
        HeadingView(eyebrow: "Modules", title: "\(atlas.modules.count) modules",
                lede: "Each module with the modules it depends on. Select one to draw its types.")
        ForEach(atlas.modules, id: \.self) { module in
            let uses = atlas.dependencies(ofModule: module).uses
            Button { workspace.select(.module(module)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(module).font(.system(.body, design: .monospaced).weight(.semibold))
                    Text(atlas.summary(of: atlas.types(in: module))).font(.caption).foregroundStyle(.secondary)
                    if !uses.isEmpty { Text("depends on " + uses.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// One module: its entry points, the modules it depends on and is used by, its folders, and its types.
struct ModuleView: View {
    /// The arranged interface the page reads the module's entry points, dependencies, and types from.
    var atlas: Atlas
    /// The name of the module the page shows.
    var module: String

    var body: some View {
        let (uses, usedBy) = atlas.dependencies(ofModule: module)
        let folders = atlas.folders(in: module)
        HeadingView(eyebrow: "Module", title: module, lede: atlas.summary(of: atlas.types(in: module)))
        ChipBlockView(title: "Entry points", units: atlas.entryPoints(in: module).map { .type($0.id) }, atlas: atlas)
        ChipBlockView(title: "Depends on", units: uses.map { .module($0) }, atlas: atlas)
        ChipBlockView(title: "Used by", units: usedBy.map { .module($0) }, atlas: atlas)
        if folders.count > 1 { ChipBlockView(title: "Folders", units: folders.map { .folder(module, $0) }, atlas: atlas) }
        ChipBlockView(title: "Types", units: atlas.types(in: module).map { .type($0.id) }, atlas: atlas)
    }
}

/// One folder drawn as its own level: what it depends on outside itself, what uses it, and its types.
struct FolderView: View {
    /// The arranged interface the page reads the folder's summary, dependencies, and types from.
    var atlas: Atlas
    /// The name of the module the folder belongs to.
    var module: String
    /// The folder's name within its module, empty for files directly in the module's directory.
    var folder: String

    var body: some View {
        let (uses, usedBy) = atlas.dependencies(ofFolder: folder, in: module)
        let members = atlas.types(inFolder: folder, of: module)
        HeadingView(eyebrow: "\(module) · folder", title: Wording.folderLabel(folder), lede: atlas.summary(of: members))
        ChipBlockView(title: "Depends on", units: uses, atlas: atlas)
        ChipBlockView(title: "Used by", units: usedBy, atlas: atlas)
        ChipBlockView(title: "Types", units: members.map { .type($0.id) }, atlas: atlas)
    }
}

// MARK: A type

/// One type: its declaration and doc, what flows into and out of it, and its members.
struct TypeView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the page reads the type's declaration, doc, neighbors, and members from.
    var atlas: Atlas
    /// The type the page shows, nested or not. For file scope or an extension of a type no scanned source
    /// declares, the page shows only its label and says which it is.
    var node: Graph.Node

    var body: some View {
        let group = atlas.group(node.id)
        let (incoming, outgoing, nested) = atlas.neighbors(of: node)
        TypeHeaderView(atlas: atlas, node: node)
        FlowView(atlas: atlas, incoming: incoming, outgoing: outgoing, nested: nested)
        WhyView(atlas: atlas, node: node, incoming: incoming, outgoing: outgoing)
        MembersView(members: group.members.filter { Contract.rank($0.access) >= workspace.minimumRank })
    }
}

/// A type previewed from the focus: its declaration and doc, then only how it ties back to the type
/// the focus grows from, each trail of drawn dependencies with what its declarations say.
struct RelationView: View {
    /// The arranged interface the page reads the type and the reasons from.
    var atlas: Atlas
    /// The previewed type.
    var node: Graph.Node
    /// The trails from ``GlossMap/Reach/trails(to:limit:)``, each read top to bottom as the map draws it.
    var trails: [[GraphLayout.Link]]
    /// How many more trails the type has than are shown.
    var more: Int
    /// The id of the type the focus grows from, which the section names.
    var root: String?

    var body: some View {
        let rootName = root.map { atlas.label(of: .type($0)) } ?? "the root"
        TypeHeaderView(atlas: atlas, node: node)
        VStack(alignment: .leading, spacing: 12) {
            EyebrowView(text: "How it ties to \(rootName)")
            ForEach(Array(trails.enumerated()), id: \.offset) { index, trail in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(trail.enumerated()), id: \.offset) { _, hop in
                        HopView(atlas: atlas, hop: hop)
                    }
                }
            }
            if more > 0 {
                Text("\(more) more way\(more == 1 ? "" : "s") back to \(rootName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A type's declaration and its doc: what it is, before what it is tied to.
struct TypeHeaderView: View {
    /// The arranged interface the header reads the type's declaration and doc from.
    var atlas: Atlas
    /// The type, nested or not. For file scope or an extension of a type no scanned source declares, the
    /// header shows only its label and says which it is.
    var node: Graph.Node

    var body: some View {
        let group = atlas.group(node.id)
        VStack(alignment: .leading, spacing: 10) {
            EyebrowView(text: "\(node.module) · \(Wording.kind(of: node))")
            if let head = group.head {
                CodeView(runs: Highlight.runs(of: head.contract))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                if let summary = head.summary { DocTextView(text: summary).font(.title3) }
                ForEach(head.notes, id: \.self) { note in NoteView(text: note) }
                FindingsView(findings: head.findings)
                SourceLinkView(file: head.file, line: head.line)
            } else {
                Text(atlas.label(node)).font(.system(.title3, design: .monospaced).weight(.semibold))
                Text(node.keyword == "extension" ? "Extends a type no scanned source declares." : "Declarations at file scope.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// What flows into and out of a type, read top to bottom: what uses it, then what it conforms to,
/// holds, takes, returns, and throws, then what it uses only inside its bodies.
struct FlowView: View {
    /// The arranged interface the chips read their names and findings from.
    var atlas: Atlas
    /// The edges from types that use this one, shown as Used by chips whose tooltips name the edge's roles.
    var incoming: [Graph.Edge]
    /// The edges to the types this one depends on, each shown under every role it has; one made only of body
    /// uses shows under Uses inside its bodies.
    var outgoing: [Graph.Edge]
    /// The types declared directly inside this one, shown as Nests chips when there are any.
    var nested: [Graph.Node]

    var body: some View {
        let roles: [(Mention.Role, String)] = [(.conformance, "Conforms to"), (.property, "Holds"), (.parameter, "Takes"),
                                               (.returns, "Returns"), (.throws, "Throws")]
        let insideOnly = outgoing.filter { $0.roles == [.body] }
        VStack(alignment: .leading, spacing: 14) {
            EyebrowView(text: "Flow")
            ChipBlockView(title: "Used by", units: incoming.map { .type($0.from) }, atlas: atlas,
                      notes: incoming.map { Wording.words($0.roles) })
            ForEach(roles, id: \.0) { role, title in
                ChipBlockView(title: title, units: outgoing.filter { $0.roles.contains(role) }.map { .type($0.to) }, atlas: atlas)
            }
            if !nested.isEmpty {
                ChipBlockView(title: "Nests", units: nested.map { .type($0.id) }, atlas: atlas)
            }
            ChipBlockView(title: "Uses inside its bodies", units: insideOnly.map { .type($0.to) }, atlas: atlas)
        }
    }
}

/// Why the type is tied to each type beside it, one row per neighbor that unfolds to what the
/// declarations the dependency runs through say about it.
struct WhyView: View {
    /// The arranged interface the rows read their reasons and names from.
    var atlas: Atlas
    /// The type the page shows.
    var node: Graph.Node
    /// The edges from types that use this one, listed first.
    var incoming: [Graph.Edge]
    /// The edges to the types this one depends on, listed after.
    var outgoing: [Graph.Edge]

    var body: some View {
        if !incoming.isEmpty || !outgoing.isEmpty {
            LazyVStack(alignment: .leading, spacing: 2) {
                EyebrowView(text: "Why · \(incoming.count + outgoing.count)")
                    .padding(.bottom, 6)
                ForEach(incoming, id: \.from) { edge in
                    WhyRowView(atlas: atlas, other: edge.from, roles: edge.roles, usesThis: true, from: edge.from, to: node.id)
                    Divider()
                }
                ForEach(outgoing, id: \.to) { edge in
                    WhyRowView(atlas: atlas, other: edge.to, roles: edge.roles, usesThis: false, from: node.id, to: edge.to)
                    Divider()
                }
            }
        }
    }
}

/// One neighbor and how it is tied to the type, unfolding to the reasons.
struct WhyRowView: View {
    /// The arranged interface the neighbor's chip reads its name from.
    var atlas: Atlas
    /// The id of the neighbor.
    var other: String
    /// How the dependent mentions the other, as the edge's roles.
    var roles: [Mention.Role]
    /// `true` when the neighbor uses the type, read as "Neighbor holds it"; `false` when the type uses
    /// the neighbor, read as "holds Neighbor".
    var usesThis: Bool
    /// The id of the dependent type.
    var from: String
    /// The id of the type it depends on.
    var to: String
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            // The reasons are read only once the row opens: a type with hundreds of neighbors would
            // otherwise read every declaration of each before showing anything.
            VStack(alignment: .leading, spacing: 12) {
                if isOpen {
                    ForEach(Array(atlas.reasons(from: from, to: to).enumerated()), id: \.offset) { _, reason in ReasonView(reason: reason) }
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
        } label: {
            HStack(spacing: 6) {
                if usesThis {
                    ChipView(unit: .type(other), atlas: atlas)
                    Text(Wording.words(roles) + " it").foregroundStyle(.secondary)
                } else {
                    Text(Wording.words(roles)).foregroundStyle(.secondary)
                    ChipView(unit: .type(other), atlas: atlas)
                }
            }
            .font(.callout)
            .padding(.vertical, 4)
        }
    }
}

/// One step of a trail: the dependency as a sentence, open on what the declarations it runs through
/// say about it, and folding away when the reader closes it.
struct HopView: View {
    /// The arranged interface the reasons and names come from.
    var atlas: Atlas
    /// The drawn dependency.
    var hop: GraphLayout.Link
    @State private var isOpen = true

    var body: some View {
        let reasons = atlas.reasons(from: hop.from, to: hop.to)
        let roles = Mention.Role.allCases.filter { role in reasons.contains { $0.roles.contains(role) } }
        DisclosureGroup(isExpanded: $isOpen) {
            // The reasons are the dependent's declarations, so its module's color marks them.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in ReasonView(reason: reason) }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(ink(hop.from).opacity(0.7)).frame(width: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 6)
        } label: {
            Text(sentence(roles: roles))
        }
    }

    /// The dependency as a sentence: each type named in code in its module's color, the verb between
    /// them quieter.
    ///
    /// - Parameter roles: How the dependent mentions the other.
    /// - Returns: `Workspace holds Atlas`, styled.
    private func sentence(roles: [Mention.Role]) -> AttributedString {
        func name(_ id: String) -> AttributedString {
            var text = AttributedString(atlas.label(of: .type(id)))
            text.font = .system(.callout, design: .monospaced).weight(.semibold)
            text.foregroundColor = ink(id)
            return text
        }
        var verb = AttributedString(" \(Wording.words(roles)) ")
        verb.font = .callout
        verb.foregroundColor = .secondary
        return name(hop.from) + verb + name(hop.to)
    }

    /// The color a type's module is drawn in on the map.
    ///
    /// - Parameter id: A node id.
    /// - Returns: The module's ink, or the secondary color for a node the atlas does not hold.
    private func ink(_ id: String) -> Color {
        guard let module = atlas.byID[id]?.module, let slot = atlas.moduleColors[module] else { return .secondary }
        return Palette.moduleInk(slot)
    }
}

/// One declaration a dependency runs through, and what its doc says: the entry for each parameter that
/// takes the type and for the return or thrown error, then the summary; or, when it says nothing, the
/// docs forwarded from what it uses.
struct ReasonView: View {
    @Environment(Workspace.self) private var workspace
    /// The declaration and the doc text that answers for the dependency.
    var reason: Reason

    var body: some View {
        let inSignature = reason.roles != [.body]
        let declaration = Text(Self.declaration(reason)).font(.system(.callout, design: .monospaced))
        let marks = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Wording.words(reason.roles))
                .font(.caption.weight(.medium))
                .foregroundStyle(inSignature ? Palette.accent : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(inSignature ? Palette.accentSoft : Palette.surface))
            Button { workspace.reveal(reason.file, line: reason.line) } label: {
                Image(systemName: "arrow.up.forward.app").font(.caption)
            }
            .buttonStyle(.link)
            .help("Open \(reason.file):\(reason.line) in Xcode")
        }
        VStack(alignment: .leading, spacing: 6) {
            // A long declaration takes the whole line and its marks go under it, rather than breaking
            // the name beside them.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    declaration.fixedSize()
                    marks
                }
                VStack(alignment: .leading, spacing: 4) {
                    declaration.fixedSize(horizontal: false, vertical: true)
                    marks
                }
            }
            // Each label sits over its text, so every line of doc starts at the same edge however long
            // the label.
            ForEach(Array(reason.entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.parameter ?? (entry.role == .returns ? "Returns" : "Throws"))
                        .font(entry.parameter == nil ? .caption.weight(.semibold) : .system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    DocTextView(text: entry.text ?? "Undocumented.", codeColor: Self.code).font(.callout)
                        .foregroundStyle(entry.text == nil ? Palette.danger : .primary)
                }
            }
            if let summary = reason.summary {
                DocTextView(text: summary, codeColor: Self.code).font(.callout)
                    .foregroundStyle(reason.entries.contains { $0.text != nil } ? .secondary : .primary)
            } else if !reason.forwarded.isEmpty {
                // Forwarded docs are the used type's words, not this declaration's, so they read quieter
                // and each names where it comes from.
                ForEach(Array(reason.forwarded.enumerated()), id: \.offset) { _, forward in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.via(forward.name))
                        DocTextView(text: forward.summary, codeColor: Self.code).font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else if reason.entries.isEmpty {
                Text("Undocumented.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// The color of code spans in the doc text, the color code gives the scanned sources' own types.
    private static let code = CodeView.color(.projectType)

    /// The label over a forwarded doc: `via`, then where the doc comes from in code.
    ///
    /// - Parameter name: A member of the used type as a caller writes it, or the type's name.
    /// - Returns: `via select(unit:)`, styled.
    private static func via(_ name: String) -> AttributedString {
        var via = AttributedString("via ")
        via.font = .caption
        via.foregroundColor = .secondary
        var source = AttributedString(name)
        source.font = .system(.caption, design: .monospaced)
        source.foregroundColor = code
        return via + source
    }

    /// The declaration as code: its keyword, its name in the color of a declared name, and a callable's
    /// argument labels quieter.
    ///
    /// - Parameter reason: The reason whose declaration to show.
    /// - Returns: `func add(_:to:)` and the like, styled.
    static func declaration(_ reason: Reason) -> AttributedString {
        var keyword = AttributedString(reason.keyword + " ")
        keyword.foregroundColor = CodeView.color(.keyword)
        keyword.inlinePresentationIntent = .stronglyEmphasized
        let open = reason.name.firstIndex(of: "(") ?? reason.name.endIndex
        var name = AttributedString(String(reason.name[..<open]))
        name.foregroundColor = CodeView.color(.declaration)
        var labels = AttributedString(String(reason.name[open...]))
        labels.foregroundColor = .secondary
        return keyword + name + labels
    }
}

/// A type's members, grouped by what a caller does with them; overrides come last, since their
/// contract is the inherited one.
struct MembersView: View {
    /// The type's members at or above the access filter, grouped by what a caller does with them.
    var members: [Atlas.Reviewed]

    var body: some View {
        let sections: [(String, [Atlas.Reviewed])] = [
            ("Operations", members.filter { Wording.isCallable($0.keyword) && !$0.isOverride }),
            ("Properties", members.filter { ["var", "let"].contains($0.keyword) && !$0.isOverride }),
            ("Cases", members.filter { $0.keyword == "case" }),
            ("Other", members.filter { !Wording.isCallable($0.keyword) && !["var", "let", "case"].contains($0.keyword) && !$0.isOverride }),
            ("Overrides", members.filter(\.isOverride))
        ]
        ForEach(sections.filter { !$0.1.isEmpty }, id: \.0) { title, list in
            LazyVStack(alignment: .leading, spacing: 2) {
                EyebrowView(text: "\(title) · \(list.count)")
                    .padding(.bottom, 6)
                ForEach(Array(list.enumerated()), id: \.offset) { _, member in
                    MemberRowView(member: member)
                    Divider()
                }
            }
        }
    }
}

/// One member: its declaration and first sentence, unfolding to its whole contract.
struct MemberRowView: View {
    /// The member the row shows: its contract and first sentence, unfolding to its whole doc and findings.
    var member: Atlas.Reviewed
    @State private var isOpen = false

    var body: some View {
        let brief = member.summary.map(Wording.firstSentence)
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = member.summary, summary != brief { DocTextView(text: summary) }
                if !member.parameters.isEmpty {
                    TermsView(title: "Parameters", rows: member.parameters.map { ($0.name, $0.doc ?? "Undocumented.", $0.doc == nil) })
                }
                if let returns = member.returns { TermsView(title: "Returns", rows: [(member.returnType ?? "", returns, false)]) }
                if let throwsDoc = member.throwsDoc { TermsView(title: "Throws", rows: [(member.throwsClause ?? "throws", throwsDoc, false)]) }
                ForEach(Array(member.callouts.enumerated()), id: \.offset) { _, callout in
                    TermsView(title: callout.keyword, rows: [("", callout.text, false)])
                }
                ForEach(member.notes, id: \.self) { note in NoteView(text: note) }
                if let exemption = member.exemption {
                    Text("Exempt: \(exemption)").font(.caption).foregroundStyle(.secondary)
                }
                FindingsView(findings: member.findings)
                SourceLinkView(file: member.file, line: member.line)
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CodeView(runs: Highlight.runs(of: member.contract))
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(isOpen ? nil : 2)
                    if !member.findings.isEmpty {
                        Circle().fill(Palette.danger).frame(width: 6, height: 6)
                    }
                }
                if let brief {
                    DocTextView(text: brief).font(.callout).foregroundStyle(.secondary)
                } else if member.requiresDoc {
                    Text("Undocumented").font(.callout).foregroundStyle(Palette.danger)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: Pieces

/// A view's heading: a small label, a title, and one line of context.
struct HeadingView: View {
    /// The small uppercase label over the title, such as Module, or `nil` for none.
    var eyebrow: String?
    /// The page's name, set large in an italic serif.
    var title: String
    /// One line of context under the title, such as how many types the page holds, or `nil` for none.
    var lede: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { EyebrowView(text: eyebrow) }
            Text(title).font(.system(.title, design: .serif).italic())
            if let lede { Text(lede).foregroundStyle(.secondary) }
        }
    }
}

/// A dot in a module's color, the cue that ties its name in the list and the details to its lanes and
/// boxes on the map.
struct ModuleDotView: View {
    @Environment(Workspace.self) private var workspace
    /// The module whose color the dot shows; a module the atlas does not know draws nothing.
    var module: String

    var body: some View {
        if let slot = workspace.atlas?.moduleColors[module] {
            Circle().fill(Palette.moduleInk(slot)).frame(width: 7, height: 7)
        }
    }
}

/// A small uppercase label over a section.
struct EyebrowView: View {
    /// The label, which the view sets in uppercase.
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Doc text with its code spans set in code.
struct DocTextView: View {
    /// Doc text as written, with its inline Markdown rendered; text that does not parse shows as written.
    var text: String
    /// The color of the code spans, or `nil` to draw them in the text's own color.
    var codeColor: Color?

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        if let codeColor {
            for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].foregroundColor = codeColor
            }
        }
        return Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One paragraph of a doc's notes: prose, or fenced code, which the model keeps whole and this draws as
/// a block, colored when it is Swift.
struct NoteView: View {
    /// A paragraph from a contract's notes; fenced code starts with its opening fence.
    var text: String

    var body: some View {
        if let (language, code) = Self.fenced(text) {
            ScrollView(.horizontal) {
                Group {
                    if language.isEmpty || language == "swift" {
                        CodeView(runs: Highlight.runs(code))
                    } else {
                        Text(code)
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .fixedSize()
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        } else {
            DocTextView(text: text)
        }
    }

    /// Splits fenced code into its language and its lines, fences dropped.
    ///
    /// - Parameter text: A note paragraph.
    /// - Returns: The language after the opening fence, empty when none is named, and the code; `nil` for prose.
    static func fenced(_ text: String) -> (language: String, code: String)? {
        guard text.hasPrefix("```") else { return nil }
        var lines = text.components(separatedBy: "\n")
        let language = lines.removeFirst().drop { $0 == "`" }.trimmingCharacters(in: .whitespaces)
        if lines.count > 0, lines[lines.count - 1].trimmingCharacters(in: .whitespaces).hasPrefix("```") { lines.removeLast() }
        return (language, lines.joined(separator: "\n"))
    }
}

/// A titled list of names and what each one means, for parameters, returns, throws, and callouts.
struct TermsView: View {
    /// The heading over the rows: Parameters, Returns, Throws, or a callout's keyword.
    var title: String
    /// The rows: each term set in code, or empty to show the text alone; what it means; and whether its doc
    /// is missing, which draws the text in ``Palette/danger``.
    var rows: [(term: String, text: String, missing: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowView(text: title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !row.term.isEmpty {
                        Text(row.term).font(.system(.callout, design: .monospaced))
                    }
                    DocTextView(text: row.text).font(.callout).foregroundStyle(row.missing ? Palette.danger : .primary)
                }
            }
        }
    }
}

/// The findings the linter made on one declaration.
struct FindingsView: View {
    /// The findings to list, each rule beside its message; empty shows nothing.
    var findings: [Assessment.Finding]

    var body: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(finding.rule).font(.system(.caption, design: .monospaced).weight(.semibold))
                        Text(finding.message).font(.callout)
                    }
                    .foregroundStyle(Palette.danger)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.danger.opacity(0.08)))
        }
    }
}

/// Where a declaration is written, opening it in Xcode.
struct SourceLinkView: View {
    @Environment(Workspace.self) private var workspace
    /// The file path as the interface names it, relative to the open folder.
    var file: String
    /// The 1-based line of the declaration, shown after the path and where Xcode opens the file.
    var line: Int

    var body: some View {
        Button { workspace.reveal(file, line: line) } label: {
            Label("\(file):\(line)", systemImage: "arrow.up.forward.app")
                .font(.caption)
        }
        .buttonStyle(.link)
        // The file on disk is not the one read when the window shows another revision.
        .disabled(workspace.head != nil)
        .help(workspace.head.map { "This is \(file) at \($0); the file on disk may differ" } ?? "Open in Xcode")
    }
}

/// A titled row of chips, or nothing when there are none.
struct ChipBlockView: View {
    /// The heading over the chips, shown with their count; empty shows the chips alone.
    var title: String
    /// The types, modules, or folders to show as chips, in order; empty shows nothing, title included.
    var units: [MapScope.Unit]
    /// The arranged interface the chips read their names and findings from.
    var atlas: Atlas
    /// A tooltip for each chip, at the same index.
    var notes: [String] = []
    @State private var showsAll = false

    /// The most chips shown before the rest wait behind a button: about a screenful, since laying out
    /// hundreds of chips at once holds up the page.
    static let limit = 40

    var body: some View {
        if !units.isEmpty {
            let shown = showsAll ? units.count : min(units.count, Self.limit)
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    HStack(spacing: 6) {
                        Text(title).font(.callout.weight(.semibold))
                        Text("\(units.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Wrap(spacing: 6) {
                    ForEach(Array(units.prefix(shown).enumerated()), id: \.offset) { index, unit in
                        ChipView(unit: unit, atlas: atlas, note: index < notes.count ? notes[index] : nil)
                    }
                    if shown < units.count {
                        Button("\(units.count - shown) more") { showsAll = true }
                            .buttonStyle(.link)
                            .font(.callout)
                            .help("Show every one")
                    }
                }
            }
        }
    }
}

/// A link to a type, module, or folder that lights its box on the map while hovered.
struct ChipView: View {
    @Environment(Workspace.self) private var workspace
    @State private var isHovered = false
    /// The type, module, or folder the chip names, selects when clicked, and lights on the map while hovered;
    /// a nested type lights its root's box.
    var unit: MapScope.Unit
    /// The arranged interface the chip reads its name, its type's findings, and its type's root from.
    var atlas: Atlas
    /// The chip's tooltip, or `nil` to show its name.
    var note: String?

    var body: some View {
        let dirty: Bool = if case .type(let id) = unit { atlas.group(id).findingCount > 0 } else { false }
        let lights: String = if case .type(let id) = unit { atlas.byID[id]?.root ?? id } else { unit.id }
        Button {
            let target = Workspace.selection(of: unit)
            if NSEvent.modifierFlags.contains(.command) { workspace.openInNewTab(target) } else { workspace.select(target) }
        } label: {
            Text(atlas.label(of: unit))
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(isHovered ? Palette.accent : .primary)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isHovered ? Palette.accent : dirty ? Palette.danger : Palette.line))
        }
        .buttonStyle(.plain)
        .help(note ?? atlas.label(of: unit))
        .onHover { inside in
            isHovered = inside
            workspace.hovered = inside ? lights : nil
        }
        .contextMenu {
            Button("Open in New Tab") { workspace.openInNewTab(Workspace.selection(of: unit)) }
        }
    }
}

/// Lays out views in rows, wrapping to a new row when the next one does not fit.
struct Wrap {
    /// The gap in points between neighbors in a row and between rows.
    var spacing: CGFloat
}

extension Wrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = size(of: subviews[index], within: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    /// A subview's size at its ideal width, or narrowed to the row's width when wider, so a long name
    /// truncates rather than widening the page.
    ///
    /// - Parameters:
    ///   - subview: The subview.
    ///   - width: The width of a row.
    /// - Returns: The size it takes.
    private func size(of subview: LayoutSubview, within width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width <= width ? ideal : subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for index in subviews.indices {
            let size = size(of: subviews[index], within: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([], current.y + current.height + spacing, 0, 0)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

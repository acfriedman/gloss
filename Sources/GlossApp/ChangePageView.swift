import GlossRead
import GlossModel
import GlossMap
import SwiftUI

/// The bar over the selected type's page on the changes level: what the page shows, and a button that
/// trades it for the type's whole page and back.
struct ChangePageBarView: View {
    @Environment(Workspace.self) private var workspace
    /// The id of the selected type.
    var id: String

    var body: some View {
        let name = workspace.atlas?.label(of: .type(id)) ?? id
        let phrase = workspace.comparisonPhrase
        let nodeChange = workspace.diff?.change(ofNode: id)
        let change = nodeChange?.change
        HStack(spacing: 8) {
            Image(systemName: "plusminus")
            Text(workspace.showsFullPage ? "All of \(name)"
                 : change == .added ? "\(name) is new \(phrase)"
                 : change == .moved ? "\(name) moved from \(nodeChange?.movedFrom?.module ?? "another module") \(phrase)"
                 : change == .implementation ? "What changed inside \(name) \(phrase)"
                 : change != nil ? "What changed in \(name) \(phrase)" : "How the changes \(phrase) reach \(name)")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                workspace.showsFullPage.toggle()
            } label: {
                Text(workspace.showsFullPage ? "Changes Only" : "Full Page")
            }
            .controlSize(.small)
            .help(workspace.showsFullPage ? "Show only what changed" : "Show \(name)'s whole page")
        }
        .textStyle(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// A type on the changes level: its declaration and doc, then only what changed in it since the base,
/// or, for a type that did not change itself, how the changes reach it.
struct ChangePageView: View {
    /// The arranged interface the page reads the type, its members, and the reasons from.
    var atlas: Atlas
    /// The type.
    var node: Graph.Node
    /// How the interface differs from the base.
    var diff: InterfaceDiff

    var body: some View {
        TypeHeaderView(atlas: atlas, node: node)
        if let change = diff.change(ofNode: node.id) {
            StoryThemesView(id: node.id)
            DeclarationChangesView(atlas: atlas, change: change)
            let nested = diff.nodes.filter { $0.node.id.hasPrefix(node.id + ".") }
            if !nested.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowView(text: "Nested types that changed · \(nested.count)")
                    ForEach(Array(nested.enumerated()), id: \.offset) { _, change in
                        NodeChangeView(change: change, atlas: atlas)
                    }
                }
            }
            // What the type depends on is its own change, whatever is at the other end. A new type that
            // depends on it is that type's change, said on its page, so only users already there are listed.
            let added = Set(diff.nodes.filter { $0.change == .added }.map(\.node.id))
            let edges = diff.edges.filter { $0.from == node.id || ($0.to == node.id && !added.contains($0.from)) }
            if !edges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowView(text: "Dependencies that changed · \(edges.count)")
                    ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                        DependencyChangeView(edge: edge, atlas: atlas)
                    }
                }
            }
        } else {
            ReachedView(atlas: atlas, id: node.id, diff: diff, reasons: atlas.changeReasons(of: node.id, in: diff))
        }
    }
}

/// The declarations of a new or changed type that differ from the base: each new one and each changed
/// one as a member row that unfolds to its contract, saying what changed and what was written before,
/// and each gone one as the base wrote it.
struct DeclarationChangesView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the rows read the members from.
    var atlas: Atlas
    /// The type's change.
    var change: InterfaceDiff.NodeChange

    var body: some View {
        let members = atlas.group(change.node.id).members
        // The type's own declaration heads the page already; changed, it is said once, here.
        let own = change.declarations.first { ["struct", "class", "enum", "protocol", "actor"].contains($0.keyword) }
        let rows = change.declarations.filter { $0 != own }
        VStack(alignment: .leading, spacing: 2) {
            if let was = change.movedFrom {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ChangeBadgeView(change: .moved)
                    Text("Moved from \(was.module) to \(change.node.module)\(change.declarations.isEmpty ? ", declared the same." : ".")")
                        .textStyle(.callout)
                }
                .padding(.bottom, 10)
            }
            if let own, change.change == .changed || change.change == .moved {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ChangeBadgeView(change: .changed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The declaration itself changed: its \(Self.what(own)).").textStyle(.callout)
                        if own.signatureChanged, let was = own.was { WasNowView(was: was, now: nil, atlas: atlas) }
                    }
                }
                .padding(.bottom, 10)
            }
            // Why the type itself is new, gone, moved, or declared differently, beside that change.
            TypeNotesView(node: change.node.id)
            if !(change.change == .moved && rows.isEmpty) {
                EyebrowView(text: change.change == .added ? "New \(workspace.comparisonPhrase) · \(rows.count)" : "Declarations that changed · \(rows.count)")
                    .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, declaration in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ChangeBadgeView(change: declaration.change)
                    VStack(alignment: .leading, spacing: 4) {
                        if let now = declaration.now,
                           let member = members.first(where: { $0.contract.keyword == declaration.keyword && $0.contract.declaration == now }) {
                            MemberRowView(member: member)
                        } else if let was = declaration.was {
                            CodeView(runs: Highlight.runs(was, projectTypes: Self.projectTypes(atlas)))
                                .textStyle(.callout, design: .monospaced)
                                .strikethrough(color: Palette.removed)
                                .padding(.vertical, 6)
                        }
                        if declaration.change == .changed || declaration.change == .implementation {
                            Text("Its \(Self.what(declaration)) changed.")
                                .textStyle(.caption)
                                .foregroundStyle(.secondary)
                            if declaration.signatureChanged, let was = declaration.was { WasNowView(was: was, now: nil, atlas: atlas) }
                            if declaration.docChanged, declaration.wasSummary != declaration.nowSummary {
                                DocWasNowView(was: declaration.wasSummary, now: declaration.nowSummary)
                            }
                        } else if declaration.change == .removed {
                            Text("Gone.")
                                .textStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                        MemberNotesView(node: change.node.id, name: declaration.name)
                    }
                    .padding(.bottom, declaration.change == .added ? 0 : 6)
                }
                Divider()
            }
        }
    }

    /// What changed in a declaration, as a noun phrase: its signature, its doc, its body, or several.
    ///
    /// - Parameter declaration: A changed declaration.
    /// - Returns: Such as `signature`, `body`, or `signature, doc, and body`.
    static func what(_ declaration: InterfaceDiff.DeclarationChange) -> String {
        Wording.list([declaration.signatureChanged ? "signature" : nil, declaration.docChanged ? "doc" : nil,
                      declaration.bodyChanged ? "body" : nil].compactMap { $0 })
    }

    /// The names the scanned sources declare, so declarations written in the base color their types as
    /// the head's do.
    ///
    /// - Parameter atlas: The arranged interface.
    /// - Returns: Each node name's path components.
    static func projectTypes(_ atlas: Atlas) -> Set<String> {
        Set(atlas.nodes.flatMap { $0.name.split(separator: ".").map(String.init) })
    }
}

/// A declaration as the base wrote it, and as written now when the row does not show it already.
struct WasNowView: View {
    /// The declaration as the base wrote it.
    var was: String
    /// The declaration as written now, or `nil` when the row above shows it.
    var now: String?
    /// The arranged interface, for the names its types are colored by.
    var atlas: Atlas

    var body: some View {
        let types = DeclarationChangesView.projectTypes(atlas)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                Text("was").textStyle(.caption).foregroundStyle(Palette.removed)
                CodeView(runs: Highlight.runs(was, projectTypes: types)).textStyle(.caption, design: .monospaced)
            }
            if let now {
                GridRow {
                    Text("now").textStyle(.caption).foregroundStyle(Palette.added)
                    CodeView(runs: Highlight.runs(now, projectTypes: types)).textStyle(.caption, design: .monospaced)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

/// One dependency that differs from the base, read as a sentence: who depends on whom, and how now
/// and before.
struct DependencyChangeView: View {
    /// The dependency's change.
    var edge: InterfaceDiff.EdgeChange
    /// The arranged interface the links read their names from.
    var atlas: Atlas

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ChangeBadgeView(change: edge.change)
            Wrap(spacing: 6) {
                ChipView(unit: .type(edge.from), atlas: atlas)
                Text(edge.change == .removed ? "no longer \(Wording.words(edge.before))"
                     : edge.before.isEmpty || edge.before == edge.after ? Wording.words(edge.after) : "now \(Wording.words(edge.after))")
                    .textStyle(.callout)
                ChipView(unit: .type(edge.to), atlas: atlas)
                if edge.change == .changed {
                    Text(edge.before != edge.after ? "(was: \(Wording.words(edge.before)))" : Self.through(edge))
                        .textStyle(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Which declarations make a dependency now that did not before, and which no longer do.
    ///
    /// - Parameter edge: A changed dependency whose roles stayed the same.
    /// - Returns: A parenthetical, such as `(through Cart.tidy now, not Cart.total)`.
    static func through(_ edge: InterfaceDiff.EdgeChange) -> String {
        let now = edge.viaAdded.isEmpty ? nil : "through \(Wording.list(edge.viaAdded)) now"
        let gone = edge.viaRemoved.isEmpty ? nil : "not \(Wording.list(edge.viaRemoved))"
        return "(" + [now, gone].compactMap { $0 }.joined(separator: ", ") + ")"
    }
}

/// How the changes reach a type that did not change itself, one row per way, or that none does.
struct ReachedView: View {
    @Environment(Workspace.self) private var workspace
    /// The arranged interface the rows read names from.
    var atlas: Atlas
    /// The reached type's id.
    var id: String
    /// The change.
    var diff: InterfaceDiff
    /// The ways, as ``GlossMap/Atlas/changeReasons(of:in:)`` gives them.
    var reasons: [ChangeReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowView(text: "How the changes reach it")
            if reasons.isEmpty {
                Text("They do not: its dependencies on changed types are as they were, and it uses nothing in them that changed.")
                    .textStyle(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                ReachRowView(reason: reason, atlas: atlas,
                             why: atlas.why(reason, reaching: id, in: diff, story: workspace.story,
                                            coverage: workspace.storyCoverage, commits: workspace.changeCommits))
            }
        }
    }

    /// The type's declarations that reach a member, by name alone, since the page is the type's own.
    ///
    /// - Parameter via: Qualified names, the type's and the declaration's joined by a dot.
    /// - Returns: The declarations' own names, as a list.
    static func callers(_ via: [String]) -> String {
        Wording.list(via.map { String($0.split(separator: ".").last ?? Substring($0)) })
    }
}

/// One way a change reaches a type: what reaches it in a line, then why that changed, set as the story's
/// reasons are, and why the type relies on it, in its doc's quieter text, a sentence or two each, with
/// the rest folded beneath, so one reach is one thought.
struct ReachRowView: View {
    /// The way the change reaches the type.
    var reason: ChangeReason
    /// The arranged interface the links read their names from.
    var atlas: Atlas
    /// Why the change was made and why the type relies on it.
    var why: ReachWhy
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            what
            VStack(alignment: .leading, spacing: 6) {
                // Why it changed is the change's reason, the story's or a commit's, so it reads as a note does.
                if let changed = why.changed {
                    StoryReasonView(text: changed.lead)
                } else {
                    Text("Neither the story nor a commit says why it changed.").textStyle(.callout).foregroundStyle(.tertiary)
                }
                // A dependency that is gone is relied on no more, so only one still there is asked why.
                if !isDropped {
                    let first = why.uses.first
                    let user = why.user == reason.changed ? atlas.byID[why.user].map(atlas.label) ?? why.user : first?.name ?? "it"
                    WhyLineView(title: "Why \(user) relies on it", answer: first?.answer,
                                missing: first.map { "\($0.name)'s doc doesn't say why." } ?? "Nothing it declares says why.")
                }
                if hasMore {
                    Button { isOpen.toggle() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            Text(isOpen ? "Less" : "More")
                        }
                        .textStyle(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if isOpen { more }
            }
            .padding(.leading, 20)
        }
    }

    /// The reach in a line: who relies on what, and what about it changed.
    @ViewBuilder private var what: some View {
        switch reason.kind {
        case .dependency(let edge):
            DependencyChangeView(edge: edge, atlas: atlas)
        case .declaration:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ChangeBadgeView(change: .changed)
                Wrap(spacing: 6) {
                    Text("Uses").textStyle(.callout)
                    ChipView(unit: .type(reason.changed), atlas: atlas)
                    Text("whose declaration changed").textStyle(.callout)
                }
            }
        case .member(let member):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ChangeBadgeView(change: member.change)
                Wrap(spacing: 6) {
                    Text(ReachedView.callers(reason.via)).textStyle(.callout, design: .monospaced)
                    Text(reason.via.count == 1 ? "uses" : "use").textStyle(.callout)
                    ChipView(unit: .type(reason.changed), atlas: atlas)
                    Text(".\(member.name)").textStyle(.callout, design: .monospaced)
                    Text(member.change == .removed ? "which is gone" : "whose signature changed").textStyle(.callout)
                }
            }
        }
    }

    /// The declaration as it was and is, when the reach is through one.
    private var declaration: InterfaceDiff.DeclarationChange? {
        switch reason.kind {
        case .member(let change), .declaration(let change): change
        case .dependency: nil
        }
    }

    /// Whether the reach is a dependency that is gone, which nothing relies on any more.
    private var isDropped: Bool {
        if case .dependency(let edge) = reason.kind { return edge.change == .removed }
        return false
    }

    /// Whether anything is folded: what was written, the rest of either answer, or more declarations.
    private var hasMore: Bool {
        declaration?.was != nil || !(why.changed?.more.isEmpty ?? true)
            || (!isDropped && (why.uses.count > 1 || !(why.uses.first?.answer?.more.isEmpty ?? true)))
    }

    /// What unfolds: the declaration before and now, each answer's rest and where it was written, and the
    /// other declarations that rely on the change.
    @ViewBuilder private var more: some View {
        if let declaration, let was = declaration.was { WasNowView(was: was, now: declaration.now, atlas: atlas) }
        if let changed = why.changed { WhyMoreView(answer: changed) }
        if !isDropped {
            if let answer = why.uses.first?.answer { WhyMoreView(answer: answer) }
            ForEach(Array(why.uses.dropFirst().enumerated()), id: \.offset) { _, use in
                WhyLineView(title: "Why \(use.name) relies on it", answer: use.answer, missing: "\(use.name)'s doc doesn't say why.")
            }
        }
    }
}

/// One doc's why: a small title, then the answer's lead in a sentence or two, quieter as doc text is,
/// or a quieter line still when the doc says nothing.
struct WhyLineView: View {
    /// What the line answers, such as `Why it changed`.
    var title: String
    /// The answer, or `nil` when nothing was written.
    var answer: ReachWhy.Answer?
    /// What to say when nothing was written.
    var missing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textStyle(.caption, weight: .semibold).foregroundStyle(.secondary)
            if let answer {
                DocTextView(text: StoryProse.markdown(answer.lead), codeColor: Palette.accent).textStyle(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(missing).textStyle(.callout).foregroundStyle(.tertiary)
            }
        }
    }
}

/// The rest of an answer, unfolded: where it was written, then what follows its lead there.
struct WhyMoreView: View {
    /// The answer.
    var answer: ReachWhy.Answer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From \(answer.source)").textStyle(.caption).foregroundStyle(.secondary)
            ForEach(Array(answer.more.enumerated()), id: \.offset) { _, paragraph in
                DocTextView(text: StoryProse.markdown(paragraph), codeColor: Palette.accent).textStyle(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// A declaration's doc summary as the base wrote it and as it reads now.
struct DocWasNowView: View {
    /// The summary in the base, or `nil` when it had none.
    var was: String?
    /// The summary now, or `nil` when it has none.
    var now: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
            GridRow {
                Text("doc was").textStyle(.caption).foregroundStyle(Palette.removed)
                Text(was ?? "No summary.").textStyle(.caption).foregroundStyle(.secondary)
            }
            GridRow {
                Text("now").textStyle(.caption).foregroundStyle(Palette.added)
                Text(now ?? "No summary.").textStyle(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}


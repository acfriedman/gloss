import GlossCore
import GlossMap
import SwiftUI

/// The middle pane: the text of whatever is selected, from the overview down to one type's members.
///
/// A preview is laid over the selection rather than replacing it, so when the preview ends the
/// selection is back where the reader left it: scrolled to the same place, members still open.
struct DetailPaneView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ZStack(alignment: .top) {
            DetailPageView(target: workspace.selection)
                .id(workspace.selection)
            if let preview = workspace.preview {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                        Text("Previewing. Click it to keep it here.")
                        Spacer()
                        Button("Keep") { workspace.select(preview) }
                            .controlSize(.small)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(.bar)
                    Divider()
                    DetailPageView(target: preview)
                }
                .id(preview)
            }
        }
        .onHover { workspace.detailsHovered($0) }
    }
}

/// One page of the details pane, scrolled from its top.
struct DetailPageView: View {
    @Environment(Workspace.self) private var workspace
    /// What the page shows, the selection or the preview laid over it; a type the atlas no longer holds
    /// leaves the page empty.
    var target: Workspace.Selection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let atlas = workspace.atlas {
                    switch target {
                    case .overview: OverviewView(atlas: atlas)
                    case .modules: ModulesView(atlas: atlas)
                    case .module(let module): ModuleView(atlas: atlas, module: module)
                    case .folder(let module, let folder): FolderView(atlas: atlas, module: module, folder: folder)
                    case .type(let id): if let node = atlas.byID[id] { TypeView(atlas: atlas, node: node) }
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
                    EyebrowView(text: module)
                    ForEach(entries, id: \.id) { node in
                        CardView(atlas: atlas, node: node)
                    }
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
        FlowView(atlas: atlas, incoming: incoming, outgoing: outgoing, nested: nested)
        MembersView(members: group.members.filter { Contract.rank($0.access) >= workspace.minimumRank })
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
            VStack(alignment: .leading, spacing: 2) {
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

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
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
        .help("Open in Xcode")
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

    var body: some View {
        if !units.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    HStack(spacing: 6) {
                        Text(title).font(.callout.weight(.semibold))
                        Text("\(units.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Wrap(spacing: 6) {
                    ForEach(Array(units.enumerated()), id: \.offset) { index, unit in
                        ChipView(unit: unit, atlas: atlas, note: index < notes.count ? notes[index] : nil)
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
        Button { workspace.select(unit: unit) } label: {
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
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
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

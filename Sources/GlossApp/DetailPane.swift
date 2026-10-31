import GlossCore
import GlossMap
import SwiftUI

/// The middle pane: the text of whatever is selected, from the start page down to one type's members.
struct DetailPane: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let atlas = workspace.atlas {
                    switch workspace.selection {
                    case .start: StartView(atlas: atlas)
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

/// The front door: per module, the types other code reaches first.
struct StartView: View {
    @Environment(Workspace.self) private var workspace
    var atlas: Atlas

    var body: some View {
        Heading(eyebrow: "Start here", title: "The front door of \(workspace.name)",
                lede: "These are the types other code reaches first: each one is used from another module, or is used by nothing else in its own. Open one to see what flows into and out of it, then follow those types inward.")
        ForEach(atlas.modules, id: \.self) { module in
            let entries = atlas.entryPoints(in: module).filter(workspace.isShown)
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: module)
                    ForEach(entries, id: \.id) { node in
                        Card(atlas: atlas, node: node)
                    }
                }
            }
        }
    }
}

/// A type on the start page: its kind, name, first sentence, and who uses it.
struct Card: View {
    @Environment(Workspace.self) private var workspace
    var atlas: Atlas
    var node: Graph.Node

    var body: some View {
        let group = atlas.group(node.id)
        let operations = group.members.filter { Wording.isCallable($0.keyword) && Contract.rank($0.access) >= 1 && !$0.isOverride }.count
        let users = atlas.users(of: node.id)
        let summary = group.head?.summary.map(Wording.firstSentence)
            ?? (node.keyword == "file" ? "The module's file-scope code: for an executable, its entry point." : nil)
        let facts = (operations > 0 ? ["\(operations) operation\(operations == 1 ? "" : "s")"] : [])
            + (users.isEmpty ? [] : ["used by " + users.map(atlas.label).joined(separator: ", ")])
        Button { workspace.select(.type(node.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Wording.kind(of: node).uppercased())
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Text(atlas.label(node)).font(.system(.body, design: .monospaced).weight(.semibold))
                if let summary { DocText(text: summary).foregroundStyle(.primary) }
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
    var atlas: Atlas

    var body: some View {
        Heading(eyebrow: "Modules", title: "\(atlas.modules.count) modules",
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

/// One module: its front door, the modules it depends on and is used by, its folders, and its types.
struct ModuleView: View {
    var atlas: Atlas
    var module: String

    var body: some View {
        let (uses, usedBy) = atlas.dependencies(ofModule: module)
        let folders = atlas.folders(in: module)
        Heading(eyebrow: "Module", title: module, lede: atlas.summary(of: atlas.types(in: module)))
        ChipBlock(title: "Front door", units: atlas.entryPoints(in: module).map { .type($0.id) }, atlas: atlas)
        ChipBlock(title: "Depends on", units: uses.map { .module($0) }, atlas: atlas)
        ChipBlock(title: "Used by", units: usedBy.map { .module($0) }, atlas: atlas)
        if folders.count > 1 { ChipBlock(title: "Folders", units: folders.map { .folder(module, $0) }, atlas: atlas) }
        ChipBlock(title: "Types", units: atlas.types(in: module).map { .type($0.id) }, atlas: atlas)
    }
}

/// One folder drawn as its own level: what it depends on outside itself, what uses it, and its types.
struct FolderView: View {
    var atlas: Atlas
    var module: String
    var folder: String

    var body: some View {
        let (uses, usedBy) = atlas.dependencies(ofFolder: folder, in: module)
        let members = atlas.types(inFolder: folder, of: module)
        Heading(eyebrow: "\(module) · folder", title: Wording.folderLabel(folder), lede: atlas.summary(of: members))
        ChipBlock(title: "Depends on", units: uses, atlas: atlas)
        ChipBlock(title: "Used by", units: usedBy, atlas: atlas)
        ChipBlock(title: "Types", units: members.map { .type($0.id) }, atlas: atlas)
    }
}

// MARK: A type

/// One type: its declaration and doc, what flows into and out of it, and its members.
struct TypeView: View {
    @Environment(Workspace.self) private var workspace
    var atlas: Atlas
    var node: Graph.Node

    var body: some View {
        let group = atlas.group(node.id)
        let (incoming, outgoing, nested) = atlas.neighbors(of: node)
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "\(node.module) · \(Wording.kind(of: node))")
            if let head = group.head {
                Text(head.declaration)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                if let summary = head.summary { DocText(text: summary).font(.title3) }
                ForEach(head.notes, id: \.self) { note in DocText(text: note) }
                Findings(findings: head.findings)
                SourceLink(file: head.file, line: head.line)
            } else {
                Text(atlas.label(node)).font(.system(.title3, design: .monospaced).weight(.semibold))
                Text(node.keyword == "extension" ? "Extends a type no scanned source declares." : "Declarations at file scope.")
                    .foregroundStyle(.secondary)
            }
        }
        Flow(atlas: atlas, node: node, incoming: incoming, outgoing: outgoing, nested: nested)
        Members(atlas: atlas, members: group.members.filter { Contract.rank($0.access) >= workspace.minimumRank })
    }
}

/// What flows into and out of a type, read top to bottom: what uses it, then what it conforms to,
/// holds, takes, returns, and throws, then what it uses only inside its bodies.
struct Flow: View {
    var atlas: Atlas
    var node: Graph.Node
    var incoming: [Graph.Edge]
    var outgoing: [Graph.Edge]
    var nested: [Graph.Node]

    var body: some View {
        let roles: [(Mention.Role, String)] = [(.conformance, "Conforms to"), (.property, "Holds"), (.parameter, "Takes"),
                                               (.returns, "Returns"), (.throws, "Throws")]
        let insideOnly = outgoing.filter { $0.roles == [.body] }
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "Flow")
            ChipBlock(title: "Used by", units: incoming.map { .type($0.from) }, atlas: atlas,
                      notes: incoming.map { Wording.words($0.roles) })
            ForEach(roles, id: \.0) { role, title in
                ChipBlock(title: title, units: outgoing.filter { $0.roles.contains(role) }.map { .type($0.to) }, atlas: atlas)
            }
            if !nested.isEmpty {
                ChipBlock(title: "Nests", units: nested.map { .type($0.id) }, atlas: atlas)
            }
            if !insideOnly.isEmpty {
                DisclosureGroup {
                    ChipBlock(title: "", units: insideOnly.map { .type($0.to) }, atlas: atlas)
                        .padding(.top, 6)
                } label: {
                    Text("Uses \(insideOnly.count) more type\(insideOnly.count == 1 ? "" : "s") inside its bodies")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A type's members, grouped by what a caller does with them; overrides fold away, since their
/// contract is the inherited one.
struct Members: View {
    var atlas: Atlas
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
                Eyebrow(text: "\(title) · \(list.count)")
                    .padding(.bottom, 6)
                ForEach(Array(list.enumerated()), id: \.offset) { _, member in
                    MemberRow(member: member)
                    Divider()
                }
            }
        }
    }
}

/// One member: its declaration and first sentence, unfolding to its whole contract.
struct MemberRow: View {
    var member: Atlas.Reviewed
    @State private var isOpen = false

    var body: some View {
        let brief = member.summary.map(Wording.firstSentence)
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = member.summary, summary != brief { DocText(text: summary) }
                if !member.parameters.isEmpty {
                    Terms(title: "Parameters", rows: member.parameters.map { ($0.name, $0.doc ?? "Undocumented.", $0.doc == nil) })
                }
                if let returns = member.returns { Terms(title: "Returns", rows: [(member.returnType ?? "", returns, false)]) }
                if let throwsDoc = member.throwsDoc { Terms(title: "Throws", rows: [(member.throwsClause ?? "throws", throwsDoc, false)]) }
                ForEach(Array(member.callouts.enumerated()), id: \.offset) { _, callout in
                    Terms(title: callout.keyword, rows: [("", callout.text, false)])
                }
                ForEach(member.notes, id: \.self) { note in DocText(text: note) }
                if let exemption = member.exemption {
                    Text("Exempt: \(exemption)").font(.caption).foregroundStyle(.secondary)
                }
                Findings(findings: member.findings)
                SourceLink(file: member.file, line: member.line)
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(member.declaration)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(isOpen ? nil : 2)
                    if !member.findings.isEmpty {
                        Circle().fill(.red).frame(width: 6, height: 6)
                    }
                }
                if let brief {
                    DocText(text: brief).font(.callout).foregroundStyle(.secondary)
                } else if member.requiresDoc {
                    Text("Undocumented").font(.callout).foregroundStyle(.red)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: Pieces

/// A view's heading: a small label, a title, and one line of context.
struct Heading: View {
    var eyebrow: String
    var title: String
    var lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(.title, design: .serif).italic())
            Text(lede).foregroundStyle(.secondary)
        }
    }
}

/// A small uppercase label over a section.
struct Eyebrow: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Doc text with its code spans set in code.
struct DocText: View {
    var text: String

    var body: some View {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A titled list of names and what each one means, for parameters, returns, throws, and callouts.
struct Terms: View {
    var title: String
    var rows: [(term: String, text: String, missing: Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !row.term.isEmpty {
                        Text(row.term).font(.system(.callout, design: .monospaced))
                    }
                    DocText(text: row.text).font(.callout).foregroundStyle(row.missing ? .red : .primary)
                }
            }
        }
    }
}

/// The findings the linter made on one declaration.
struct Findings: View {
    var findings: [Assessment.Finding]

    var body: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(finding.rule).font(.system(.caption, design: .monospaced).weight(.semibold))
                        Text(finding.message).font(.callout)
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.08)))
        }
    }
}

/// Where a declaration is written, opening it in Xcode.
struct SourceLink: View {
    @Environment(Workspace.self) private var workspace
    var file: String
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
struct ChipBlock: View {
    var title: String
    var units: [MapScope.Unit]
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
                        Chip(unit: unit, atlas: atlas, note: index < notes.count ? notes[index] : nil)
                    }
                }
            }
        }
    }
}

/// A link to a type, module, or folder that lights its box on the map while hovered.
struct Chip: View {
    @Environment(Workspace.self) private var workspace
    var unit: MapScope.Unit
    var atlas: Atlas
    var note: String?

    var body: some View {
        let dirty: Bool = if case .type(let id) = unit { atlas.group(id).findingCount > 0 } else { false }
        let lights: String = if case .type(let id) = unit { atlas.byID[id]?.root ?? id } else { unit.id }
        Button { workspace.select(unit: unit) } label: {
            Text(atlas.label(of: unit))
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(dirty ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.1)))
                .foregroundStyle(dirty ? Color.red : Color.accentColor)
        }
        .buttonStyle(.plain)
        .help(note ?? atlas.label(of: unit))
        .onHover { workspace.hovered = $0 ? lights : nil }
    }
}

/// Lays out views in rows, wrapping to a new row when the next one does not fit.
struct Wrap {
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

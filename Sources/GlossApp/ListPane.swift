import GlossCore
import GlossMap
import SwiftUI

/// The list: the start page, then each module and its types, nested types indented under their parents.
struct ListPane: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        let selection = Binding<Workspace.Selection?>(
            get: { workspace.selection },
            set: { if let target = $0 { workspace.select(target) } }
        )
        List(selection: selection) {
            Label("Start here", systemImage: "door.left.hand.open")
                .tag(Workspace.Selection?.some(.start))
            if let atlas = workspace.atlas {
                ForEach(atlas.modules, id: \.self) { module in
                    let rows = workspace.listed(in: module)
                    Section {
                        ForEach(rows, id: \.id) { node in
                            TypeRow(node: node, atlas: atlas)
                                .tag(Workspace.Selection?.some(.type(node.id)))
                                .onHover { $0 ? workspace.hoverBegan(.type(node.id)) : workspace.hoverEnded() }
                        }
                    } header: {
                        Button { workspace.select(.module(module)) } label: {
                            Text(module)
                        }
                        .buttonStyle(.plain)
                        .help("Show \(module) and draw its types")
                        .onHover { $0 ? workspace.hoverBegan(.module(module)) : workspace.hoverEnded() }
                    }
                }
            }
        }
        .searchable(text: $workspace.search, placement: .sidebar, prompt: "Find a type or member")
        .safeAreaInset(edge: .bottom) { Summary() }
    }
}

/// One type in the list: its short name, a mark when it has findings, and its member count.
struct TypeRow: View {
    var node: Graph.Node
    var atlas: Atlas

    var body: some View {
        let group = atlas.group(node.id)
        HStack(spacing: 6) {
            Text(atlas.shortLabel(node))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .padding(.leading, CGFloat(atlas.depth(node)) * 12)
            if group.findingCount > 0 {
                Circle().fill(.red).frame(width: 6, height: 6)
                    .help("\(group.findingCount) findings")
            }
            Spacer(minLength: 4)
            Text("\(group.members.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

/// The size of the interface under the list, and the findings filter.
struct Summary: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        if let interface = workspace.interface {
            let owed = zip(interface.contracts, interface.assessments).filter { $0.1.requiresDoc }.map(\.0)
            let findings = interface.assessments.reduce(0) { $0 + $1.findings.count }
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Stat(title: "Declarations", value: "\(interface.contracts.filter { Contract.rank($0.access) >= 1 }.count)")
                        Stat(title: "Public", value: "\(interface.contracts.filter { Contract.rank($0.access) >= 3 }.count)")
                    }
                    GridRow {
                        Stat(title: "Documented", value: "\(owed.filter(\.isDocumented).count)/\(owed.count)")
                        Stat(title: "Findings", value: "\(findings)", tint: findings == 0 ? .green : .red)
                    }
                }
                Toggle("Only types with findings", isOn: $workspace.findingsOnly)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

/// One labeled number in the summary.
struct Stat: View {
    var title: String
    var value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

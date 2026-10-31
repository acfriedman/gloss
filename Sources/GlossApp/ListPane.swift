import GlossCore
import GlossMap
import SwiftUI

/// The list: the overview, then each module as its source folders hold it, every module, folder,
/// and enclosing type opening and closing on its own.
struct ListPane: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        let selection = Binding<Workspace.Selection?>(
            get: { workspace.selection },
            set: { if let target = $0 { workspace.select(target) } }
        )
        // Tags are the plain selection type: a List selects only rows whose tag type matches its
        // selection's value type exactly, so an optional tag would hover but never select.
        ScrollViewReader { proxy in
            List(selection: selection) {
                Label("Overview", systemImage: "square.grid.2x2")
                    .modifier(RowHover(target: .overview))
                    .tag(Workspace.Selection.overview)
                if let atlas = workspace.atlas {
                    ForEach(atlas.modules, id: \.self) { module in
                        Section(isExpanded: workspace.expansion(ofModule: module)) {
                            ForEach(workspace.outline(of: module)) { item in
                                OutlineRow(item: item, atlas: atlas)
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
            // Selecting from the map or a chip opens the rows around the type; this brings it into view.
            .onChange(of: workspace.selection) { _, target in
                proxy.scrollTo(target)
            }
        }
        .searchable(text: $workspace.search, placement: .sidebar, prompt: "Find a type or member")
        .safeAreaInset(edge: .bottom) { Summary() }
    }
}

/// One outline row: a folder, or a type, opening onto what it holds when it holds anything.
struct OutlineRow: View {
    @Environment(Workspace.self) private var workspace
    var item: OutlineItem
    var atlas: Atlas

    var body: some View {
        if item.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: workspace.expansion(of: item.id)) {
                ForEach(item.children) { child in
                    OutlineRow(item: child, atlas: atlas)
                }
            } label: {
                label
            }
        }
    }

    @ViewBuilder private var label: some View {
        switch item.kind {
        case .folder(let name):
            let open = workspace.expansion(of: item.id)
            HStack(spacing: 6) {
                Label(name, systemImage: "folder")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(item.typeCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture { open.wrappedValue.toggle() }
        case .type(let node):
            TypeRow(node: node, atlas: atlas)
                .modifier(RowHover(target: .type(node.id)))
                .tag(Workspace.Selection.type(node.id))
                .id(Workspace.Selection.type(node.id))
        }
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

/// A list row's hover: a subtle highlight while the pointer is on the row or while what it names is
/// previewed from the map, and the preview itself.
struct RowHover {
    @Environment(Workspace.self) private var workspace
    @State private var isHovered = false
    var target: Workspace.Selection
}

extension RowHover: ViewModifier {
    func body(content: Content) -> some View {
        let lit = isHovered || workspace.preview == target
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(lit ? 0.08 : 0)))
            .padding(.horizontal, -6)
            .padding(.vertical, -2)
            .onHover { inside in
                isHovered = inside
                if inside { workspace.hoverBegan(target) } else { workspace.hoverEnded() }
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

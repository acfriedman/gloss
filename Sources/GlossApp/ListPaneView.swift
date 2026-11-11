import LucidRead
import GlossModel
import GlossMap
import SwiftUI

/// The list: the overview, then each module as its source folders hold it, every module, folder,
/// and enclosing type opening and closing on its own.
struct ListPaneView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        // The list keeps its own selection: clicking a row opens it, and nothing the map or the details
        // select moves the list. The blank page has nothing open, so nothing selected.
        let selection = Binding<Workspace.Selection?>(
            get: { workspace.isBlank ? nil : workspace.listSelection },
            set: { target in
                guard let target else { return }
                workspace.listSelection = target
                // Command-click opens the row in a new tab and leaves this one where it is.
                if NSEvent.modifierFlags.contains(.command) { workspace.openInNewTab(target) } else { workspace.select(target) }
            }
        )
        // Tags are the plain selection type: a List selects only rows whose tag type matches its
        // selection's value type exactly, so an optional tag would hover but never select.
        List(selection: selection) {
            Label("Overview", systemImage: "square.grid.2x2")
                .modifier(RowHover(target: .overview))
                .tag(Workspace.Selection.overview)
            Label("Summary", systemImage: "chart.bar.doc.horizontal")
                .modifier(RowHover(target: .summary))
                .tag(Workspace.Selection.summary)
                .help("The interface's size, documentation, and findings")
            if workspace.comparison != .off {
                Label {
                    HStack {
                        Text("Changes")
                        Spacer()
                        if let diff = workspace.diff, !diff.isEmpty {
                            Text("\(diff.nodes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "plusminus")
                }
                .modifier(RowHover(target: .changes))
                .tag(Workspace.Selection.changes)
                .help("What changed \(workspace.comparisonPhrase), and the types one step around it")
            }
            if let atlas = workspace.atlas {
                let list = workspace.listOutline
                if workspace.isFiltering {
                    // A short search in a huge project matches more than the list can draw at once.
                    Text(list.matches == 0 ? "Nothing matches."
                         : list.shown < list.matches ? "Showing the first \(list.shown) of \(list.matches) matches; type more to narrow them."
                         : "\(list.matches) match\(list.matches == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(list.modules) { entry in
                    // While filtering, a module that holds a match is simply open: flipping a section's
                    // expansion as its rows change makes the outline view reenter itself.
                    if workspace.isFiltering {
                        Section { rows(of: entry, atlas: atlas) } header: { header(of: entry.name) }
                    } else {
                        Section(isExpanded: workspace.expansion(ofModule: entry.name)) {
                            rows(of: entry, atlas: atlas)
                        } header: {
                            header(of: entry.name)
                        }
                    }
                }
            }
        }
        .searchable(text: $workspace.search, placement: .sidebar, prompt: "Find a type or member")
        .safeAreaInset(edge: .bottom) { ListFilterView() }
    }

    /// A module's rows in the list.
    ///
    /// - Parameters:
    ///   - entry: The module and its rows, as the list worked them out.
    ///   - atlas: The arranged interface the rows read their names and findings from.
    /// - Returns: One row per folder or type at the top of the module.
    private func rows(of entry: ListOutline.Module, atlas: Atlas) -> some View {
        ForEach(entry.rows) { item in
            OutlineRowView(item: item, atlas: atlas)
        }
    }

    /// A module's header: its color and name, which opens the module's page.
    ///
    /// - Parameter module: The module's name.
    /// - Returns: The header.
    private func header(of module: String) -> some View {
        Button { workspace.select(.module(module)) } label: {
            HStack(spacing: 6) {
                ModuleDotView(module: module)
                Text(module)
            }
        }
        .buttonStyle(.plain)
        .help("Show \(module) and draw its types")
        .onHover { $0 ? workspace.hoverBegan(.module(module)) : workspace.hoverEnded() }
    }
}

/// One outline row: a folder, or a type, opening onto what it holds when it holds anything.
struct OutlineRowView: View {
    @Environment(Workspace.self) private var workspace
    /// The folder or type the row shows, with the rows it opens onto.
    var item: OutlineItem
    /// The arranged interface the type rows read their names, findings, and member counts from.
    var atlas: Atlas

    var body: some View {
        if item.children.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: workspace.expansion(of: item.id)) {
                ForEach(item.children) { child in
                    OutlineRowView(item: child, atlas: atlas)
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
            TypeRowView(node: node, atlas: atlas)
                .modifier(RowHover(target: .type(node.id)))
                .tag(Workspace.Selection.type(node.id))
        }
    }
}

/// One type in the list: its short name, a mark when it has findings, and its member count.
struct TypeRowView: View {
    /// The type the row shows, named as it reads under its parent.
    var node: Graph.Node
    /// The arranged interface the row reads the type's short name, findings, and members from.
    var atlas: Atlas

    var body: some View {
        let group = atlas.group(node.id)
        HStack(spacing: 6) {
            Text(atlas.shortLabel(node))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            if group.findingCount > 0 {
                Circle().fill(Palette.danger).frame(width: 6, height: 6)
                    .help("\(group.findingCount) findings")
            }
            Spacer(minLength: 4)
            Text("\(group.members.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

/// A list row's hover: a subtle highlight while the pointer is on the row, and the preview itself. The
/// map's previews do not light the list, which follows only what is done in it.
struct RowHover {
    @Environment(Workspace.self) private var workspace
    @State private var isHovered = false
    /// What the row stands for, which hovering previews.
    var target: Workspace.Selection
}

extension RowHover: ViewModifier {
    func body(content: Content) -> some View {
        let lit = isHovered
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
            .contextMenu {
                Button("Open in New Tab") { workspace.openInNewTab(target) }
            }
    }
}

/// The list's filter under it: only the types with findings, or every type.
struct ListFilterView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        if workspace.interface != nil {
            Toggle("Only types with findings", isOn: $workspace.findingsOnly)
                .toggleStyle(.checkbox)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }
}

/// One labeled number in the summary, at the detail pane's text size there and the system's in the list.
struct StatView: View {
    /// The name of the number, shown in uppercase above it.
    var title: String
    /// The number as text, which may be a count or a fraction such as 40/52.
    var value: String
    /// The color of the number: primary, or for the findings count ``Palette/ok`` when there are none and
    /// ``Palette/danger`` otherwise.
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .textSize(9.5, weight: .semibold)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .textStyle(.body, design: .monospaced, weight: .medium)
                .foregroundStyle(tint)
        }
    }
}

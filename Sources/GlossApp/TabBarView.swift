import SwiftUI
import UniformTypeIdentifiers

/// The tabs over the details and the map, drawn as Xcode draws its editor's: one per place, sharing the
/// bar's width, the current one on the page's own ground, each closing from a button that shows on
/// hover, and dragged to reorder. Past a few dozen tabs the bar scrolls.
struct TabBarView: View {
    @Environment(Workspace.self) private var workspace
    @State private var dragging: Workspace.Tab.ID?

    /// The narrowest a tab gets before the bar scrolls instead.
    private static let minimumWidth: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            let width = max(Self.minimumWidth, proxy.size.width / CGFloat(max(workspace.tabs.count, 1)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.tabs) { tab in
                        TabBarItemView(tab: tab)
                            .frame(width: width)
                            .onDrag {
                                dragging = tab.id
                                return NSItemProvider(object: tab.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TabDropDelegate(target: tab.id, workspace: workspace, dragging: $dragging))
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: .leading)
            }
        }
        .frame(height: 28)
        .background(Palette.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1) }
    }
}

/// One tab: its module's color and its title, lit while current, with a close button on hover.
struct TabBarItemView: View {
    @Environment(Workspace.self) private var workspace
    @State private var isHovered = false
    /// The tab the item shows and brings forward when clicked.
    var tab: Workspace.Tab

    var body: some View {
        let isCurrent = tab.id == workspace.currentTabID
        let title = workspace.title(of: tab)
        ZStack {
            HStack(spacing: 6) {
                if let module = workspace.module(of: tab) { ModuleDotView(module: module) }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout.weight(isCurrent ? .medium : .regular))
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .padding(.horizontal, 26)
            if isHovered, workspace.tabs.count > 1 {
                Button { workspace.closeTab(tab.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Close Tab (⌘W)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isCurrent ? Color(nsColor: .textBackgroundColor) : Color.primary.opacity(isHovered ? 0.04 : 0))
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.line.opacity(0.6)).frame(width: 1) }
        // The current tab opens onto the page below it, so only the others keep the bar's bottom line.
        .overlay(alignment: .bottom) {
            if isCurrent { Rectangle().fill(Color(nsColor: .textBackgroundColor)).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(tab.id) }
        .onHover { isHovered = $0 }
        .help(title)
    }
}

/// Moves the dragged tab into a tab's place as the drag passes over it.
struct TabDropDelegate: DropDelegate {
    /// The tab the drag is over.
    let target: Workspace.Tab.ID
    /// The workspace whose tabs move.
    let workspace: Workspace
    /// The tab being dragged, cleared when the drop lands.
    @Binding var dragging: Workspace.Tab.ID?

    /// Moves the dragged tab into the place of the tab the drag has just entered.
    ///
    /// - Parameter info: The drag, unused; the dragged tab is the one ``dragging`` names.
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeOut(duration: 0.15)) { workspace.moveTab(dragging, to: target) }
    }

    /// Shows the drag as a move rather than a copy.
    ///
    /// - Parameter info: The drag, unused.
    /// - Returns: A move.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Ends the drag; the tab has already moved while it passed over the others.
    ///
    /// - Parameter info: The drag, unused.
    /// - Returns: `true`, since the drop always lands.
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

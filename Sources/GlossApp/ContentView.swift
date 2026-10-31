import GlossCore
import SwiftUI

/// The three panes, List | Detail | Map, with the controls that apply to all of them in the toolbar.
struct ContentView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if workspace.atlas != nil {
                NavigationSplitView {
                    ListPane()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
                } content: {
                    DetailPane()
                        .navigationSplitViewColumnWidth(min: 320, ideal: 440, max: 760)
                } detail: {
                    MapPane()
                }
            } else {
                EmptyState()
            }
        }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Access", selection: $workspace.minimumRank) {
                    Text("Public").tag(3)
                    Text("Internal").tag(1)
                    Text("All").tag(0)
                }
                .pickerStyle(.segmented)
                .help("Show declarations at least this visible")
                ControlGroup {
                    Button { workspace.zoom(to: workspace.zoomOutTarget) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                        .disabled(workspace.zoomOutTarget == nil)
                        .help("Zoom out to the wider level (⌘-)")
                    Button { workspace.zoom(to: workspace.zoomInTarget) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                        .disabled(workspace.zoomInTarget == nil)
                        .help("Zoom in, down to the selected type and its neighbors (⌘=)")
                }
                Toggle(isOn: $workspace.includeBody) { Label("Bodies", systemImage: "curlybraces") }
                    .help("Include dependencies used only inside bodies (⌘B)")
                Button { workspace.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .help("Read the sources again (⌘R)")
                    .disabled(workspace.root == nil || workspace.isLoading)
            }
        }
    }
}

/// What the window shows before a package is open, while it is read, or when it cannot be.
struct EmptyState: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        if workspace.isLoading {
            ProgressView("Reading \(workspace.name)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("No package open", systemImage: "shippingbox")
            } description: {
                Text(workspace.problem ?? "Open a folder of Swift sources. gloss reads its Sources folder when it has one.")
            } actions: {
                Button("Open Folder…") { workspace.chooseFolder() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

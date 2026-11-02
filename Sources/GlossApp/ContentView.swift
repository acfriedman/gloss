import GlossCore
import SwiftUI

/// The three panes, List | Detail | Map, the details and the map under a bar of tabs as Xcode's editor
/// is, with the controls that apply to all of them in the toolbar.
struct ContentView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if workspace.atlas != nil {
                NavigationSplitView(columnVisibility: $workspace.columns) {
                    ListPaneView()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
                } detail: {
                    VStack(spacing: 0) {
                        TabBarView()
                        EditorSplitView()
                    }
                }
            } else {
                EmptyStateView()
            }
        }
        .overlay {
            // The field sits a little above the middle and results grow down from it, so the panel
            // reads as centered without jumping as the results change.
            if workspace.isQuickOpenShown {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { workspace.isQuickOpenShown = false }
                        QuickOpenView()
                            .padding(.top, max(48, proxy.size.height * 0.3))
                    }
                }
            }
        }
        .tint(Palette.accent)
        .task { workspace.start() }
        // The welcome window hands over to this one, so it closes once this one is up.
        .onAppear {
            workspace.isMainWindowShown = true
            dismissWindow(id: "welcome")
        }
        .onDisappear { workspace.isMainWindowShown = false }
        .navigationTitle(workspace.name)
        .navigationSubtitle(workspace.subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { workspace.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!workspace.canGoBack)
                        .help("Go back to the previous place (⌘←)")
                    Button { workspace.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!workspace.canGoForward)
                        .help("Go forward again (⌘→)")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(selection: $workspace.comparison) {
                    Text("No Comparison").tag(Workspace.Comparison.off)
                    if let branch = workspace.defaultBranch {
                        Text("Since \(branch)").tag(Workspace.Comparison.branch(branch))
                    }
                    Text("Since Last Commit").tag(Workspace.Comparison.lastCommit)
                    if case .revision(let revision) = workspace.comparison {
                        Text("Since \(revision)").tag(Workspace.Comparison.revision(revision))
                    }
                } label: {
                    Label("Changes", systemImage: "plusminus")
                }
                .pickerStyle(.menu)
                .help(workspace.comparisonProblem ?? "Mark what changed since a base: where this branch left \(workspace.defaultBranch ?? "main"), or the last commit")
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
                Button { workspace.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .help("Read the sources again (⌘R)")
                    .disabled(workspace.root == nil || workspace.isLoading)
            }
        }
    }
}

/// The details beside the map, under the tabs: the details as wide as the reader last dragged the line
/// between them, 440 points at first, and the map taking the rest.
struct EditorSplitView: View {
    @AppStorage("detailWidth") private var width = 440.0
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 0) {
            DetailPaneView()
                .frame(width: width)
            Rectangle()
                .fill(Palette.line.opacity(0.6))
                .frame(width: 1)
                .overlay {
                    Color.clear
                        .frame(width: 9)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { drag in
                                    let start = dragStart ?? width
                                    dragStart = start
                                    width = min(760, max(320, start + drag.translation.width))
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
            MapPaneView()
                .frame(minWidth: 320, maxWidth: .infinity)
        }
    }
}

/// What the window shows before a package is open, while it is read, or when it cannot be.
struct EmptyStateView: View {
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

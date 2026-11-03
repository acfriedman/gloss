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
                    if workspace.isBlank {
                        BlankPageView()
                    } else {
                        VStack(spacing: 0) {
                            TabBarView()
                            EditorSplitView()
                        }
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
        .sheet(isPresented: $workspace.isCompareShown) {
            CompareSheetView()
                .environment(workspace)
        }
        .task { workspace.start() }
        // The welcome window hands over to this one, so it closes once this one is up.
        .onAppear {
            workspace.isMainWindowShown = true
            dismissWindow(id: "welcome")
        }
        .onDisappear { workspace.isMainWindowShown = false }
        .background(WindowReader { workspace.mainWindow = $0 })
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
                ComparisonMenuView()
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

/// The editor with nothing open, as Xcode shows it: no tabs, and how to open a type.
struct BlankPageView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        VStack(spacing: 14) {
            Text("No Editor")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tertiary)
            Button { workspace.isQuickOpenShown = true } label: {
                HStack(spacing: 8) {
                    Text("Open Quickly")
                    HStack(spacing: 2) {
                        ForEach(["⇧", "⌘", "O"], id: \.self) { key in
                            Text(key)
                                .font(.system(.callout, design: .rounded).weight(.medium))
                                .frame(minWidth: 20, minHeight: 20)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
                        }
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Find a type by name")
            Text("or pick a type in the list")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Hands over the window a view is in, once it is in one.
struct WindowReader: NSViewRepresentable {
    /// What to do with the window.
    var found: (NSWindow) -> Void

    /// Makes the view that reads its window.
    ///
    /// - Parameter context: The representable's context, unused.
    /// - Returns: A view that calls back once it is in a window.
    func makeNSView(context: Context) -> NSView {
        Reader(found: found)
    }

    /// Does nothing; the view calls back on its own when its window changes.
    ///
    /// - Parameters:
    ///   - nsView: The view.
    ///   - context: The representable's context, unused.
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Calls back with the window it lands in.
    final class Reader: NSView {
        private let found: (NSWindow) -> Void

        /// Makes a view that calls back with its window.
        ///
        /// - Parameter found: What to do with the window.
        init(found: @escaping (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
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

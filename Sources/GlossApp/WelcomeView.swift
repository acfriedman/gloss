import AppKit
import SwiftUI

/// The window gloss opens on, as Xcode opens on its welcome window: what gloss is and how to open a
/// folder on the left, the folders opened most recently on the right, and whether to show it at launch.
///
/// Opening a folder from it, by dropping one onto it, or from the File menu while it is in front hands
/// over to the main window, which closes it on appearing. A launch that goes straight to a folder hides
/// it before it is seen and hands over at once.
struct WelcomeView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Workspace.showsWelcomeKey) private var showsAtLaunch = true
    @State private var isDropTargeted = false

    var body: some View {
        // The window's size is the content's and the hidden title bar's together, so the content is
        // 28 points short of the 460 the window is, and only the grounds reach up behind the close button.
        HStack(spacing: 0) {
            intro
                .frame(width: 500)
                .background(Palette.surface.ignoresSafeArea())
            Rectangle()
                .fill(Palette.line.opacity(0.6))
                .frame(width: 1)
                .ignoresSafeArea()
            RecentFoldersView()
                .frame(width: 300)
                .background(Palette.panel.ignoresSafeArea())
        }
        .frame(height: 432)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Palette.accent, lineWidth: 3)
                    .ignoresSafeArea()
            }
        }
        .tint(Palette.accent)
        .background(WelcomeWindowStyle(hidden: workspace.launchFolder != nil))
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.lazy.compactMap(Self.folder(for:)).first else { return false }
            workspace.open(folder)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear {
            if workspace.launchFolder != nil { openWindow(id: "main") } else { workspace.snapshotWelcomeIfAsked() }
        }
        .onChange(of: workspace.opens) {
            openWindow(id: "main")
            if workspace.isMainWindowShown { dismissWindow(id: "welcome") }
        }
    }

    /// The mark, the name, what gloss reads, and the ways to open a folder, over the launch checkbox.
    private var intro: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            GlossMarkView()
                .frame(width: 112, height: 112)
            Text("gloss")
                .font(.system(size: 36, weight: .semibold))
                .padding(.top, 16)
            Text("A Swift package's interface, and what holds it together")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Spacer(minLength: 32)
            VStack(spacing: 10) {
                WelcomeActionView(title: "Open Folder…", detail: "A Swift package, or a folder of sources",
                                  systemImage: "folder", shortcut: "⌘O") { workspace.chooseFolder() }
                Text("or drop a folder onto this window")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 56)
            Spacer(minLength: 32)
            Toggle("Show this window when gloss opens", isOn: $showsAtLaunch)
                .toggleStyle(.checkbox)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
    }

    /// The folder to open for something dropped: a folder itself, or the package a `Package.swift` makes.
    ///
    /// - Parameter url: A dropped file URL.
    /// - Returns: The folder, or `nil` for any other file.
    private static func folder(for url: URL) -> URL? {
        if Workspace.isFolder(url) { return url }
        return url.lastPathComponent == "Package.swift" ? url.deletingLastPathComponent() : nil
    }
}

/// One way to open something, drawn as Xcode draws the welcome window's: a wide button with its symbol,
/// its title over what it opens, and its shortcut, lit under the pointer.
struct WelcomeActionView: View {
    /// What the action does, ending in an ellipsis when it asks for more.
    var title: String
    /// What it opens, under the title.
    var detail: String
    /// The SF Symbol beside the title.
    var systemImage: String
    /// The menu shortcut that does the same, shown at the trailing edge.
    var shortcut: String
    /// What a click does.
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isHovered ? 0.09 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The folders opened most recently, newest first, the newest chosen so Return opens it: each opens
/// with a double click or Return, and shows in Finder or leaves the list from its menu.
struct RecentFoldersView: View {
    @Environment(Workspace.self) private var workspace
    @State private var chosen: URL?
    @FocusState private var isFocused: Bool

    var body: some View {
        if workspace.recentFolders.isEmpty {
            Text("No Recent Folders")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(workspace.recentFolders, id: \.self, selection: $chosen) { url in
                RecentFolderRowView(url: url)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .contextMenu(forSelectionType: URL.self) { urls in
                if let url = urls.first {
                    Button("Open") { workspace.open(url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Divider()
                    Button("Remove from Recents") { workspace.forget(url) }
                }
            } primaryAction: { urls in
                if let url = urls.first { workspace.open(url) }
            }
            .padding(.top, 12)
            .onAppear {
                chosen = workspace.recentFolders.first
                isFocused = true
            }
        }
    }
}

/// One recent folder: a package's box or a plain folder, its name, and where it is.
struct RecentFolderRowView: View {
    /// The folder.
    var url: URL

    var body: some View {
        let isPackage = FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
        HStack(spacing: 10) {
            Image(systemName: isPackage ? "shippingbox" : "folder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.accentSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .help(url.path)
    }
}

/// The mark the welcome window wears: a small map, two types under the one they lead to, the trail
/// from one of them lit.
struct GlossMarkView: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 112
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
            }
            func edge(from start: CGPoint, to end: CGPoint, color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: start.x * scale, y: start.y * scale))
                path.addCurve(to: CGPoint(x: end.x * scale, y: end.y * scale),
                              control1: CGPoint(x: start.x * scale, y: (start.y + end.y) / 2 * scale),
                              control2: CGPoint(x: end.x * scale, y: (start.y + end.y) / 2 * scale))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
            }
            func box(_ frame: CGRect, fill: Color, ink: Color) {
                let shape = Path(roundedRect: frame, cornerRadius: 5 * scale)
                context.fill(shape, with: .color(fill))
                context.stroke(shape, with: .color(ink), lineWidth: 1.5 * scale)
                let label = CGRect(x: frame.minX + 7 * scale, y: frame.midY - 2 * scale, width: frame.width * 0.5, height: 4 * scale)
                context.fill(Path(roundedRect: label, cornerRadius: 2 * scale), with: .color(ink.opacity(0.7)))
            }
            edge(from: CGPoint(x: 34, y: 72), to: CGPoint(x: 48, y: 42), color: Palette.accent)
            edge(from: CGPoint(x: 78, y: 72), to: CGPoint(x: 64, y: 42), color: Palette.edge.opacity(0.7))
            box(rect(30, 20, 52, 22), fill: Palette.accentSoft, ink: Palette.accent)
            box(rect(12, 72, 44, 22), fill: Palette.moduleTint(1), ink: Palette.moduleInk(1))
            box(rect(58, 72, 44, 22), fill: Palette.moduleTint(2), ink: Palette.moduleInk(2))
        }
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.background)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Palette.line.opacity(0.5)))
    }
}

/// Shapes the welcome view's window as Xcode shapes its own: no title bar, only the close button, moved
/// by dragging anywhere, and left out of full screen and window restoration.
private struct WelcomeWindowStyle: NSViewRepresentable {
    /// Whether the window is hidden from the start, for a launch that goes straight to a folder.
    var hidden: Bool

    func makeNSView(context: Context) -> NSView {
        WindowReader(hidesWindow: hidden)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Styles the window it lands in.
    final class WindowReader: NSView {
        private let hidesWindow: Bool

        /// Makes a view that styles the window it lands in.
        ///
        /// - Parameter hidesWindow: Whether to hide the window at once.
        init(hidesWindow: Bool) {
            self.hidesWindow = hidesWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.isRestorable = false
            window.collectionBehavior.insert(.fullScreenNone)
            if hidesWindow { window.alphaValue = 0 }
        }
    }
}

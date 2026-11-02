import AppKit
import GlossCore
import SwiftUI

/// The gloss window: every type listed on the left, the text of one type in the middle, and the
/// dependency map on the right.
///
/// It opens on a welcome window that lists the folders opened most recently, as Xcode does; with that
/// turned off, it reopens the last folder. `swift run GlossApp --root <folder>` opens a folder
/// straight away. The folder takes a flag because AppKit reads a bare path argument as a document to
/// open, and then opens no window.
@main
struct GlossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var workspace = Workspace(arguments: CommandLine.arguments)

    /// Makes a process started from the command line a regular app before any scene opens, so it gets
    /// a window, a Dock icon, and a menu bar.
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        // The welcome window comes first, so it is the one a launch opens.
        Window("Welcome to gloss", id: "welcome") {
            WelcomeView()
                .environment(workspace)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("1", modifiers: [.command, .shift])
        Window("gloss", id: "main") {
            ContentView()
                .environment(workspace)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { workspace.chooseFolder() }
                    .keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(workspace.recentFolders, id: \.self) { url in
                        Button(url.lastPathComponent) { workspace.open(url) }
                    }
                    Divider()
                    Button("Clear Menu") { workspace.clearRecentFolders() }
                        .disabled(workspace.recentFolders.isEmpty)
                }
                Button("Open Quickly…") { workspace.isQuickOpenShown = true }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(workspace.atlas == nil)
                Divider()
                Button("New Tab") { workspace.newTab() }
                    .keyboardShortcut("t")
                    .disabled(workspace.atlas == nil)
                // With one tab left, Close Tab steps aside and Command-W closes the window, as in Xcode.
                Button("Close Tab") { workspace.closeTab(workspace.currentTabID) }
                    .keyboardShortcut("w")
                    .disabled(workspace.tabs.count < 2)
                Divider()
                Button("Reload") { workspace.reload() }
                    .keyboardShortcut("r")
                    .disabled(workspace.root == nil)
            }
            CommandGroup(after: .toolbar) {
                Button(workspace.showsList ? "Hide List" : "Show List") { workspace.toggleList() }
                    .keyboardShortcut("1")
                Divider()
                Button("Zoom In") { workspace.zoom(to: workspace.zoomInTarget) }
                    .keyboardShortcut("=")
                    .disabled(workspace.zoomInTarget == nil)
                Button("Zoom Out") { workspace.zoom(to: workspace.zoomOutTarget) }
                    .keyboardShortcut("-")
                    .disabled(workspace.zoomOutTarget == nil)
                Divider()
            }
            CommandMenu("Navigate") {
                Button("Back") { travel(workspace.goBack, orMoveBy: #selector(NSResponder.moveToBeginningOfLine(_:))) }
                    .keyboardShortcut(.leftArrow)
                    .disabled(!workspace.canGoBack)
                Button("Forward") { travel(workspace.goForward, orMoveBy: #selector(NSResponder.moveToEndOfLine(_:))) }
                    .keyboardShortcut(.rightArrow)
                    .disabled(!workspace.canGoForward)
                Divider()
                Button("Show Previous Tab") { workspace.showTab(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(workspace.tabs.count < 2)
                Button("Show Next Tab") { workspace.showTab(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(workspace.tabs.count < 2)
            }
        }
    }

    /// Goes back or forward, unless a text field is being edited, where the arrow keeps moving the
    /// cursor to the start or end of the line as it would without the menu.
    ///
    /// - Parameters:
    ///   - step: Going back or forward.
    ///   - selector: The cursor move the field makes instead.
    private func travel(_ step: () -> Void, orMoveBy selector: Selector) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
            NSApp.sendAction(selector, to: editor, from: nil)
        } else {
            step()
        }
    }
}

/// Brings a process started from the command line to the front, and quits with its last window.
final class AppDelegate: NSObject {}

extension AppDelegate: NSApplicationDelegate {
    // The window's own tabs are gloss's tab bar, so the system's window tabs and their menu items stay off.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        MainThreadWatch.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

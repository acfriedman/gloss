import AppKit

/// Writes the window to a PNG and quits, so the app can be reviewed from a script without screen access.
///
/// Set `GLOSS_SNAPSHOT` to the output path. `GLOSS_SELECT` names what to select first: a node id such
/// as `GlossCore/Linter`, `module:Name`, or `changes`, or several to select in turn, joined by commas,
/// such as `changes,GlossMap/Atlas`. `GLOSS_ZOOM` is how many times to zoom in after that, and
/// `GLOSS_PREVIEW` names a node to preview as if the pointer rested on it. `GLOSS_COMPARE` compares
/// with a base from where the head left it, `develop`, or names the head too, `develop..feature`, and
/// it is read before anything is selected. Without `--root`, the
/// snapshot is of the welcome window. A snapshot run leaves the folders the next launch lists alone.
extension Workspace {
    /// Whether a snapshot was started, so a second read of the folder starts no second one.
    private static var isSnapshotUnderWay = false

    /// Whether this run only takes a snapshot, and so must not change what the reader's next launch opens.
    static var isSnapshotting: Bool {
        ProcessInfo.processInfo.environment["GLOSS_SNAPSHOT"] != nil
    }

    /// Takes the snapshot the environment asks for, once the interface and any comparison are read;
    /// does nothing otherwise, or when one is under way: a head read from git reads the folder again.
    func snapshotIfAsked() {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["GLOSS_SNAPSHOT"], !Self.isSnapshotUnderWay else { return }
        Self.isSnapshotUnderWay = true
        Task {
            if let asked = environment["GLOSS_COMPARE"] {
                let ends = asked.components(separatedBy: "..")
                _ = compare(base: ends[0], asItIs: false, head: ends.count > 1 ? ends[1] : nil)
            }
            // The comparison is read after the sources, and the changes level draws nothing until it is,
            // so a type selected there before would move to a level of its own.
            var waited = 0
            while isLoading || (comparison != .off && diff == nil && comparisonProblem == nil), waited < 150 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            // The map draws off the main thread, and where a selection lands can depend on the drawing.
            @MainActor func settle() async {
                while isDrawing { try? await Task.sleep(for: .milliseconds(20)) }
            }
            await settle()
            for target in (environment["GLOSS_SELECT"] ?? "").split(separator: ",").map(String.init) {
                select(target == "changes" ? .changes : target.hasPrefix("module:") ? .module(String(target.dropFirst("module:".count))) : .type(target))
                await settle()
            }
            for _ in 0..<(Int(environment["GLOSS_ZOOM"] ?? "") ?? 0) {
                zoom(to: zoomInTarget)
                await settle()
            }
            if let target = environment["GLOSS_PREVIEW"] { hoverBegan(.type(target)) }
            Self.capture(to: output, after: .seconds(2))
        }
    }

    /// Takes the snapshot the environment asks for of the welcome window, when the launch shows it;
    /// does nothing otherwise.
    func snapshotWelcomeIfAsked() {
        guard let output = ProcessInfo.processInfo.environment["GLOSS_SNAPSHOT"] else { return }
        Self.capture(to: output, after: .seconds(1))
    }

    /// Writes the window on screen to a PNG once it has settled, and quits.
    ///
    /// - Parameters:
    ///   - output: The PNG's path.
    ///   - delay: How long to let the window draw first.
    private static func capture(to output: String, after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            // A sheet up is what the reader sees, so it is the one taken.
            let window = NSApp.windows.first(where: \.isVisible)
            guard let view = (window?.attachedSheet ?? window)?.contentView?.superview,
                  let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            NSApp.terminate(nil)
        }
    }
}

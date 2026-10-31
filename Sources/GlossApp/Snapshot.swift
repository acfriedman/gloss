import AppKit

/// Writes the window to a PNG and quits, so the app can be reviewed from a script without screen access.
///
/// Set `GLOSS_SNAPSHOT` to the output path. `GLOSS_SELECT` names what to select first: a node id such
/// as `GlossCore/Linter`, or `module:Name`. `GLOSS_ZOOM` is how many times to zoom in after that, and
/// `GLOSS_PREVIEW` names a node to preview as if the pointer rested on it.
extension Workspace {
    /// Takes the snapshot the environment asks for, once the interface is read; does nothing otherwise.
    func snapshotIfAsked() {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["GLOSS_SNAPSHOT"] else { return }
        if let target = environment["GLOSS_SELECT"] {
            select(target.hasPrefix("module:") ? .module(String(target.dropFirst("module:".count))) : .type(target))
        }
        for _ in 0..<(Int(environment["GLOSS_ZOOM"] ?? "") ?? 0) { zoom(to: zoomInTarget) }
        if let target = environment["GLOSS_PREVIEW"] { hoverBegan(.type(target)) }
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
                  let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            NSApp.terminate(nil)
        }
    }
}

import Foundation

/// Finds the Swift sources under a path the way every gloss front end does.
public enum SourceFiles {
    /// A path that does not exist, so a typo cannot pass as a clean run.
    public struct Missing: Error, Sendable {
        /// The path that was asked for, exactly as given.
        public var path: String
    }

    /// Collects the `.swift` files under a path, or the path itself when it names one file.
    ///
    /// - Parameters:
    ///   - path: A file or directory.
    ///   - includeTests: `false` skips any directory whose name ends in `Tests`.
    /// - Returns: The files, sorted, so output order is stable across runs; empty for a non-Swift file.
    ///   Each path is `path` joined with the file's path under it.
    /// - Throws: ``Missing`` when nothing exists at `path`.
    ///
    /// `.build` and `.swiftpm` directories are always skipped.
    public static func swiftFiles(under path: String, includeTests: Bool) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { throw Missing(path: path) }
        guard isDirectory.boolValue else { return path.hasSuffix(".swift") ? [path] : [] }
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }
        var files: [String] = []
        for case let relative as String in enumerator {
            if isSkipped(relative, includeTests: includeTests) { enumerator.skipDescendants(); continue }
            if relative.hasSuffix(".swift") { files.append((path as NSString).appendingPathComponent(relative)) }
        }
        return files.sorted()
    }

    /// Whether a path under a scanned directory is left out, it or a directory it is in being a build
    /// directory, or a test directory when tests are not wanted.
    ///
    /// - Parameters:
    ///   - relative: The path under the scanned directory, components joined by `/`.
    ///   - includeTests: `false` leaves out anything in a directory whose name ends in `Tests`.
    /// - Returns: `true` when the path is not scanned.
    public static func isSkipped(_ relative: String, includeTests: Bool) -> Bool {
        let components = relative.split(separator: "/")
        if components.contains(".build") || components.contains(".swiftpm") { return true }
        return !includeTests && components.contains { $0.hasSuffix("Tests") }
    }
}

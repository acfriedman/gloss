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
    /// Hidden folders, such as `.build` and `.swiftpm`, and the folders dependency managers check code out
    /// into, ``dependencyFolders``, are always skipped.
    public static func swiftFiles(under path: String, includeTests: Bool) throws -> [String] {
        let phase = Timing.begin("list files"); defer { Timing.end(phase, path) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { throw Missing(path: path) }
        guard isDirectory.boolValue else { return path.hasSuffix(".swift") ? [path] : [] }
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }
        var files: [String] = []
        for case let relative as String in enumerator {
            if isSkipped(relative, includeTests: includeTests) {
                // Only a folder has descendants to skip; skipping after a file, such as `.DS_Store`, ends the walk.
                if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory { enumerator.skipDescendants() }
                continue
            }
            if relative.hasSuffix(".swift") { files.append((path as NSString).appendingPathComponent(relative)) }
        }
        return files.sorted()
    }

    /// The folders package managers and Xcode check other projects' code out into, which is never the
    /// project's own: Xcode's `SourcePackages` and `DerivedData`, CocoaPods' `Pods`, and `Carthage`.
    public static let dependencyFolders: Set<String> = ["SourcePackages", "DerivedData", "Pods", "Carthage"]

    /// Whether a path under a scanned directory is left out, it or a directory it is in being hidden, a
    /// dependency folder, or a test directory when tests are not wanted.
    ///
    /// - Parameters:
    ///   - relative: The path under the scanned directory, components joined by `/`.
    ///   - includeTests: `false` leaves out anything in a directory whose name ends in `Tests`.
    /// - Returns: `true` when the path is not scanned.
    public static func isSkipped(_ relative: String, includeTests: Bool) -> Bool {
        let components = relative.split(separator: "/")
        if components.contains(where: { $0.hasPrefix(".") || dependencyFolders.contains(String($0)) }) { return true }
        return !includeTests && components.contains { $0.hasSuffix("Tests") }
    }

    /// Names the module a file belongs to by the SwiftPM layout: the directory right under `Sources`
    /// or `Tests`. Outside that layout the file's own directory stands in, which is right for most
    /// Xcode projects and harmless for the rest.
    ///
    /// - Parameter file: The path as given.
    /// - Returns: The module name, or `Module` for a bare file name.
    public static func module(of file: String) -> String {
        let parts = file.split(separator: "/").map(String.init)
        if let root = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }), root + 2 < parts.count {
            return parts[root + 1]
        }
        return parts.count >= 2 ? parts[parts.count - 2] : "Module"
    }
}

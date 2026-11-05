import Foundation

/// Finds the Swift sources under a path the way every gloss front end does.
public enum SourceFiles {
    /// A path that does not exist, so a typo cannot pass as a clean run.
    public struct Missing: Error, Sendable {
        /// The path that was asked for, exactly as given.
        public var path: String
    }

    /// The extensions of the files gloss reads: Swift sources, the Objective-C headers whose types a Swift
    /// doc may link in a project that mixes the two, and the README that is each module's page.
    public static let readExtensions: Set<String> = ["swift", "h", "md"]

    /// Whether a file is one gloss reads among some extensions: one of them, and a Markdown file only when
    /// it is a module's page, so no other README or note is read as one.
    ///
    /// - Parameters:
    ///   - path: A file's path.
    ///   - extensions: The extensions wanted, without their dots.
    /// - Returns: `true` when the file is read.
    public static func reads(_ path: String, extensions: Set<String>) -> Bool {
        let ext = (path as NSString).pathExtension
        return extensions.contains(ext) && (ext != "md" || ModulePage.isPage(path))
    }

    /// Collects the `.swift` files under a path, or the path itself when it names one file.
    ///
    /// - Parameters:
    ///   - path: A file or directory.
    ///   - includeTests: `false` skips any directory whose name ends in `Tests`.
    /// - Returns: The files, sorted, so output order is stable across runs; empty for a non-Swift file.
    ///   Each path is `path` joined with the file's path under it.
    /// - Throws: ``Missing`` when nothing exists at `path`.
    public static func swiftFiles(under path: String, includeTests: Bool) throws -> [String] {
        try files(under: path, includeTests: includeTests, extensions: ["swift"])
    }

    /// Collects the files with some extensions under a path, or the path itself when it names one.
    ///
    /// - Parameters:
    ///   - path: A file or directory.
    ///   - includeTests: `false` skips any directory whose name ends in `Tests`.
    ///   - extensions: The extensions wanted, without their dots, such as ``readExtensions``.
    /// - Returns: The files, sorted, so output order is stable across runs; empty for a file of another
    ///   extension. Each path is `path` joined with the file's path under it.
    /// - Throws: ``Missing`` when nothing exists at `path`.
    ///
    /// Hidden folders, such as `.build` and `.swiftpm`, and the folders dependency managers check code out
    /// into, ``dependencyFolders``, are always skipped.
    public static func files(under path: String, includeTests: Bool, extensions: Set<String>) throws -> [String] {
        let phase = Timing.begin("list files"); defer { Timing.end(phase, path) }
        func wanted(_ file: String) -> Bool { reads(file, extensions: extensions) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { throw Missing(path: path) }
        guard isDirectory.boolValue else { return wanted(path) ? [path] : [] }
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }
        var files: [String] = []
        for case let relative as String in enumerator {
            if isSkipped(relative, includeTests: includeTests) {
                // Only a folder has descendants to skip; skipping after a file, such as `.DS_Store`, ends the walk.
                if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory { enumerator.skipDescendants() }
                continue
            }
            // Judged by its whole path, since a module's page is known by the folders above it.
            let file = (path as NSString).appendingPathComponent(relative)
            if wanted(file) { files.append(file) }
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

import GlossCore
import Foundation

/// Command-line entry: `gloss [--include-tests] [--summary] <path>...`.
///
/// Paths may be files or directories; directories are walked for `.swift` files, skipping `.build`
/// and, unless `--include-tests` is given, any directory whose name ends in `Tests`.
let arguments = Array(CommandLine.arguments.dropFirst())
let includeTests = arguments.contains("--include-tests")
let summaryOnly = arguments.contains("--summary")
let paths = arguments.filter { !$0.hasPrefix("--") }

guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: gloss [--include-tests] [--summary] <path>...\n".utf8))
    exit(64)
}

/// Collects the `.swift` files under a path, or the path itself when it names one file. A path that
/// does not exist exits with status 66, so a typo cannot pass as a clean run.
///
/// - Parameter path: A file or directory, as given on the command line.
/// - Returns: The files, sorted, so output order is stable across runs; empty for a non-Swift file.
func swiftFiles(under path: String) -> [String] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
        FileHandle.standardError.write(Data("gloss: no such path: \(path)\n".utf8))
        exit(66)
    }
    guard isDirectory.boolValue else { return path.hasSuffix(".swift") ? [path] : [] }
    guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [] }
    var files: [String] = []
    for case let relative as String in enumerator {
        let components = relative.split(separator: "/")
        if components.contains(".build") || components.contains(".swiftpm") { enumerator.skipDescendants(); continue }
        if !includeTests, components.contains(where: { $0.hasSuffix("Tests") }) { enumerator.skipDescendants(); continue }
        if relative.hasSuffix(".swift") { files.append((path as NSString).appendingPathComponent(relative)) }
    }
    return files.sorted()
}

var diagnostics: [Diagnostic] = []
var fileCount = 0
for file in paths.flatMap(swiftFiles(under:)) {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
    fileCount += 1
    diagnostics += Checker.check(source: source, file: file)
}

if !summaryOnly {
    for diagnostic in diagnostics { print(diagnostic.rendered) }
}
let byRule = Dictionary(grouping: diagnostics, by: \.rule).mapValues(\.count)
var summary = "\(diagnostics.count) error\(diagnostics.count == 1 ? "" : "s") in \(fileCount) file\(fileCount == 1 ? "" : "s")"
if !byRule.isEmpty {
    summary += "\n" + byRule.sorted { $0.value > $1.value }.map { "  \($0.value)\t\($0.key.rawValue)" }.joined(separator: "\n")
}
FileHandle.standardError.write(Data((summary + "\n").utf8))
exit(diagnostics.isEmpty ? 0 : 1)

import GlossCore
import Foundation

/// Command-line entry: `gloss [--include-tests] [--summary] <path>...` lints;
/// `gloss interface [--include-tests] [--json <file>] [--html <file>] [--title <name>] <path>...` exports.
///
/// Paths may be files or directories; directories are walked for `.swift` files, skipping `.build`
/// and, unless `--include-tests` is given, any directory whose name ends in `Tests`. The interface
/// command writes JSON to standard output when neither `--json` nor `--html` names a file.
var arguments = Array(CommandLine.arguments.dropFirst())
let interfaceMode = arguments.first == "interface"
if interfaceMode { arguments.removeFirst() }
let includeTests = arguments.contains("--include-tests")
let summaryOnly = arguments.contains("--summary")
var options: [String: String] = [:]
var paths: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    index += 1
    guard argument.hasPrefix("--") else { paths.append(argument); continue }
    if interfaceMode, ["--json", "--html", "--title"].contains(argument) {
        guard index < arguments.count else {
            FileHandle.standardError.write(Data("gloss: \(argument) needs a value\n".utf8))
            exit(64)
        }
        options[argument] = arguments[index]
        index += 1
    }
}

guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("""
    usage: gloss [--include-tests] [--summary] <path>...
           gloss interface [--include-tests] [--json <file>] [--html <file>] [--title <name>] <path>...

    """.utf8))
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

let sources: [(file: String, source: String)] = paths.flatMap(swiftFiles(under:)).compactMap { file in
    (try? String(contentsOfFile: file, encoding: .utf8)).map { (file, $0) }
}

if interfaceMode {
    let interface = Interface.build(sources: sources)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let title = options["--title"] ?? (FileManager.default.currentDirectoryPath as NSString).lastPathComponent
    var outputs: [(path: String, data: Data)] = []
    if let path = options["--json"] { outputs.append((path, try encoder.encode(interface))) }
    if let path = options["--html"] { outputs.append((path, Data(InterfacePage.render(interface, title: title).utf8))) }
    if outputs.isEmpty {
        FileHandle.standardOutput.write(try encoder.encode(interface))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    for output in outputs {
        do {
            try output.data.write(to: URL(fileURLWithPath: output.path))
        } catch {
            FileHandle.standardError.write(Data("gloss: cannot write \(output.path): \(error.localizedDescription)\n".utf8))
            exit(73)
        }
    }
    let findings = interface.assessments.reduce(0) { $0 + $1.findings.count }
    FileHandle.standardError.write(Data("\(interface.contracts.count) declarations, \(findings) findings in \(sources.count) files\n".utf8))
    exit(0)
}

var diagnostics: [Diagnostic] = []
for (file, source) in sources {
    diagnostics += Linter.check(source: source, file: file)
}

if !summaryOnly {
    for diagnostic in diagnostics { print(diagnostic.rendered) }
}
let byRule = Dictionary(grouping: diagnostics, by: \.rule).mapValues(\.count)
var summary = "\(diagnostics.count) error\(diagnostics.count == 1 ? "" : "s") in \(sources.count) file\(sources.count == 1 ? "" : "s")"
if !byRule.isEmpty {
    summary += "\n" + byRule.sorted { $0.value > $1.value }.map { "  \($0.value)\t\($0.key.rawValue)" }.joined(separator: "\n")
}
FileHandle.standardError.write(Data((summary + "\n").utf8))
exit(diagnostics.isEmpty ? 0 : 1)

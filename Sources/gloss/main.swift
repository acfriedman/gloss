import GlossRead
import GlossLint
import GlossModel
import GlossMap
import GlossPage
import Foundation

/// Command-line entry: `gloss [--include-tests] [--summary] [--style <file>] [--staged | --since <revision>] <path>...`
/// lints, `--staged` and `--since` judging only the declarations a change added or changed;
/// `gloss interface [--include-tests] [--json <file>] [--html <file>] [--title <name>] <path>...` exports;
/// `gloss bench [--include-tests] [--base <revision>] <path>...` times what the app does with the paths;
/// `gloss story [--include-tests] [--base <revision>] <path>...` checks the branch's story covers its change.
///
/// Paths may be files or directories; directories are walked for `.swift` files, skipping hidden folders,
/// the folders dependency managers check code out into, and, unless `--include-tests` is given, any
/// directory whose name ends in `Tests`. The interface command writes JSON to standard output when neither
/// `--json` nor `--html` names a file. The lint, the
/// export, and the bench follow the project's house style: the file `--style` names, else the nearest
/// `.gloss/style.json` in the current directory or above it, else gloss's own.
var arguments = Array(CommandLine.arguments.dropFirst())
let interfaceMode = arguments.first == "interface"
let benchMode = arguments.first == "bench"
let storyMode = arguments.first == "story"
if interfaceMode || benchMode || storyMode { arguments.removeFirst() }
let includeTests = arguments.contains("--include-tests")
let summaryOnly = arguments.contains("--summary")
let lintMode = !interfaceMode && !benchMode && !storyMode
let staged = lintMode && arguments.contains("--staged")
var options: [String: String] = [:]
var paths: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    index += 1
    guard argument.hasPrefix("--") else { paths.append(argument); continue }
    if (interfaceMode && ["--json", "--html", "--title"].contains(argument)) || ((benchMode || storyMode) && argument == "--base")
        || (!storyMode && argument == "--style") || (lintMode && argument == "--since") {
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
    usage: gloss [--include-tests] [--summary] [--style <file>] [--staged | --since <revision>] <path>...
           gloss interface [--include-tests] [--style <file>] [--json <file>] [--html <file>] [--title <name>] <path>...
           gloss bench [--include-tests] [--style <file>] [--base <revision>] <path>...
           gloss story [--include-tests] [--base <revision>] <path>...

    """.utf8))
    exit(64)
}

/// The project's house style, which a broken file stops the run over rather than linting by another.
let style: HouseStyle = {
    do {
        return try options["--style"].map { try HouseStyle.load($0) } ?? HouseStyle.find(from: FileManager.default.currentDirectoryPath)
    } catch {
        FileHandle.standardError.write(Data("gloss: \(error)\n".utf8))
        exit(65)
    }
}()

/// Collects the `.swift` files under a path, and the Objective-C headers whose types their docs may link.
/// A path that does not exist exits with status 66, so a typo cannot pass as a clean run.
///
/// - Parameter path: A file or directory, as given on the command line.
/// - Returns: The files, sorted, so output order is stable across runs; empty for a file gloss does not read.
func sourceFiles(under path: String) -> [String] {
    do {
        return try SourceFiles.files(under: path, includeTests: includeTests, extensions: SourceFiles.readExtensions)
    } catch {
        FileHandle.standardError.write(Data("gloss: no such path: \(path)\n".utf8))
        exit(66)
    }
}

let (sources, readSamples) = Timing.record {
    Timing.measure("read files") {
        paths.flatMap(sourceFiles(under:)).compactMap { file -> (file: String, source: String)? in
            (try? String(contentsOfFile: file, encoding: .utf8)).map { (file, $0) }
        }
    }
}

if storyMode {
    exit(StoryCheck.run(sources: sources, base: options["--base"] ?? "main", in: paths[0], includeTests: includeTests))
}

if benchMode {
    let samples = readSamples + Bench.run(sources: sources, style: style, base: options["--base"], in: paths[0], includeTests: includeTests)
    print(Bench.table(samples))
    exit(0)
}

if interfaceMode {
    let reading = Reading(sources: sources)
    let interface = Interface.build(reading)
    let assessments = Linter.assess(reading, style: style)
    let export = Export(interface, assessments: assessments)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let title = options["--title"] ?? (FileManager.default.currentDirectoryPath as NSString).lastPathComponent
    var outputs: [(path: String, data: Data)] = []
    if let path = options["--json"] { outputs.append((path, try encoder.encode(export))) }
    if let path = options["--html"] {
        outputs.append((path, Data(InterfacePage.render(interface, assessments: assessments, title: title).utf8)))
    }
    if outputs.isEmpty {
        FileHandle.standardOutput.write(try encoder.encode(export))
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
    let findings = assessments.reduce(0) { $0 + $1.findings.count }
    FileHandle.standardError.write(Data("\(interface.contracts.count) declarations, \(findings) findings in \(interface.files.count) files\n".utf8))
    exit(0)
}

// A change's lint judges only what it touched; without one, the whole of every path is judged.
let changed: ChangeLint.Result?
if staged || options["--since"] != nil {
    do {
        changed = try ChangeLint.run(paths: paths, since: options["--since"], workingTree: sources, style: style, includeTests: includeTests)
    } catch {
        // What git said reads better than the error's own description.
        FileHandle.standardError.write(Data("gloss: \((error as? Revision.Failure)?.message ?? "\(error)")\n".utf8))
        exit(65)
    }
} else {
    changed = nil
}
let diagnostics = changed?.diagnostics ?? Linter.check(sources: sources, style: style)

if !summaryOnly {
    for diagnostic in diagnostics { print(diagnostic.rendered) }
}
let byRule = Dictionary(grouping: diagnostics, by: \.rule).mapValues(\.count)
let errors = diagnostics.filter { $0.severity == .error }.count
// Headers and module pages are read for their names and prose, so the files counted are the Swift ones.
let swiftCount = sources.filter { $0.file.hasSuffix(".swift") }.count
let warnings = diagnostics.count - errors
let judged = changed.map { "\($0.declarations) changed declaration\($0.declarations == 1 ? "" : "s")" }
    ?? "\(swiftCount) file\(swiftCount == 1 ? "" : "s")"
var summary = "\(errors) error\(errors == 1 ? "" : "s")" + (warnings > 0 ? " and \(warnings) warning\(warnings == 1 ? "" : "s")" : "")
    + " in " + judged
if !byRule.isEmpty {
    summary += "\n" + byRule.sorted { $0.value > $1.value }.map { "  \($0.value)\t\($0.key.rawValue)" }.joined(separator: "\n")
}
FileHandle.standardError.write(Data((summary + "\n").utf8))
// Only errors fail the run, so a style can bring a rule in as a warning before it gates anything.
exit(errors == 0 ? 0 : 1)

import LucidRead
import LucidLint
import GlossModel
import GlossMap
import GlossPage
import Foundation

/// Command-line entry: `gloss interface [--include-tests] [--json <file>] [--html <file>] [--title <name>] <path>...`
/// exports; `gloss bench [--include-tests] [--base <revision>] <path>...` times what the app does with the paths;
/// `gloss story [--include-tests] [--base <revision>] <path>...` checks the branch's story covers its change.
/// The lint is SwiftLucid's own command, `swiftlucid`.
///
/// Paths may be files or directories; directories are walked for `.swift` files, skipping hidden folders,
/// the folders dependency managers check code out into, and, unless `--include-tests` is given, any
/// directory whose name ends in `Tests`. The interface command writes JSON to standard output when neither
/// `--json` nor `--html` names a file. The export and the bench show the lint's findings by the project's
/// house style: the file `--style` names, else the nearest `.swiftlucid.json` in the current directory or
/// above it, else SwiftLucid's own.
var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? ""
let interfaceMode = command == "interface"
let benchMode = command == "bench"
let storyMode = command == "story"
let usage = """
usage: gloss interface [--include-tests] [--style <file>] [--json <file>] [--html <file>] [--title <name>] <path>...
       gloss bench [--include-tests] [--style <file>] [--base <revision>] <path>...
       gloss story [--include-tests] [--base <revision>] <path>...
To lint, run swiftlucid: https://github.com/acfriedman/SwiftLucid

"""
guard interfaceMode || benchMode || storyMode else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}
arguments.removeFirst()
let includeTests = arguments.contains("--include-tests")
var options: [String: String] = [:]
var paths: [String] = []
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    index += 1
    guard argument.hasPrefix("--") else { paths.append(argument); continue }
    if (interfaceMode && ["--json", "--html", "--title"].contains(argument)) || ((benchMode || storyMode) && argument == "--base")
        || (!storyMode && argument == "--style") {
        guard index < arguments.count else {
            FileHandle.standardError.write(Data("gloss: \(argument) needs a value\n".utf8))
            exit(64)
        }
        options[argument] = arguments[index]
        index += 1
    }
}

guard !paths.isEmpty else {
    FileHandle.standardError.write(Data(usage.utf8))
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

// What is left is the interface export.
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

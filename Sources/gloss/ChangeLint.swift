import Foundation
import GlossRead
import GlossLint
import GlossModel
import GlossMap

/// The lint of what a change touched: `--staged` for a commit hook, judging the next commit against
/// `HEAD`, and `--since <revision>` for a pull request's check, judging the working tree against a base.
///
/// The change's side is read whole, so links into files it did not touch still resolve; only the findings
/// on the declarations it added or changed are reported.
enum ChangeLint {
    /// What a change's lint found and how much it judged.
    struct Result {
        /// The findings on new or changed declarations, file by file, each file's in source order.
        var diagnostics: [Diagnostic]
        /// How many declarations the change added or changed.
        var declarations: Int
    }

    /// Lints what a change touched.
    ///
    /// - Parameters:
    ///   - paths: The directories given on the command line, inside one git work tree.
    ///   - since: The revision to judge the working tree against, or `nil` to judge what is staged against
    ///     `HEAD`.
    ///   - workingTree: The sources as read from disk, which `since` judges.
    ///   - style: The project's house style.
    ///   - includeTests: Whether `*Tests` folders are read too.
    /// - Returns: The findings kept, and how many declarations the change touched.
    /// - Throws: ``GlossRead/Revision/Failure`` when git cannot read the index or the base revision.
    static func run(paths: [String], since: String?, workingTree: [(file: String, source: String)], style: HouseStyle,
                    includeTests: Bool) throws -> Result {
        let current = FileManager.default.currentDirectoryPath
        let head = try since == nil ? paths.flatMap {
            try Revision.stagedSources(under: $0, relativeTo: current, includeTests: includeTests, extensions: SourceFiles.readExtensions)
        } : workingTree
        // A first commit has no HEAD to judge against, so everything it stages is new.
        let hasBase = since != nil || (try? Revision.commit("HEAD", in: paths[0])) != nil
        let base = try hasBase ? paths.flatMap {
            try Revision.sources(at: since ?? "HEAD", under: $0, relativeTo: current, includeTests: includeTests, extensions: ["swift"])
        } : []
        let reading = Reading(sources: head)
        let changed = ChangedFindings(InterfaceDiff(base: Interface.build(sources: base), head: Interface.build(reading)))
        return Result(diagnostics: changed.filter(Linter.check(reading, style: style)), declarations: changed.count)
    }
}

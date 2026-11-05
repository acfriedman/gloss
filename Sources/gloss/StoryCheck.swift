import GlossRead
import GlossModel
import Foundation

/// What `gloss story` checks: that the branch's story, at `.gloss/changes/<branch>.md`, explains every
/// type whose interface changed since where the branch left its base, each in a note of its own as well
/// as a theme, and that its links name something, so a pull request can be held to saying why as its declarations are held to saying what.
enum StoryCheck {
    /// Reads the branch's story and its change, prints what the story covers and leaves out, and says
    /// whether it is complete.
    ///
    /// - Parameters:
    ///   - sources: Each file's path and its text, now.
    ///   - base: The branch the change is to go into, compared from where this branch left it.
    ///   - directory: A directory inside the repository.
    ///   - includeTests: Whether the base's test directories are read too, as the sources' were.
    /// - Returns: The exit status: 0 for a complete story, 1 for a story with gaps or none, 2 when git
    ///   cannot say.
    static func run(sources: [(file: String, source: String)], base: String, in directory: String, includeTests: Bool) -> Int32 {
        do {
            let commit = try Revision.mergeBase(of: "HEAD", and: base, in: directory)
            let before = Interface.build(sources: try Revision.sources(at: commit, under: directory,
                                                                       relativeTo: FileManager.default.currentDirectoryPath, includeTests: includeTests))
            let head = Interface.build(sources: sources)
            let diff = InterfaceDiff(base: before, head: head)
            guard let branch = try Revision.currentBranch(in: directory) else {
                FileHandle.standardError.write(Data("gloss: no branch is checked out, so there is no story to read\n".utf8))
                return 2
            }
            let path = ChangeStory.path(forBranch: branch)
            let file = URL(fileURLWithPath: try Revision.top(of: directory)).appendingPathComponent(path)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                print("No story at \(path). \(diff.nodes.filter { $0.change != .implementation }.count) types changed since \(base) need one.")
                return 1
            }
            let story = ChangeStory.parse(text)
            let coverage = StoryCoverage(story: story, diff: diff, head: head, base: before)
            print("\(story.headline ?? "Untitled story") (\(path))")
            for (index, theme) in story.themes.enumerated() {
                print("  \(theme.title): \(coverage.types[index].count) type\(coverage.types[index].count == 1 ? "" : "s")")
            }
            for id in coverage.unexplained {
                print("not in the story: \(diff.change(ofNode: id).map { "\($0.node.name) (\($0.change.rawValue))" } ?? id)")
            }
            for id in coverage.withoutNotes {
                print("no note of its own: \(diff.change(ofNode: id).map { "\($0.node.name) (\($0.change.rawValue))" } ?? id)")
            }
            for member in coverage.membersWithoutNotes {
                let node = diff.change(ofNode: member.node)
                let change = node?.declarations.first { $0.name == member.name }?.change.rawValue ?? "changed"
                let type = node.map { $0.node.name.replacingOccurrences(of: ".", with: "/") } ?? member.node
                print("no note of its own: ``\(type.isEmpty ? "" : type + "/")\(member.name)`` (\(change))")
            }
            for dead in coverage.deadLinks {
                print("names nothing: ``\(dead.link)`` in \(dead.theme)")
            }
            return coverage.isComplete ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data("gloss: \((error as? Revision.Failure)?.message ?? "\(error)")\n".utf8))
            return 2
        }
    }
}

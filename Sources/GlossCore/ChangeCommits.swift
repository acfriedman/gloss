import Foundation

/// The commits that made each change since a base, read with `git blame`, so a change can say why in
/// its author's own words: the messages of the commits in the range that last wrote its lines, or, for
/// a declaration that is gone, of the commits that deleted them.
///
/// A declaration is matched to commits by its lines alone, its doc comment included, so the matching
/// is exact and the same on every read. A commit's message speaks for everything the commit changed,
/// so one large commit explains each declaration it touched in the same words. Lines edited and not
/// committed yet have no commit; the change says so instead.
public struct ChangeCommits: Sendable, Equatable {
    /// One commit in the range: its hash and its message.
    public struct Commit: Sendable, Equatable, Hashable {
        /// The full hash.
        public var hash: String
        /// The message's first line.
        public var subject: String
        /// The rest of the message, without its leading and trailing blank lines; empty for a commit with
        /// only a subject.
        public var body: String

        /// The hash's first seven characters, as git abbreviates it.
        public var shortHash: String { String(hash.prefix(7)) }
    }

    /// The commits in the range, oldest first.
    public private(set) var commits: [Commit] = []
    /// The commits behind each declaration change, by ``key(_:)``, as indexes into ``commits``.
    private var byChange: [String: Set<Int>] = [:]
    /// The declaration changes, by ``key(_:)``, with lines not committed yet.
    private var uncommitted: Set<String> = []

    /// The hash git gives lines not committed yet.
    private static let notCommitted = String(repeating: "0", count: 40)

    /// The commits behind one declaration change, oldest first.
    ///
    /// - Parameter change: A declaration change from the diff the commits were read for.
    /// - Returns: The commits; empty when only uncommitted edits made it, or none in the range did.
    public func commits(for change: InterfaceDiff.DeclarationChange) -> [Commit] {
        (byChange[Self.key(change)] ?? []).sorted().map { commits[$0] }
    }

    /// The commits behind any of a type's declaration changes, oldest first.
    ///
    /// - Parameter change: A type's change from the diff the commits were read for.
    /// - Returns: The commits, each once.
    public func commits(for change: InterfaceDiff.NodeChange) -> [Commit] {
        change.declarations.reduce(into: Set<Int>()) { $0.formUnion(byChange[Self.key($1)] ?? []) }.sorted().map { commits[$0] }
    }

    /// Whether edits not committed yet made a declaration change, in part or in whole.
    ///
    /// - Parameter change: A declaration change from the diff the commits were read for.
    /// - Returns: `true` when some of its lines are not committed.
    public func isUncommitted(_ change: InterfaceDiff.DeclarationChange) -> Bool {
        uncommitted.contains(Self.key(change))
    }

    /// Whether edits not committed yet made any of a type's declaration changes.
    ///
    /// - Parameter change: A type's change from the diff the commits were read for.
    /// - Returns: `true` when any of its declarations has lines not committed.
    public func isUncommitted(_ change: InterfaceDiff.NodeChange) -> Bool {
        change.declarations.contains(where: isUncommitted)
    }

    /// Reads which commits made each declaration change of a diff.
    ///
    /// - Parameters:
    ///   - diff: How the head differs from the base.
    ///   - base: The commit the diff compares with.
    ///   - head: The revision the head was read from, or `nil` for the working tree, whose uncommitted
    ///     edits then count too.
    ///   - root: The directory the interface's file names are relative to, inside the repository.
    /// - Returns: The commits behind each change.
    /// - Throws: ``Revision/Failure`` when git cannot list the range's commits.
    public static func read(_ diff: InterfaceDiff, base: String, head: String?, root: String) throws -> ChangeCommits {
        let phase = Timing.begin("read change commits")
        defer { Timing.end(phase, "\(diff.nodes.count) types") }
        let tip = head ?? "HEAD"
        var result = ChangeCommits()
        let log = try Revision.git(["log", "--reverse", "--format=%H%x1f%s%x1f%b%x1e", "\(base)..\(tip)"], in: root)
        for record in String(decoding: log, as: UTF8.self).split(separator: "\u{1e}") {
            let fields = record.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let body = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            result.commits.append(Commit(hash: String(fields[0]), subject: String(fields[1]), body: body))
        }
        let position = Dictionary(uniqueKeysWithValues: result.commits.enumerated().map { ($0.element.hash, $0.offset) })
        let changes = diff.nodes.flatMap(\.declarations)

        // What wrote each line now: one blame per file, of the working tree's copy or the head's.
        var written: [String: [Int: String]?] = [:]
        for file in Set(changes.compactMap { $0.place?.file }) {
            var arguments = ["blame", "--porcelain"]
            if head == nil { arguments += ["--contents", file] }
            arguments += ["\(base)..\(tip)", "--", file]
            // A file git has never seen is new and not committed, every line of it.
            written[file] = (try? Revision.git(arguments, in: root)).map { lineCommits($0, keepingBoundary: false) }
        }
        // What last had each line of a gone declaration, the commit after which deleted it.
        var lastHad: [String: [Int: String]] = [:]
        for file in Set(changes.filter { $0.place == nil }.compactMap { $0.wasPlace?.file }) {
            // A line deleted by the range's first commit was last had by the base, the boundary, so it stays.
            lastHad[file] = (try? Revision.git(["blame", "--reverse", "--porcelain", "\(base)..\(tip)", "--", file], in: root))
                .map { lineCommits($0, keepingBoundary: true) } ?? [:]
        }
        let tipCommit = try? String(decoding: Revision.git(["rev-parse", tip], in: root), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var deleter: [String: String?] = [:]
        func deleted(after commit: String, in file: String) -> String? {
            if let known = deleter[commit + file] { return known }
            let next = (try? Revision.git(["rev-list", "--reverse", "--ancestry-path", "\(commit)..\(tip)", "--", file], in: root))
                .flatMap { String(decoding: $0, as: UTF8.self).split(separator: "\n").first.map(String.init) }
            deleter[commit + file] = next
            return next
        }

        for change in changes {
            let key = key(change)
            var hashes: [String] = []
            if let place = change.place {
                guard let lines = written[place.file] ?? nil else {
                    result.uncommitted.insert(key)
                    continue
                }
                hashes = place.lines.compactMap { lines[$0] }
            } else if let place = change.wasPlace {
                for commit in Set(place.lines.compactMap { lastHad[place.file]?[$0] }) {
                    // A line the tip still has was deleted after it, in the working tree.
                    if commit == tipCommit {
                        if head == nil { hashes.append(notCommitted) }
                    } else if let next = deleted(after: commit, in: place.file) {
                        hashes.append(next)
                    }
                }
            }
            if hashes.contains(notCommitted) { result.uncommitted.insert(key) }
            let found = Set(hashes.compactMap { position[$0] })
            if !found.isEmpty { result.byChange[key, default: []].formUnion(found) }
        }
        return result
    }

    /// The commit git gives each line, from `git blame --porcelain` output.
    ///
    /// - Parameters:
    ///   - output: The output.
    ///   - keepingBoundary: `false` leaves out the lines git gives the range's boundary, which were there
    ///     before the range.
    /// - Returns: Each final line's commit hash, by line number.
    private static func lineCommits(_ output: Data, keepingBoundary: Bool) -> [Int: String] {
        var lines: [Int: String] = [:]
        var boundary: Set<String> = []
        var current: String?
        for line in String(decoding: output, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\t") { continue }
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[0].count == 40, parts[0].allSatisfy(\.isHexDigit), let final = Int(parts[2]) {
                current = String(parts[0])
                lines[final] = current
            } else if line == "boundary", let current {
                boundary.insert(current)
            }
        }
        return keepingBoundary ? lines : lines.filter { !boundary.contains($0.value) }
    }

    /// What tells declaration changes apart: their node, keyword, and name as a caller writes it, which
    /// overloads share.
    ///
    /// - Parameter change: A declaration change.
    /// - Returns: The key.
    private static func key(_ change: InterfaceDiff.DeclarationChange) -> String {
        change.node + "\u{0}" + change.keyword + "\u{0}" + change.name
    }
}

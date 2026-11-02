import Foundation

/// Swift sources as a git revision holds them, read straight from the repository without checking the
/// revision out, so an interface can be built for a base to compare the working tree against.
public enum Revision {
    /// Why a revision could not be read: git did not run, the directory is not in a repository, or git
    /// does not know the revision.
    public struct Failure: Error, Sendable, Equatable {
        /// What git said, or why it could not run.
        public var message: String
    }

    /// A name git gives a commit: a branch here, a branch on a remote, or a tag.
    public struct Ref: Sendable, Hashable {
        /// What kind of name a ref is.
        public enum Kind: String, Sendable, Hashable {
            /// A branch in this repository, such as `develop`.
            case branch
            /// A branch as a remote last had it, such as `origin/develop`.
            case remote
            /// A tag, such as `v1.2`.
            case tag
        }

        /// The short name, such as `develop`, `origin/develop`, or `v1.2`, which git takes as a revision.
        public var name: String
        /// Whether it is a branch, a remote's branch, or a tag.
        public var kind: Kind
    }

    /// Reads the Swift files under a directory as a revision holds them, choosing them as
    /// ``SourceFiles/swiftFiles(under:includeTests:)`` chooses files on disk.
    ///
    /// - Parameters:
    ///   - revision: Anything git names a commit by: a branch, a tag, `HEAD`, or a hash.
    ///   - directory: The directory whose files to read, inside a git work tree.
    ///   - root: The directory the returned paths are relative to, which holds `directory`, as the
    ///     working tree's paths are reported.
    ///   - includeTests: `false` leaves out any directory whose name ends in `Tests`.
    /// - Returns: Each file's path relative to `root` and its text, sorted by path; a file that is not
    ///   UTF-8 is left out.
    /// - Throws: ``Failure`` when git cannot run, `directory` is not in a repository, or the revision is
    ///   unknown.
    public static func sources(at revision: String, under directory: String, relativeTo root: String,
                               includeTests: Bool) throws -> [(file: String, source: String)] {
        let top = try text(git(["rev-parse", "--show-toplevel"], in: directory))
        let scanned = try text(git(["rev-parse", "--show-prefix"], in: directory))
        let base = try text(git(["rev-parse", "--show-prefix"], in: root))
        let listing = try git(["ls-tree", "-r", "-z", "--name-only", revision, "--", scanned.isEmpty ? "." : scanned], in: top)
        let paths = listing.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }.filter { path in
            path.hasSuffix(".swift") && !SourceFiles.isSkipped(String(path.dropFirst(scanned.count)), includeTests: includeTests)
        }.sorted()
        guard !paths.isEmpty else { return [] }

        // One `cat-file` reads every file: a header line, the bytes, and a newline for each.
        let request = Data(paths.map { "\(revision):\($0)\n" }.joined().utf8)
        let objects = try git(["cat-file", "--batch"], in: top, input: request)
        var files: [(file: String, source: String)] = []
        var offset = objects.startIndex
        for path in paths {
            guard let newline = objects[offset...].firstIndex(of: 0x0A) else { break }
            let header = objects[offset..<newline].split(separator: 0x20)
            offset = newline + 1
            guard header.count == 3, let size = Int(String(decoding: header[2], as: UTF8.self)) else { continue }
            let body = objects[offset..<offset + size]
            offset += size + 1
            guard let source = String(data: body, encoding: .utf8) else { continue }
            files.append((path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path, source))
        }
        return files
    }

    /// The commit two revisions last shared, as `git merge-base` finds it: where a branch left the one
    /// it will merge into.
    ///
    /// - Parameters:
    ///   - revision: One revision, such as `HEAD`.
    ///   - other: The other, such as `main`.
    ///   - directory: A directory inside the repository.
    /// - Returns: The commit's hash.
    /// - Throws: ``Failure`` when git cannot run, or knows no shared commit.
    public static func mergeBase(of revision: String, and other: String, in directory: String) throws -> String {
        try text(git(["merge-base", revision, other], in: directory))
    }

    /// The commit a revision names.
    ///
    /// - Parameters:
    ///   - revision: A branch, a tag, `HEAD`, or a hash.
    ///   - directory: A directory inside the repository.
    /// - Returns: The commit's hash.
    /// - Throws: ``Failure`` when git cannot run, or the revision names no commit.
    public static func commit(_ revision: String, in directory: String) throws -> String {
        try text(git(["rev-parse", "--verify", "--quiet", revision + "^{commit}"], in: directory))
    }

    /// The branches, the remotes' branches, and the tags of a repository, those committed to most
    /// recently first, without each remote's pointer to its default branch.
    ///
    /// - Parameter directory: A directory inside the repository.
    /// - Returns: The refs.
    /// - Throws: ``Failure`` when git cannot run or the directory is not in a repository.
    public static func refs(in directory: String) throws -> [Ref] {
        let output = try text(git(["for-each-ref", "--sort=-committerdate", "--format=%(refname)",
                                   "refs/heads", "refs/remotes", "refs/tags"], in: directory))
        let kinds: [(prefix: String, kind: Ref.Kind)] = [("refs/heads/", .branch), ("refs/remotes/", .remote), ("refs/tags/", .tag)]
        return output.split(separator: "\n").compactMap { line in
            guard let match = kinds.first(where: { line.hasPrefix($0.prefix) }) else { return nil }
            let name = String(line.dropFirst(match.prefix.count))
            return match.kind == .remote && name.hasSuffix("/HEAD") ? nil : Ref(name: name, kind: match.kind)
        }
    }

    /// The branch checked out.
    ///
    /// - Parameter directory: A directory inside the repository.
    /// - Returns: The branch's name, or `nil` when no branch is checked out, as when the head is detached.
    /// - Throws: ``Failure`` when git cannot run or the directory is not in a repository.
    public static func currentBranch(in directory: String) throws -> String? {
        let name = try text(git(["branch", "--show-current"], in: directory))
        return name.isEmpty ? nil : name
    }

    /// Runs git in a directory and collects what it prints.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git -C directory`.
    ///   - directory: The directory git runs in.
    ///   - input: What to write to git's standard input, or `nil` for none.
    /// - Returns: The standard output.
    /// - Throws: ``Failure`` when git cannot run or exits with an error.
    private static func git(_ arguments: [String], in directory: String, input: Data? = nil) throws -> Data {
        try Timing.measure("git", arguments.prefix(2).joined(separator: " ")) { try run(arguments, in: directory, input: input) }
    }

    /// Runs git, as ``git(_:in:input:)`` does once it is timed.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git -C directory`.
    ///   - directory: The directory git runs in.
    ///   - input: What to write to git's standard input, or `nil` for none.
    /// - Returns: The standard output.
    /// - Throws: ``Failure`` when git cannot run or exits with an error.
    private static func run(_ arguments: [String], in directory: String, input: Data?) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory] + arguments
        let output = Pipe()
        let errors = Pipe()
        let feed = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : feed
        // `waitUntilExit()` polls the run loop and adds tens of milliseconds to every call; the exit is
        // waited for exactly instead.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw Failure(message: "git could not run: \(error.localizedDescription)")
        }
        // Input goes in from another thread, so a large answer never waits on a full pipe.
        if let input {
            let writer = feed.fileHandleForWriting
            DispatchQueue.global().async {
                writer.write(input)
                try? writer.close()
            }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let complaint = errors.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: complaint, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty ? "git \(arguments.first ?? "") failed" : message)
        }
        return data
    }

    /// The output of a git command that prints one line.
    ///
    /// - Parameter data: The output.
    /// - Returns: The line without its newline.
    private static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

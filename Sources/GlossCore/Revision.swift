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

    /// Runs git in a directory and collects what it prints.
    ///
    /// - Parameters:
    ///   - arguments: The arguments after `git -C directory`.
    ///   - directory: The directory git runs in.
    ///   - input: What to write to git's standard input, or `nil` for none.
    /// - Returns: The standard output.
    /// - Throws: ``Failure`` when git cannot run or exits with an error.
    private static func git(_ arguments: [String], in directory: String, input: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory] + arguments
        let output = Pipe()
        let errors = Pipe()
        let feed = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input == nil ? FileHandle.nullDevice : feed
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
        process.waitUntilExit()
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

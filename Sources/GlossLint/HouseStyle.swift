import Foundation
import GlossRead

/// A project's own house style: how loudly each rule speaks, which files are not linted, and which
/// declarations owe a doc, read from `.gloss/style.json` so each project chooses its own.
///
/// Every field is optional, and no file at all is gloss's own style: every rule an error, and every
/// declaration but the private ones owing a doc. A file names rules by their codes, so a typo is an
/// error rather than a rule quietly left on:
///
/// ```json
/// {
///   "severity": "warning",
///   "rules": { "missing-doc": "error", "summary-*": "off" },
///   "exclude": ["Sources/Generated", "**/*.pb.swift"],
///   "requireDocs": "public"
/// }
/// ```
public struct HouseStyle: Sendable, Equatable {
    /// How loudly a rule speaks under a style.
    public enum Level: String, Sendable, CaseIterable {
        /// Reported as `error:`, and the run fails.
        case error
        /// Reported as `warning:`, and the run still passes.
        case warning
        /// Not checked at all.
        case off
    }

    /// A style file that cannot be read as one, said in a line that names the fix.
    public struct Problem: Error, Sendable, Equatable, CustomStringConvertible {
        /// What is wrong, and where.
        public var description: String
    }

    /// Where a style lives, relative to the folder it styles.
    public static let path = ".gloss/style.json"

    /// The level of every rule ``rules`` does not name.
    public var severity: Level = .error
    /// Levels by rule code, such as `missing-doc`, or by a prefix ending in `*`, such as `summary-*`; a code
    /// wins over a prefix, and a longer prefix over a shorter one.
    public var rules: [String: Level] = [:]
    /// Paths that are not linted, as globs from ``root``: `*` within a name, `**` across folders, `?` for one
    /// character, and a folder's name for everything in it. Their declarations are still read, so links
    /// into them resolve.
    public var exclude: [String] = []
    /// The narrowest access that owes a doc: `public` asks only for the API, `internal` for every
    /// declaration but the private ones. It decides `missing-doc` alone; a doc that is written is checked
    /// whatever the access.
    public var requireDocs = "internal"
    /// The folder the style styles, the one holding `.gloss`, which ``exclude`` patterns start from.
    public var root: String
    /// The folder that relative source paths are given from: the current directory for the command line,
    /// the opened folder for the app.
    public var base: String

    /// Makes gloss's own style for a folder.
    ///
    /// - Parameters:
    ///   - root: The folder styled, which ``exclude`` patterns start from; a relative one is read from the
    ///     current directory.
    ///   - base: The folder relative source paths are given from; `root` when `nil`.
    public init(root: String = ".", base: String? = nil) {
        self.root = root
        self.base = base ?? root
    }

    /// Reads a style file's JSON, checking every key and value against what gloss knows.
    ///
    /// - Parameters:
    ///   - data: The file's contents.
    ///   - root: The folder the style styles.
    ///   - base: The folder relative source paths are given from; `root` when `nil`.
    /// - Returns: The style, with gloss's own choices where the file says nothing.
    /// - Throws: ``Problem`` when the file is not a JSON object, has a key gloss does not know, names a
    ///   rule no code or prefix matches, or gives a value it cannot use.
    public static func parse(_ data: Data, root: String, base: String? = nil) throws -> HouseStyle {
        var style = HouseStyle(root: root, base: base)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Problem(description: "\(path) is not a JSON object; write `{}` for gloss's own style.")
        }
        let known = ["severity", "rules", "exclude", "requireDocs"]
        if let unknown = object.keys.sorted().first(where: { !known.contains($0) }) {
            throw Problem(description: "\(path) has `\(unknown)`, which gloss does not read; the keys are \(known.map { "`\($0)`" }.joined(separator: ", ")).")
        }
        if let value = object["severity"] { style.severity = try level(value, for: "severity") }
        if let value = object["rules"] {
            guard let rules = value as? [String: Any] else {
                throw Problem(description: "\(path): `rules` maps rule codes to `error`, `warning`, or `off`.")
            }
            for (code, level) in rules {
                guard Rule.allCases.contains(where: { matches(code, $0) }) else {
                    throw Problem(description: "\(path): `\(code)` names no rule; codes are as findings print them, such as `missing-doc` or `summary-*`.")
                }
                style.rules[code] = try Self.level(level, for: code)
            }
        }
        if let value = object["exclude"] {
            guard let patterns = value as? [String] else {
                throw Problem(description: "\(path): `exclude` is a list of paths or globs, such as `[\"Sources/Generated\"]`.")
            }
            style.exclude = patterns
        }
        if let value = object["requireDocs"] {
            guard let access = value as? String, ["public", "package", "internal"].contains(access) else {
                throw Problem(description: "\(path): `requireDocs` is `public`, `package`, or `internal`, the narrowest access that owes a doc.")
            }
            style.requireDocs = access
        }
        return style
    }

    /// Finds the style for a folder: the nearest `.gloss/style.json` in it or a folder above it, else
    /// gloss's own.
    ///
    /// - Parameter folder: Where the sources are given from, which is also where the search starts.
    /// - Returns: The style, rooted at the folder holding the file it read, or at `folder` for gloss's own.
    /// - Throws: ``Problem`` when the file found cannot be read as a style.
    public static func find(from folder: String) throws -> HouseStyle {
        var directory = URL(fileURLWithPath: folder).standardizedFileURL
        while true {
            let file = directory.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: file.path) { return try load(file.path, base: folder) }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return HouseStyle(root: folder) }
            directory = parent
        }
    }

    /// Reads a style file named outright.
    ///
    /// - Parameters:
    ///   - file: The file's path; its style roots at the folder that holds its `.gloss` folder, or at the
    ///     folder it is in when it is not in one.
    ///   - base: The folder relative source paths are given from; the current directory when `nil`.
    /// - Returns: The style.
    /// - Throws: ``Problem`` when the file cannot be read or is not a style.
    public static func load(_ file: String, base: String? = nil) throws -> HouseStyle {
        guard let data = FileManager.default.contents(atPath: file) else {
            throw Problem(description: "Cannot read the style at \(file).")
        }
        var folder = URL(fileURLWithPath: file).standardizedFileURL.deletingLastPathComponent()
        if folder.lastPathComponent == ".gloss" { folder.deleteLastPathComponent() }
        return try parse(data, root: folder.path, base: base ?? FileManager.default.currentDirectoryPath)
    }

    /// How loudly a rule speaks under this style.
    ///
    /// - Parameter rule: A rule.
    /// - Returns: Its level by code, else by its longest matching prefix, else ``severity``.
    public func level(of rule: Rule) -> Level {
        if let level = rules[rule.rawValue] { return level }
        let prefixes = rules.keys.filter { $0.hasSuffix("*") && Self.matches($0, rule) }
        return prefixes.max { $0.count < $1.count }.flatMap { rules[$0] } ?? severity
    }

    /// Whether a declaration owes a doc: never when the harness excuses it, and otherwise when its access
    /// is at least ``requireDocs``.
    ///
    /// - Parameter declaration: A declaration as read.
    /// - Returns: `true` when a missing doc is a finding.
    public func requiresDoc(_ declaration: Declaration) -> Bool {
        declaration.requiresDoc && Declaration.rank(declaration.access) >= Declaration.rank(requireDocs)
    }

    /// Whether a file is left out of the lint.
    ///
    /// - Parameter file: A source path, absolute or given from ``base``.
    /// - Returns: `true` when a pattern in ``exclude`` matches the path from ``root``, or a folder it is in.
    public func excludes(_ file: String) -> Bool {
        guard !exclude.isEmpty else { return false }
        func absolute(_ path: String, from folder: String) -> String {
            URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)).absoluteURL.standardizedFileURL.path
        }
        let current = FileManager.default.currentDirectoryPath
        let path = absolute(file, from: absolute(base, from: current))
        let root = absolute(root, from: current)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : file
        let parts = relative.split(separator: "/").map(String.init)
        return exclude.contains { pattern in
            let globs = pattern.split(separator: "/").map(String.init)
            return (1...max(parts.count, 1)).contains { Self.glob(globs[...], parts.prefix($0)[...]) }
        }
    }

    /// Reports diagnostics as this style asks: each at its rule's level, the ones turned off dropped.
    ///
    /// - Parameter diagnostics: What the rules found, all at gloss's own level.
    /// - Returns: The diagnostics still reported, in the same order.
    public func report(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        diagnostics.compactMap { diagnostic in
            var reported = diagnostic
            switch level(of: diagnostic.rule) {
            case .off: return nil
            case .warning: reported.severity = .warning
            case .error: reported.severity = .error
            }
            return reported
        }
    }

    /// Reads a level from a style file.
    ///
    /// - Parameters:
    ///   - value: The value as JSON gives it.
    ///   - key: What it is the level of, for the message.
    /// - Returns: The level.
    /// - Throws: ``Problem`` when the value is not `error`, `warning`, or `off`.
    private static func level(_ value: Any, for key: String) throws -> Level {
        guard let text = value as? String, let level = Level(rawValue: text) else {
            throw Problem(description: "\(path): `\(key)` is `error`, `warning`, or `off`.")
        }
        return level
    }

    /// Whether a rule key names a rule: its code exactly, or a prefix of it ending in `*`.
    ///
    /// - Parameters:
    ///   - key: A key from `rules`.
    ///   - rule: A rule.
    /// - Returns: `true` when the key covers the rule.
    private static func matches(_ key: String, _ rule: Rule) -> Bool {
        key.hasSuffix("*") ? rule.rawValue.hasPrefix(key.dropLast()) : rule.rawValue == key
    }

    /// Whether path components match glob components, `**` standing for any number of folders.
    ///
    /// - Parameters:
    ///   - globs: The pattern's components.
    ///   - parts: The path's components.
    /// - Returns: `true` when every component matches.
    private static func glob(_ globs: ArraySlice<String>, _ parts: ArraySlice<String>) -> Bool {
        guard let first = globs.first else { return parts.isEmpty }
        if first == "**" {
            return (parts.startIndex...parts.endIndex).contains { glob(globs.dropFirst(), parts[$0...]) }
        }
        guard let part = parts.first, wildcard(Array(first)[...], Array(part)[...]) else { return false }
        return glob(globs.dropFirst(), parts.dropFirst())
    }

    /// Whether a name matches one glob component: `*` for any run of characters, `?` for one.
    ///
    /// - Parameters:
    ///   - pattern: The component's characters.
    ///   - name: The name's characters.
    /// - Returns: `true` when the name matches.
    private static func wildcard(_ pattern: ArraySlice<Character>, _ name: ArraySlice<Character>) -> Bool {
        guard let first = pattern.first else { return name.isEmpty }
        switch first {
        case "*": return (name.startIndex...name.endIndex).contains { wildcard(pattern.dropFirst(), name[$0...]) }
        case "?": return !name.isEmpty && wildcard(pattern.dropFirst(), name.dropFirst())
        default: return name.first == first && wildcard(pattern.dropFirst(), name.dropFirst())
        }
    }
}

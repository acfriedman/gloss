import GlossRead
import GlossModel

/// One type found by a few typed letters, with where the letters landed in its name.
public struct QuickOpenMatch: Sendable, Equatable {
    /// The matched node: any node, nested types, extensions, and file scope included.
    public var node: Graph.Node
    /// The name the letters were matched in: the qualified name, or the label for file scope.
    public var name: String
    /// The offsets of the matched characters in ``name``, for drawing them apart.
    public var matched: [Int]
    /// How well the letters fit the name, higher being better; it only ranks matches of one query
    /// against each other.
    public var score: Int
}

extension Atlas {
    /// Finds types the way Xcode's Open Quickly does: the typed letters appear in the name in order,
    /// not necessarily side by side, and matches that start words rank first.
    ///
    /// - Parameters:
    ///   - query: The typed letters; case does not matter, and spaces are ignored.
    ///   - limit: The most matches to return.
    /// - Returns: The best matches, best first; ties go to the shorter name, then to graph order.
    ///   Empty for an empty query.
    ///
    /// A match scores for each letter, more for a letter that starts a word (the first letter, an
    /// uppercase letter after a lowercase one, or a letter after `.` or `_`), more again for a letter
    /// right after the previous match, and most for an exact name or a prefix of the last component.
    public func quickOpen(_ query: String, limit: Int = 50) -> [QuickOpenMatch] {
        let phase = Timing.begin("quick open"); defer { Timing.end(phase, query) }
        let letters = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !letters.isEmpty else { return [] }
        var found: [(match: QuickOpenMatch, order: Int)] = []
        for (order, node) in nodes.enumerated() {
            let name = node.name.isEmpty ? label(node) : node.name
            guard let match = Self.match(letters, in: name) else { continue }
            found.append((QuickOpenMatch(node: node, name: name, matched: match.offsets, score: match.score), order))
        }
        return found.sorted {
            ($0.match.score, -$0.match.name.count, -$0.order) > ($1.match.score, -$1.match.name.count, -$1.order)
        }.prefix(limit).map(\.match)
    }

    /// Scores the letters against one name, trying both the earliest placement and the placement
    /// that prefers word starts, and keeping the better.
    ///
    /// - Parameters:
    ///   - letters: The lowercased query, without spaces.
    ///   - name: The name to match in.
    /// - Returns: The score and the matched offsets, or `nil` when the letters do not all appear in order.
    static func match(_ letters: [Character], in name: String) -> (score: Int, offsets: [Int])? {
        let characters = Array(name)
        let lowered = characters.map { Character($0.lowercased()) }
        let starts = characters.indices.map { index in
            index == 0 || [".", "_", " "].contains(characters[index - 1])
                || (characters[index].isUppercase && characters[index - 1].isLowercase)
        }
        func place(preferringStarts: Bool) -> [Int]? {
            var offsets: [Int] = []
            var from = 0
            for letter in letters {
                let candidates = (from..<lowered.count).filter { lowered[$0] == letter }
                guard let first = candidates.first else { return nil }
                let pick = preferringStarts ? candidates.first(where: { starts[$0] }) ?? first : first
                offsets.append(pick)
                from = pick + 1
            }
            return offsets
        }
        func score(_ offsets: [Int]) -> Int {
            var total = 0
            for (position, offset) in offsets.enumerated() {
                total += 1
                if starts[offset] { total += 8 }
                if position > 0, offsets[position - 1] == offset - 1 { total += 5 }
                if position > 0 { total -= min(offset - offsets[position - 1] - 1, 3) }
            }
            if offsets.first == 0 { total += 10 }
            let lastComponent = name.split(separator: ".").last.map { $0.lowercased() } ?? ""
            let typed = String(letters)
            if name.lowercased() == typed || lastComponent == typed { total += 100 } else if lastComponent.hasPrefix(typed) { total += 40 }
            return total - characters.count / 4
        }
        let placements = [place(preferringStarts: false), place(preferringStarts: true)].compactMap { $0 }
        return placements.map { (score($0), $0) }.max { $0.0 < $1.0 }
    }
}

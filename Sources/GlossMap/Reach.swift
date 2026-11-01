import GlossCore

/// Which way a reach follows dependencies from its root.
public enum ReachDirection: Sendable, Equatable {
    /// Everything the root depends on, and what those depend on, drawn below it.
    case dependencies
    /// Everything that uses the root, and what uses those, drawn above it.
    case users
}

/// One type and everything it reaches in one direction, cut at whole depths so the drawing stays within
/// what a reader can hold.
public struct Reach: Sendable {
    /// The drawing: the root, every drawn type, and the dependencies among them.
    public var layout: GraphLayout
    /// How many steps from the root the drawing goes, at least 1.
    public var depth: Int
    /// How many steps the reach has in all; 0 when the root leads nowhere.
    public var totalDepth: Int
    /// How many types are drawn besides the root.
    public var drawn: Int
    /// How many types the root reaches in all, at any depth.
    public var total: Int
    /// Types one step from the root left out because even that step is over the budget, least
    /// connected first out; empty when the first step fits.
    public var overflow: [String]
}

extension Atlas {
    /// Follows dependencies from a type one whole step at a time, and draws as many steps as fit the
    /// budget, or exactly the steps asked for.
    ///
    /// - Parameters:
    ///   - id: Any node, nested types included; the reach starts at that type itself.
    ///   - direction: Toward what the type depends on, or toward what uses it.
    ///   - depth: The steps to draw, at least 1; `nil` draws the most whole steps that fit `budget`.
    ///   - minimumRank: The narrowest access, as ``GlossCore/Contract/rank(_:)``, a type needs to be
    ///     followed and drawn.
    ///   - budget: The most boxes an automatic depth draws, the root included.
    /// - Returns: The drawing and how much of the reach it shows, or `nil` for an unknown id.
    ///
    /// Every type is its own box, nested ones included, as in the focus, so a nested type reaches from
    /// itself and a type's own nested types are among what it depends on. Every dependency counts,
    /// signature and body alike. Only the edges from one step to the next are drawn, which show how each type leads
    /// back to the root. A type at the last drawn step that leads further is drawn as a boundary box
    /// whose detail counts its next step not drawn. When the first step alone is over the budget, its most
    /// connected types are drawn and the rest are listed as ``Reach/overflow``.
    public func reach(from id: String, toward direction: ReachDirection, depth: Int? = nil,
                      minimumRank: Int, budget: Int = mapBudget) -> Reach? {
        guard let root = byID[id] else { return nil }
        var next: [String: [String]] = [:]
        var degree: [String: Int] = [:]
        for link in edges {
            let (from, to) = direction == .dependencies ? (link.from, link.to) : (link.to, link.from)
            next[from, default: []].append(to)
            degree[link.from, default: 0] += 1
            degree[link.to, default: 0] += 1
        }
        let shown = { (id: String) in self.byID[id].map { self.rank(of: $0) >= minimumRank } ?? false }

        var layers: [[String]] = [[root.id]]
        var seen: Set<String> = [root.id]
        while let frontier = layers.last {
            let step = frontier.flatMap { next[$0] ?? [] }.filter { shown($0) && seen.insert($0).inserted }
            guard !step.isEmpty else { break }
            layers.append(step)
        }
        let totalDepth = layers.count - 1
        let total = seen.count - 1

        var drawnDepth = min(max(depth ?? 1, 1), max(totalDepth, 1))
        if depth == nil {
            var count = 1
            for (index, layer) in layers.enumerated().dropFirst() {
                count += layer.count
                guard count <= budget else { break }
                drawnDepth = index
            }
        }
        var drawn = layers.prefix(drawnDepth + 1).flatMap { $0 }
        var overflow: [String] = []
        if depth == nil, drawnDepth == 1, layers.count > 1, layers[1].count + 1 > budget {
            let ranked = layers[1].enumerated().sorted {
                (-(degree[$0.element] ?? 0), $0.offset) < (-(degree[$1.element] ?? 0), $1.offset)
            }.map(\.element)
            let kept = Set(ranked.prefix(budget - 1))
            overflow = layers[1].filter { !kept.contains($0) }
            drawn = [root.id] + layers[1].filter(kept.contains)
        }

        let drawnSet = Set(drawn)
        let lastStep = Set(drawnDepth < layers.count ? layers[drawnDepth] : [])
        let further = direction == .dependencies ? "below" : "above"
        let items = drawn.compactMap { id -> GraphLayout.Item? in
            guard let node = byID[id] else { return nil }
            let beyond = lastStep.contains(id) ? (next[id] ?? []).filter { shown($0) && !drawnSet.contains($0) }.count : 0
            var flags: GraphLayout.Flags = []
            if findings(under: id) > 0 { flags.insert(.dirty) }
            if rank(of: node) == 0 { flags.insert(.private) }
            if beyond > 0 { flags.insert(.boundary) }
            let place = node.module != root.module ? [node.module] : []
            let more = beyond > 0 ? ["+\(beyond) \(further)"] : []
            return GraphLayout.Item(unit: .type(id), label: label(node),
                                    detail: ([Wording.kind(of: node)] + place + more).joined(separator: " · "), flags: flags)
        }
        // Only the edges from one step to the next, which show how each type leads back to the root;
        // the others between drawn types are real but would bury that.
        var step: [String: Int] = [:]
        for (index, layer) in layers.enumerated() { for id in layer { step[id] = index } }
        let links = edges.filter { link in
            guard drawnSet.contains(link.from), drawnSet.contains(link.to), let from = step[link.from], let to = step[link.to] else { return false }
            return direction == .dependencies ? to == from + 1 : from == to + 1
        }.map { link in
            GraphLayout.Link(from: link.from, to: link.to, dashed: link.roles == [.body],
                             title: "\(label(of: .type(link.from))) \(Wording.words(link.roles)) \(label(of: .type(link.to)))")
        }
        return Reach(layout: GraphLayout.layered(items, links), depth: drawnDepth, totalDepth: totalDepth,
                     drawn: drawn.count - 1, total: total, overflow: overflow)
    }
}

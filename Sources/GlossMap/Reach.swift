import GlossCore

/// Which way a reach follows dependencies from its root.
public enum ReachDirection: Sendable, Equatable {
    /// Everything the root depends on, and what those depend on, drawn below it.
    case dependencies
    /// Everything that uses the root, and what uses those, drawn above it.
    case users
    /// Both at once: what uses the root above it, what it depends on below it, to the same depth.
    case both
}

/// One type and everything it reaches, cut at whole depths so the drawing stays within what a reader
/// can hold.
public struct Reach: Sendable {
    /// The drawing: the root, every drawn type, and the dependencies among them.
    public var layout: GraphLayout
    /// How many steps from the root the drawing goes, at least 1.
    public var depth: Int
    /// How many steps the reach has in all, on its deeper side; 0 when the root leads nowhere.
    public var totalDepth: Int
    /// How many types are drawn above the root: the types that use it, at any drawn step.
    public var above: Int
    /// How many types are drawn below the root: the types it depends on, at any drawn step.
    public var below: Int
    /// How many types the root reaches in all, both sides and every depth.
    public var total: Int
    /// Types one step from the root left out because even that step is over the budget; empty when the
    /// first step fits.
    public var overflow: [String]
    /// Each drawn type's drawn neighbors one step closer to the root, in graph order; the root has none.
    public var parents: [String: [String]] = [:]
    /// The drawn types above the root, which use it, as against those below, which it depends on.
    public var aboveIDs: Set<String> = []
    /// How many types are drawn besides the root.
    public var drawn: Int { above + below }

    /// The ways a drawn type leads back to the root, each a run of drawn dependencies read top to bottom
    /// as the map draws them: from the root down to a type below it, and from a type above down to the
    /// root.
    ///
    /// - Parameters:
    ///   - id: A drawn type.
    ///   - limit: The most trails to give, one per neighbor a step closer to the root.
    /// - Returns: One trail per such neighbor, in graph order, each followed on through the first
    ///   neighbor closer still; and how many neighbors were left out. No trails for the root or for a
    ///   type not drawn.
    ///
    /// A type a step from the root has one trail, its dependency with the root. Past that, a type
    /// reached from several types gets a trail through each, but each trail climbs on by one way only,
    /// so the trails stay as many as the type's own neighbors however the steps above them branch.
    public func trails(to id: String, limit: Int = 3) -> (trails: [[GraphLayout.Link]], more: Int) {
        let direct = parents[id] ?? []
        let isAbove = aboveIDs.contains(id)
        func link(_ from: String, _ to: String) -> GraphLayout.Link? {
            layout.curves.first { $0.link.from == from && $0.link.to == to }?.link
        }
        let trails = direct.prefix(limit).map { parent -> [GraphLayout.Link] in
            var chain = [id, parent]
            while let next = parents[chain[chain.count - 1]]?.first, !chain.contains(next) { chain.append(next) }
            let hops = zip(chain, chain.dropFirst()).compactMap { near, far in isAbove ? link(near, far) : link(far, near) }
            return isAbove ? hops : hops.reversed()
        }
        return (trails, max(direct.count - limit, 0))
    }
}

extension Atlas {
    /// Follows dependencies from a type one whole step at a time, and draws as many steps as fit the
    /// budget, or exactly the steps asked for.
    ///
    /// - Parameters:
    ///   - id: Any node, nested types included; the reach starts at that type itself.
    ///   - direction: Toward what the type depends on, toward what uses it, or both.
    ///   - depth: The steps to draw on each side, at least 1; `nil` draws the most whole steps that fit
    ///     `budget`.
    ///   - minimumRank: The narrowest access, as ``GlossCore/Contract/rank(_:)``, a type needs to be
    ///     followed and drawn.
    ///   - budget: The most boxes an automatic depth draws, the root included, and the most the first
    ///     step draws at any depth.
    /// - Returns: The drawing and how much of the reach it shows, or `nil` for an unknown id.
    ///
    /// Types from two or more modules are drawn in module lanes, the root's emphasized, and split at the
    /// root: what lies above it, the root, and what lies below each get lanes of their own. Every type is its
    /// own box, nested ones included, so a nested type reaches from itself and a
    /// type's own nested types are among what it depends on. Every dependency counts, signature and body
    /// alike. Only the edges from one step to the next are drawn, which show how each type leads back to
    /// the root; a type on both sides of a cycle is drawn once, below. A type at the last drawn step that
    /// leads further is a boundary box whose detail counts its next step not drawn. When the first step
    /// is over the budget, its most connected types are drawn, the budget shared between the sides, and
    /// the rest are listed as ``Reach/overflow``.
    public func reach(from id: String, toward direction: ReachDirection, depth: Int? = nil,
                      minimumRank: Int, budget: Int = mapBudget) -> Reach? {
        let phase = Timing.begin("reach"); defer { Timing.end(phase, "\(id) \(direction)") }
        guard let root = byID[id] else { return nil }
        // The indexes the atlas keeps, rather than a pass over every edge per reach.
        let down = { (id: String) in (self.edgesFrom[id] ?? []).map(\.to) }
        let up = { (id: String) in (self.edgesTo[id] ?? []).map(\.from) }
        let degree = { (id: String) in (self.edgesFrom[id]?.count ?? 0) + (self.edgesTo[id]?.count ?? 0) }
        let shown = { (id: String) in self.byID[id].map { self.rank(of: $0) >= minimumRank } ?? false }

        var seen: Set<String> = [root.id]
        func walk(_ next: (String) -> [String]) -> [[String]] {
            var layers: [[String]] = [[root.id]]
            while let frontier = layers.last {
                let step = frontier.flatMap(next).filter { shown($0) && seen.insert($0).inserted }
                guard !step.isEmpty else { break }
                layers.append(step)
            }
            return layers
        }
        var below = direction == .users ? [[root.id]] : walk(down)
        var above = direction == .dependencies ? [[root.id]] : walk(up)
        let totalDepth = max(below.count, above.count) - 1
        let total = seen.count - 1

        func size(_ steps: Int) -> Int {
            1 + [below, above].reduce(0) { sum, layers in sum + layers.dropFirst().prefix(steps).reduce(0) { $0 + $1.count } }
        }
        var drawnDepth = min(max(depth ?? 1, 1), max(totalDepth, 1))
        if depth == nil {
            for steps in stride(from: 2, through: max(totalDepth, 1), by: 1) where size(steps) <= budget { drawnDepth = steps }
        }

        var overflow: [String] = []
        if drawnDepth == 1, size(1) > budget {
            let capacity = budget - 1
            let downCount = below.count > 1 ? below[1].count : 0
            let upCount = above.count > 1 ? above[1].count : 0
            let upKeep = min(upCount, downCount == 0 ? capacity : max(capacity / 2, capacity - downCount))
            let downKeep = min(downCount, capacity - upKeep)
            func trim(_ layers: inout [[String]], keeping count: Int) {
                guard layers.count > 1 else { return }
                let ranked = layers[1].enumerated().sorted {
                    (-degree($0.element), $0.offset) < (-degree($1.element), $1.offset)
                }.map(\.element)
                let kept = Set(ranked.prefix(count))
                overflow += layers[1].filter { !kept.contains($0) }
                layers[1] = layers[1].filter(kept.contains)
            }
            trim(&below, keeping: downKeep)
            trim(&above, keeping: upKeep)
        }

        var belowStep: [String: Int] = [:]
        var aboveStep: [String: Int] = [:]
        for (index, layer) in below.prefix(drawnDepth + 1).enumerated() { for id in layer { belowStep[id] = index } }
        for (index, layer) in above.prefix(drawnDepth + 1).enumerated() { for id in layer { aboveStep[id] = index } }
        let drawnAbove = above.dropFirst().prefix(drawnDepth).flatMap { $0 }
        let drawnBelow = below.dropFirst().prefix(drawnDepth).flatMap { $0 }
        let drawn = [root.id] + drawnAbove + drawnBelow
        let drawnSet = Set(drawn)

        let items = drawn.compactMap { id -> GraphLayout.Item? in
            guard let node = byID[id] else { return nil }
            var beyond = 0
            var further = ""
            if belowStep[id] == drawnDepth {
                beyond = down(id).filter { shown($0) && !drawnSet.contains($0) }.count
                further = "below"
            } else if aboveStep[id] == drawnDepth {
                beyond = up(id).filter { shown($0) && !drawnSet.contains($0) }.count
                further = "above"
            }
            var flags: GraphLayout.Flags = []
            if findings(under: id) > 0 { flags.insert(.dirty) }
            if rank(of: node) == 0 { flags.insert(.private) }
            if beyond > 0 { flags.insert(.boundary) }
            let more = beyond > 0 ? ["+\(beyond) \(further)"] : []
            return GraphLayout.Item(unit: .type(id), label: label(node),
                                    detail: ([Wording.kind(of: node)] + more).joined(separator: " · "), flags: flags,
                                    group: node.module)
        }
        // Only the edges from one step to the next, which show how each type leads back to the root;
        // the others between drawn types are real but would bury that.
        var parents: [String: [String]] = [:]
        let links = edges.filter { link in
            guard drawnSet.contains(link.from), drawnSet.contains(link.to) else { return false }
            if let from = belowStep[link.from], belowStep[link.to] == from + 1 {
                parents[link.to, default: []].append(link.from)
                return true
            }
            if let to = aboveStep[link.to], aboveStep[link.from] == to + 1 {
                parents[link.from, default: []].append(link.to)
                return true
            }
            return false
        }.map { link in
            GraphLayout.Link(from: link.from, to: link.to, dashed: link.roles == [.body],
                             title: "\(label(of: .type(link.from))) \(Wording.words(link.roles)) \(label(of: .type(link.to)))")
        }
        return Reach(layout: GraphLayout.layered(items, links, emphasis: root.module, splitAt: root.id), depth: drawnDepth, totalDepth: totalDepth,
                     above: drawnAbove.count, below: drawnBelow.count, total: total, overflow: overflow,
                     parents: parents, aboveIDs: Set(drawnAbove))
    }
}

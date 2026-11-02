import GlossCore

extension Atlas {
    /// How a box on the map differs from a base, folding what lies inside it into the box: a type new
    /// since the base, or a module or folder whose every type is new, is added; one holding anything
    /// added, removed, or changed, nested types included, is changed.
    ///
    /// - Parameters:
    ///   - unit: What a box stands for.
    ///   - diff: How the interface differs from the base.
    /// - Returns: The box's change, or `nil` when nothing in it differs.
    public func change(of unit: MapScope.Unit, in diff: InterfaceDiff) -> InterfaceDiff.Change? {
        let inside: [InterfaceDiff.NodeChange]
        let all: Int
        switch unit {
        case .type(let id):
            if diff.change(ofNode: id)?.change == .added { return .added }
            return diff.nodes.contains { $0.node.id == id || $0.node.id.hasPrefix(id + ".") } ? .changed : nil
        case .module(let module):
            inside = diff.nodes.filter { $0.node.module == module }
            all = nodes.filter { $0.module == module }.count
        case .folder(let module, let folder):
            let held = { (node: Graph.Node) in node.module == module && self.folder(of: node) == folder }
            inside = diff.nodes.filter { change in byID[change.node.id].map(held) ?? false }
            all = nodes.filter(held).count
        }
        guard !inside.isEmpty else { return nil }
        return inside.count == all && inside.allSatisfy { $0.change == .added } ? .added : .changed
    }
}

/// What changed since a base and the types one step around it, drawn as one figure: the blast radius of
/// a change at a glance.
public struct ChangesFigure: Sendable {
    /// The drawing: the changed types, their neighbors, and the dependencies between a change and the rest.
    public var layout: GraphLayout
    /// How many changed types are drawn.
    public var changed: Int
    /// How many types around them are drawn.
    public var around: Int
    /// The changed types and neighbors left out to stay within the budget, most connected first.
    public var overflow: [String]
}

extension Atlas {
    /// Lays out what changed since a base, with the types that use a change or that a change uses.
    ///
    /// - Parameters:
    ///   - diff: How the interface differs from the base.
    ///   - minimumRank: The narrowest access, as ``GlossCore/Contract/rank(_:)``, a type needs to be drawn.
    ///   - budget: The most boxes to draw.
    /// - Returns: The figure, every type its own box, nested ones included.
    ///
    /// The changed types come first: when they alone are over the budget, the most connected of them
    /// are drawn and nothing around them. Otherwise the neighbors fill what is left, those touching the
    /// most changes first. Only dependencies with a change at one end or both are drawn, since those
    /// are the ones a change can break; removed types are gone from the interface, so they are not
    /// drawn.
    public func changesFigure(_ diff: InterfaceDiff, minimumRank: Int, budget: Int = mapBudget) -> ChangesFigure {
        let shown = { (id: String) in self.byID[id].map { self.rank(of: $0) >= minimumRank } ?? false }
        let position = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.from, default: 0] += 1
            degree[edge.to, default: 0] += 1
        }
        func ranked(_ ids: [String], by score: (String) -> Int) -> [String] {
            ids.sorted { (-score($0), position[$0] ?? 0) < (-score($1), position[$1] ?? 0) }
        }

        var changed = diff.nodes.filter { $0.change != .removed }.map(\.node.id).filter(shown)
        var overflow: [String] = []
        if changed.count > budget {
            let kept = Set(ranked(changed) { degree[$0] ?? 0 }.prefix(budget))
            overflow = ranked(changed.filter { !kept.contains($0) }) { degree[$0] ?? 0 }
            changed = changed.filter(kept.contains)
        }
        let changedSet = Set(changed)
        var touches: [String: Int] = [:]
        for edge in edges {
            let fromChanged = changedSet.contains(edge.from)
            let toChanged = changedSet.contains(edge.to)
            if fromChanged, !toChanged, shown(edge.to) { touches[edge.to, default: 0] += 1 }
            if toChanged, !fromChanged, shown(edge.from) { touches[edge.from, default: 0] += 1 }
        }
        let neighbors = ranked(Array(touches.keys)) { touches[$0] ?? 0 }
        let room = overflow.isEmpty ? max(budget - changed.count, 0) : 0
        let around = Array(neighbors.prefix(room))
        overflow += neighbors.dropFirst(room)

        let drawn = changed + around.sorted { (position[$0] ?? 0) < (position[$1] ?? 0) }
        let drawnSet = Set(drawn)
        let items = drawn.compactMap { id -> GraphLayout.Item? in
            guard let node = byID[id] else { return nil }
            var flags: GraphLayout.Flags = []
            if findings(under: id) > 0 { flags.insert(.dirty) }
            if rank(of: node) == 0 { flags.insert(.private) }
            return GraphLayout.Item(unit: .type(id), label: label(node), detail: Wording.kind(of: node), flags: flags, group: node.module)
        }
        let links = edges.filter { edge in
            drawnSet.contains(edge.from) && drawnSet.contains(edge.to) && (changedSet.contains(edge.from) || changedSet.contains(edge.to))
        }.map { edge in
            GraphLayout.Link(from: edge.from, to: edge.to, dashed: edge.roles == [.body],
                             title: "\(label(of: .type(edge.from))) \(Wording.words(edge.roles)) \(label(of: .type(edge.to)))")
        }
        return ChangesFigure(layout: GraphLayout.layered(items, links), changed: changed.count, around: around.count, overflow: overflow)
    }
}

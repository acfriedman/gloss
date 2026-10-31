import GlossCore

/// The map's narrowest level: one type with only what uses it, above, and what it depends on, below.
public struct Focus: Sendable {
    public var layout: GraphLayout
    /// How many types use it and how many it depends on, after the filters and before the cap.
    public var incoming: Int
    public var outgoing: Int
    /// How many of those are past the cap and not drawn.
    public var hidden: Int
}

extension Atlas {
    /// The most neighbors drawn on each side of a focused type.
    public static let focusCap = 24

    /// Lays out one type and its direct neighbors, signature dependencies first on each side.
    ///
    /// - Parameters:
    ///   - id: The node to focus on; any node, nested or not.
    ///   - includeBody: `true` to include neighbors linked only inside bodies.
    ///   - minimumRank: The narrowest access, as ``GlossCore/Contract/rank(_:)``, a neighbor needs to be drawn.
    /// - Returns: The figure, or `nil` for an unknown id.
    public func focus(on id: String, includeBody: Bool, minimumRank: Int) -> Focus? {
        guard let node = byID[id] else { return nil }
        let (incoming, outgoing, _) = neighbors(of: node)
        func keep(_ edge: Graph.Edge, other: String) -> Bool {
            guard let other = byID[other] else { return false }
            return (includeBody || edge.roles != [.body]) && rank(of: other) >= minimumRank
        }
        func signatureFirst(_ edges: [Graph.Edge]) -> [Graph.Edge] {
            edges.enumerated().sorted { ($0.element.roles == [.body] ? 1 : 0, $0.offset) < ($1.element.roles == [.body] ? 1 : 0, $1.offset) }.map(\.element)
        }
        let users = signatureFirst(incoming.filter { keep($0, other: $0.from) })
        let needs = signatureFirst(outgoing.filter { keep($0, other: $0.to) })
        func side(_ edges: [Graph.Edge], incoming: Bool) -> [(item: GraphLayout.Item, link: GraphLayout.Link)] {
            edges.prefix(Self.focusCap).compactMap { edge in
                guard let neighbor = byID[incoming ? edge.from : edge.to] else { return nil }
                let words = Wording.words(edge.roles)
                let detail = words + (neighbor.module != node.module ? " · " + neighbor.module : "")
                var flags: GraphLayout.Flags = []
                if group(neighbor.id).findingCount > 0 { flags.insert(.dirty) }
                if rank(of: neighbor) == 0 { flags.insert(.private) }
                let item = GraphLayout.Item(unit: .type(neighbor.id), label: label(neighbor), detail: detail, flags: flags)
                let (from, to) = incoming ? (neighbor, node) : (node, neighbor)
                return (item, GraphLayout.Link(from: from.id, to: to.id, dashed: edge.roles == [.body],
                                               title: "\(label(from)) \(words) \(label(to))"))
            }
        }
        var flags: GraphLayout.Flags = []
        if group(node.id).findingCount > 0 { flags.insert(.dirty) }
        if rank(of: node) == 0 { flags.insert(.private) }
        let center = GraphLayout.Item(unit: .type(node.id), label: label(node), detail: Wording.kind(of: node), flags: flags)
        let layout = GraphLayout.focused(center: center, above: side(users, incoming: true), below: side(needs, incoming: false))
        let hidden = max(0, users.count - Self.focusCap) + max(0, needs.count - Self.focusCap)
        return Focus(layout: layout, incoming: users.count, outgoing: needs.count, hidden: hidden)
    }
}

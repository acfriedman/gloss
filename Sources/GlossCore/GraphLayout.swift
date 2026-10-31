/// Places boxes and edge curves for the page's dependency map, top to bottom.
///
/// Layout runs in Swift, not in the browser, so a figure is fixed SVG: it renders without script and
/// the same graph always yields the same drawing.
struct GraphLayout {
    /// A node to place: its link target, text, and any CSS classes.
    struct Item {
        var id: String
        var label: String
        var detail: String
        var link: String
        var classes: String = ""
    }

    /// A dependency to draw from one item to another.
    struct Link {
        var from: String
        var to: String
        var dashed: Bool
        var title: String
    }

    /// A placed box, in SVG user units.
    struct Box {
        var item: Item
        var x: Double
        var y: Double
        var width: Double
    }

    /// A drawn edge; `reversed` puts the arrowhead at the start, for an edge drawn against the flow.
    struct Curve {
        var link: Link
        var path: String
        var reversed: Bool
    }

    var boxes: [Box] = []
    var curves: [Curve] = []
    var width = 0.0
    var height = 0.0

    static let boxHeight = 38.0
    static let margin = 6.0

    /// The width a box needs for its text, from the monospace label and the smaller detail line.
    ///
    /// - Parameter item: The item to measure.
    /// - Returns: The box width in user units.
    static func width(of item: Item) -> Double {
        max(Double(item.label.count) * 7.3, Double(item.detail.count) * 6.0) + 24
    }

    private enum Slot: Hashable {
        case node(Int)
        case dummy(edge: Int, layer: Int)
    }

    /// Lays out a whole graph in layers, so every edge points downward except those that close a cycle.
    /// Edges spanning several layers pass through placeholder slots, which keeps them out of boxes.
    ///
    /// - Parameters:
    ///   - items: The nodes, in a stable order that seeds the ordering within each layer.
    ///   - links: The edges; a link naming an unknown item or its own source is dropped.
    /// - Returns: The placed figure.
    ///
    /// Cycles are broken by reversing the back edges of a depth-first search, layers come from the
    /// longest path from a source, and order within a layer from repeated barycenter sweeps.
    static func layered(_ items: [Item], _ links: [Link]) -> GraphLayout {
        let count = items.count
        var position: [String: Int] = [:]
        for (index, item) in items.enumerated() { position[item.id] = index }
        let edges: [(from: Int, to: Int, link: Link)] = links.compactMap { link in
            guard let from = position[link.from], let to = position[link.to], from != to else { return nil }
            return (from, to, link)
        }

        var outgoing = Array(repeating: [Int](), count: count)
        for edge in edges { outgoing[edge.from].append(edge.to) }
        var state = Array(repeating: 0, count: count)
        var backEdges = Set<[Int]>()
        func search(_ node: Int) {
            state[node] = 1
            for next in outgoing[node] {
                if state[next] == 1 { backEdges.insert([node, next]) } else if state[next] == 0 { search(next) }
            }
            state[node] = 2
        }
        for node in 0..<count where state[node] == 0 { search(node) }
        let flow = edges.map { edge in
            backEdges.contains([edge.from, edge.to]) ? (low: edge.to, high: edge.from, reversed: true) : (low: edge.from, high: edge.to, reversed: false)
        }

        var layer = Array(repeating: 0, count: count)
        var indegree = Array(repeating: 0, count: count)
        var successors = Array(repeating: [Int](), count: count)
        for edge in flow {
            successors[edge.low].append(edge.high)
            indegree[edge.high] += 1
        }
        var queue = (0..<count).filter { indegree[$0] == 0 }
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for next in successors[node] {
                layer[next] = max(layer[next], layer[node] + 1)
                indegree[next] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }

        // A source sits right above its nearest dependency instead of in the top row, which keeps the
        // edges of a leaf-level consumer short.
        var hasPredecessor = Array(repeating: false, count: count)
        for edge in flow { hasPredecessor[edge.high] = true }
        for node in 0..<count where !hasPredecessor[node] {
            if let nearest = successors[node].map({ layer[$0] }).min() { layer[node] = nearest - 1 }
        }
        let lowest = layer.min() ?? 0
        layer = layer.map { $0 - lowest }

        let layerCount = (layer.max() ?? 0) + 1
        var slots = Array(repeating: [Slot](), count: layerCount)
        for node in 0..<count { slots[layer[node]].append(.node(node)) }
        var chains: [[Slot]] = []
        var above: [Slot: [Slot]] = [:]
        var below: [Slot: [Slot]] = [:]
        for (index, edge) in flow.enumerated() {
            var chain: [Slot] = [.node(edge.low)]
            for middle in stride(from: layer[edge.low] + 1, to: layer[edge.high], by: 1) {
                let slot = Slot.dummy(edge: index, layer: middle)
                slots[middle].append(slot)
                chain.append(slot)
            }
            chain.append(.node(edge.high))
            for (upper, lower) in zip(chain, chain.dropFirst()) {
                below[upper, default: []].append(lower)
                above[lower, default: []].append(upper)
            }
            chains.append(chain)
        }

        var rank: [Slot: Double] = [:]
        func renumber(_ index: Int) {
            for (offset, slot) in slots[index].enumerated() { rank[slot] = Double(offset) }
        }
        func reorder(_ index: Int, by neighbors: [Slot: [Slot]]) {
            let keyed = slots[index].enumerated().map { offset, slot -> (slot: Slot, key: Double, offset: Int) in
                let around = (neighbors[slot] ?? []).compactMap { rank[$0] }
                let key = around.isEmpty ? rank[slot] ?? Double(offset) : around.reduce(0, +) / Double(around.count)
                return (slot, key, offset)
            }
            slots[index] = keyed.sorted { ($0.key, $0.offset) < ($1.key, $1.offset) }.map(\.slot)
            renumber(index)
        }
        for index in 0..<layerCount { renumber(index) }
        for _ in 0..<12 {
            for index in stride(from: 1, to: layerCount, by: 1) { reorder(index, by: above) }
            for index in stride(from: layerCount - 2, through: 0, by: -1) { reorder(index, by: below) }
        }

        // Layers are rows, top to bottom: a deep graph grows down the page, which scrolls, not sideways.
        let dummyWidth = 8.0
        let slotGap = 18.0
        let layerGap = 54.0
        func slotWidth(_ slot: Slot) -> Double {
            if case .node(let node) = slot { return width(of: items[node]) }
            return dummyWidth
        }
        let rowWidths = slots.map { row in
            row.map(slotWidth).reduce(0, +) + slotGap * Double(max(row.count - 1, 0))
        }
        let widest = rowWidths.max() ?? 0

        var layout = GraphLayout()
        var anchors: [Slot: (x: Double, top: Double, bottom: Double)] = [:]
        for index in 0..<layerCount {
            let top = margin + Double(index) * (boxHeight + layerGap)
            var x = margin + (widest - rowWidths[index]) / 2
            for slot in slots[index] {
                let slotWidth = slotWidth(slot)
                if case .node(let node) = slot {
                    layout.boxes.append(Box(item: items[node], x: x, y: top, width: slotWidth))
                }
                anchors[slot] = (x + slotWidth / 2, top, top + boxHeight)
                x += slotWidth + slotGap
            }
        }
        for (index, chain) in chains.enumerated() {
            let points = chain.compactMap { anchors[$0] }
            layout.curves.append(Curve(link: edges[index].link, path: downward(through: points), reversed: flow[index].reversed))
        }
        layout.width = widest + margin * 2
        layout.height = Double(layerCount) * boxHeight + Double(layerCount - 1) * layerGap + margin * 2
        return layout
    }

    /// An SVG path leaving each point's bottom and entering the next point's top, with vertical tangents,
    /// for the top-to-bottom map.
    ///
    /// - Parameter points: Anchors in flow order; a placeholder is crossed from its top to its bottom.
    /// - Returns: Path data for the `d` attribute.
    static func downward(through points: [(x: Double, top: Double, bottom: Double)]) -> String {
        guard let first = points.first else { return "" }
        var data = "M\(format(first.x)),\(format(first.bottom))"
        var previous = first
        for (index, point) in points.enumerated().dropFirst() {
            let bend = (point.top - previous.bottom) / 2
            data += " C\(format(previous.x)),\(format(previous.bottom + bend)) \(format(point.x)),\(format(point.top - bend)) \(format(point.x)),\(format(point.top))"
            if index < points.count - 1 { data += " L\(format(point.x)),\(format(point.bottom))" }
            previous = point
        }
        return data
    }

    /// Prints a coordinate with at most one decimal, which keeps the SVG small and its bytes stable.
    ///
    /// - Parameter value: A coordinate.
    /// - Returns: `12` or `12.5`.
    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

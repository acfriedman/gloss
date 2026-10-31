/// Places boxes and edge curves for a dependency map, top to bottom.
///
/// Layout runs once, in Swift, for every front end: the page draws it as fixed SVG that renders
/// without script, the app draws the same boxes and curves, and the same graph always yields the same
/// drawing.
public struct GraphLayout: Sendable, Equatable {
    /// How a box is drawn, beyond its text.
    public struct Flags: OptionSet, Sendable, Equatable {
        public let rawValue: Int

        /// Wraps a raw value.
        ///
        /// - Parameter rawValue: The bits.
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The type, or something nested in it, has findings.
        public static let dirty = Flags(rawValue: 1)
        /// The type is private or file-private.
        public static let `private` = Flags(rawValue: 2)
        /// The box stands for a module or a folder, not a type.
        public static let scope = Flags(rawValue: 4)
        /// The box lies outside the level drawn, and steps into its own.
        public static let boundary = Flags(rawValue: 8)
    }

    /// A box to place: what it stands for, its text, and how it is drawn.
    public struct Item: Sendable, Equatable {
        public var unit: MapScope.Unit
        public var label: String
        public var detail: String
        public var flags: Flags = []
        /// The id links name the box by.
        public var id: String { unit.id }

        /// Describes a box.
        ///
        /// - Parameters:
        ///   - unit: The type, module, or folder it stands for.
        ///   - label: Its name.
        ///   - detail: The smaller line under the name.
        ///   - flags: How it is drawn.
        public init(unit: MapScope.Unit, label: String, detail: String, flags: Flags = []) {
            self.unit = unit
            self.label = label
            self.detail = detail
            self.flags = flags
        }
    }

    /// A dependency to draw from one item to another.
    public struct Link: Sendable, Equatable {
        public var from: String
        public var to: String
        public var dashed: Bool
        public var title: String

        /// Describes an edge.
        ///
        /// - Parameters:
        ///   - from: The id of the dependent box.
        ///   - to: The id of the box it depends on.
        ///   - dashed: `true` for a dependency used only inside bodies.
        ///   - title: The edge read as a sentence, for a tooltip.
        public init(from: String, to: String, dashed: Bool, title: String) {
            self.from = from
            self.to = to
            self.dashed = dashed
            self.title = title
        }
    }

    /// A placed box, in points from the figure's top left.
    public struct Box: Sendable, Equatable {
        public var item: Item
        public var x: Double
        public var y: Double
        public var width: Double
    }

    /// Where an edge passes a row: the column it runs in, and the top and bottom it enters and leaves by.
    public struct Anchor: Sendable, Equatable {
        public var x: Double
        public var top: Double
        public var bottom: Double
    }

    /// A drawn edge through its anchors in flow order; `reversed` puts the arrowhead at the start, for
    /// an edge drawn against the flow.
    public struct Curve: Sendable, Equatable {
        public var link: Link
        public var points: [Anchor]
        public var reversed: Bool
        /// The curve as SVG path data.
        public var path: String { GraphLayout.downward(through: points) }
    }

    public var boxes: [Box] = []
    public var curves: [Curve] = []
    public var width = 0.0
    public var height = 0.0

    /// An empty figure, which layouts start from.
    public init() {}

    public static let boxHeight = 38.0
    /// The widest a row of the map may grow before a layer wraps.
    public static let maxRowWidth = 960.0
    public static let margin = 6.0

    /// The width a box needs for its text, from the monospace label and the smaller detail line.
    ///
    /// - Parameter item: The item to measure.
    /// - Returns: The box width in points.
    public static func width(of item: Item) -> Double {
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
    public static func layered(_ items: [Item], _ links: [Link]) -> GraphLayout {
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
        // A crowded layer wraps onto extra rows, so the figure stays narrow enough to read at its own size.
        let wrapGap = 14.0
        var rows: [[[Slot]]] = []
        for layer in slots {
            var wrapped: [[Slot]] = [[]]
            var used = 0.0
            for slot in layer {
                let needed = slotWidth(slot) + (wrapped[wrapped.count - 1].isEmpty ? 0 : slotGap)
                if used + needed > maxRowWidth, !wrapped[wrapped.count - 1].isEmpty {
                    wrapped.append([])
                    used = 0
                }
                used += wrapped[wrapped.count - 1].isEmpty ? slotWidth(slot) : needed
                wrapped[wrapped.count - 1].append(slot)
            }
            rows.append(wrapped)
        }
        func rowWidth(_ row: [Slot]) -> Double {
            row.map(slotWidth).reduce(0, +) + slotGap * Double(max(row.count - 1, 0))
        }
        let widest = rows.flatMap { $0 }.map(rowWidth).max() ?? 0

        var layout = GraphLayout()
        var anchors: [Slot: Anchor] = [:]
        var top = margin
        for layer in rows {
            for row in layer {
                var x = margin + (widest - rowWidth(row)) / 2
                for slot in row {
                    let slotWidth = slotWidth(slot)
                    if case .node(let node) = slot {
                        layout.boxes.append(Box(item: items[node], x: x, y: top, width: slotWidth))
                    }
                    anchors[slot] = Anchor(x: x + slotWidth / 2, top: top, bottom: top + boxHeight)
                    x += slotWidth + slotGap
                }
                top += boxHeight + wrapGap
            }
            top += layerGap - wrapGap
        }
        for (index, chain) in chains.enumerated() {
            let points = chain.compactMap { anchors[$0] }
            layout.curves.append(Curve(link: edges[index].link, points: points, reversed: flow[index].reversed))
        }
        layout.width = widest + margin * 2
        layout.height = top - layerGap + margin
        return layout
    }

    /// Lays out one box with the boxes that use it in rows above and the boxes it depends on in rows
    /// below. Each edge enters or leaves the center box at its own point, spread across its width.
    ///
    /// - Parameters:
    ///   - center: The box in the middle.
    ///   - above: Boxes that depend on the center, each with its edge, in order.
    ///   - below: Boxes the center depends on, each with its edge, in order.
    /// - Returns: The placed figure.
    public static func focused(center: Item, above: [(item: Item, link: Link)], below: [(item: Item, link: Link)]) -> GraphLayout {
        let slotGap = 18.0
        let wrapGap = 14.0
        let sideGap = 40.0
        let rowLimit = 900.0
        func rows(_ side: [(item: Item, link: Link)]) -> [[(item: Item, link: Link)]] {
            var rows: [[(item: Item, link: Link)]] = []
            var used = 0.0
            for entry in side {
                let width = width(of: entry.item)
                if let last = rows.last, !last.isEmpty, used + slotGap + width <= rowLimit {
                    rows[rows.count - 1].append(entry)
                    used += slotGap + width
                } else {
                    rows.append([entry])
                    used = width
                }
            }
            return rows
        }
        func rowWidth(_ row: [(item: Item, link: Link)]) -> Double {
            row.map { width(of: $0.item) }.reduce(0, +) + slotGap * Double(max(row.count - 1, 0))
        }
        let upper = rows(above)
        let lower = rows(below)
        let centerWidth = width(of: center)
        let inner = max(centerWidth, (upper + lower).map(rowWidth).max() ?? 0)

        var layout = GraphLayout()
        var y = margin
        func place(_ row: [(item: Item, link: Link)]) -> [Box] {
            var x = margin + (inner - rowWidth(row)) / 2
            let boxes = row.map { entry -> Box in
                let box = Box(item: entry.item, x: x, y: y, width: width(of: entry.item))
                x += box.width + slotGap
                return box
            }
            y += boxHeight + wrapGap
            return boxes
        }
        let placedAbove = upper.flatMap(place)
        if !upper.isEmpty { y += sideGap }
        let middle = place([(center, Link(from: "", to: "", dashed: false, title: ""))])[0]
        if !lower.isEmpty { y += sideGap }
        let placedBelow = lower.flatMap(place)
        layout.boxes = placedAbove + [middle] + placedBelow

        func spread(_ index: Int, _ count: Int) -> Double {
            middle.x + Double(index + 1) * middle.width / Double(count + 1)
        }
        func anchor(_ box: Box, x: Double? = nil) -> Anchor {
            Anchor(x: x ?? box.x + box.width / 2, top: box.y, bottom: box.y + boxHeight)
        }
        for (index, (box, entry)) in zip(placedAbove, above).enumerated() {
            layout.curves.append(Curve(link: entry.link, points: [anchor(box), anchor(middle, x: spread(index, placedAbove.count))], reversed: false))
        }
        for (index, (box, entry)) in zip(placedBelow, below).enumerated() {
            layout.curves.append(Curve(link: entry.link, points: [anchor(middle, x: spread(index, placedBelow.count)), anchor(box)], reversed: false))
        }
        layout.width = inner + margin * 2
        layout.height = y - wrapGap + margin
        return layout
    }

    /// An SVG path leaving each point's bottom and entering the next point's top, with vertical tangents,
    /// for the top-to-bottom map.
    ///
    /// - Parameter points: Anchors in flow order; a placeholder is crossed from its top to its bottom.
    /// - Returns: Path data for the `d` attribute.
    public static func downward(through points: [Anchor]) -> String {
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
    public static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

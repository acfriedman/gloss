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
        /// The type, module, or folder the box stands for, which also gives it its id.
        public var unit: MapScope.Unit
        /// The name on the box's first line: a type's label, a module name, or a folder label.
        public var label: String
        /// The smaller line under the name, such as a type's kind and module or a folder's type count.
        public var detail: String
        /// How the box is drawn; empty for a plain box.
        public var flags: Flags = []
        /// The lane the box belongs in, such as its module; `nil` keeps the figure without lanes.
        public var group: String?
        /// The id links name the box by.
        public var id: String { unit.id }

        /// Describes a box.
        ///
        /// - Parameters:
        ///   - unit: The type, module, or folder it stands for.
        ///   - label: Its name.
        ///   - detail: The smaller line under the name.
        ///   - flags: How it is drawn.
        ///   - group: The lane it belongs in, such as its module, or `nil` for none.
        public init(unit: MapScope.Unit, label: String, detail: String, flags: Flags = [], group: String? = nil) {
            self.unit = unit
            self.label = label
            self.detail = detail
            self.flags = flags
            self.group = group
        }
    }

    /// A dependency to draw from one item to another.
    public struct Link: Sendable, Equatable {
        /// The id of the dependent box.
        public var from: String
        /// The id of the box it depends on.
        public var to: String
        /// `true` for a dependency used only inside bodies, which is drawn dashed.
        public var dashed: Bool
        /// The edge read as a sentence, such as `Atlas holds Graph`, for a tooltip.
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
        /// The item the box draws.
        public var item: Item
        /// The box's left edge.
        public var x: Double
        /// The box's top edge; its height is always ``GraphLayout/boxHeight``.
        public var y: Double
        /// The box's width, from ``GraphLayout/width(of:)``.
        public var width: Double
    }

    /// Where an edge passes a row: the column it runs in, and the top and bottom it enters and leaves by.
    public struct Anchor: Sendable, Equatable {
        /// The column the edge runs in: a box's center, a point spread across a focused box, or a
        /// placeholder's center.
        public var x: Double
        /// Where the edge enters the row: the box's top edge, or the row's for a placeholder.
        public var top: Double
        /// Where the edge leaves the row, ``GraphLayout/boxHeight`` below ``top``.
        public var bottom: Double
    }

    /// A drawn edge through its anchors in flow order; `reversed` puts the arrowhead at the start, for
    /// an edge drawn against the flow.
    public struct Curve: Sendable, Equatable {
        /// The dependency the curve draws.
        public var link: Link
        /// The anchors from the upper end to the lower: a box at each end, with a placeholder for each
        /// layer the edge crosses between them.
        public var points: [Anchor]
        /// `true` for an edge that closes a cycle and so runs up against the flow; its points still run
        /// downward, so its arrowhead goes at the first one.
        public var reversed: Bool
        /// The curve as SVG path data.
        public var path: String { GraphLayout.downward(through: points) }
    }

    /// A column that holds one group's boxes, such as a module's, drawn as a subtle container behind them.
    public struct Lane: Sendable, Equatable {
        /// The group's name, shown at the container's top.
        public var name: String
        /// The container's left edge, in points from the figure's left.
        public var x: Double
        /// The container's top edge, its label included.
        public var y: Double
        /// The container's width.
        public var width: Double
        /// The container's height.
        public var height: Double
        /// Whether the lane holds what the figure is about, such as the focused type's module.
        public var isEmphasized: Bool
    }

    /// The placed boxes, row by row from the top.
    public var boxes: [Box] = []
    /// The group containers, left to right; empty unless the figure's boxes span two or more groups.
    public var lanes: [Lane] = []
    /// The placed edges, one per link that was kept.
    public var curves: [Curve] = []
    /// The figure's width in points, margins included.
    public var width = 0.0
    /// The figure's height in points, margins included.
    public var height = 0.0

    /// An empty figure, which layouts start from.
    public init() {}

    /// The height of every box, in points; a placeholder takes the same height in its row.
    public static let boxHeight = 38.0
    /// The widest a row of the map may grow before a layer wraps.
    public static let maxRowWidth = 960.0
    /// The space left clear on each side of the figure, in points.
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
    ///   - emphasis: The group whose lane holds what the figure is about, drawn a little warmer.
    ///   - splitAt: The id of the item the figure grows from, such as a focused type; when lanes are
    ///     drawn, the rows above it, its own row, and the rows below it each get lanes of their own.
    /// - Returns: The placed figure.
    ///
    /// Cycles are broken by reversing the back edges of a depth-first search, layers come from the
    /// longest path from a source, and order within a layer from repeated barycenter sweeps. When every
    /// item has a group and there are two or more, each group keeps to a lane of its own on every row,
    /// lanes in the order the sweeps placed their boxes on average, and an edge's placeholders run down
    /// its source's lane. Split at an item, the figure is three bands stacked and centered, each laid
    /// out in lanes for only the groups it holds, so a group on both sides gets a container on each.
    public static func layered(_ items: [Item], _ links: [Link], emphasis: String? = nil,
                               splitAt: String? = nil) -> GraphLayout {
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

        let groups = items.map(\.group)
        if groups.allSatisfy({ $0 != nil }), Set(groups.compactMap { $0 }).count > 1 {
            let groupOf = { (slot: Slot) -> String in
                switch slot {
                case .node(let node): items[node].group ?? ""
                case .dummy(let edge, _): items[flow[edge].low].group ?? ""
                }
            }
            var bands = [0..<layerCount]
            if let splitAt, let index = position[splitAt] {
                let middle = layer[index]
                bands = [0..<middle, middle..<middle + 1, middle + 1..<layerCount].filter { !$0.isEmpty }
            }
            return lanes(items, slots: slots, bands: bands, chains: chains, edges: edges.map(\.link),
                         reversed: flow.map(\.reversed), groupOf: groupOf, emphasis: emphasis)
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

    /// Places ordered layers in group lanes, band by band: in each band, each group a column as wide as
    /// its widest row there, its boxes kept inside it on every row, and a container drawn behind them.
    ///
    /// - Parameters:
    ///   - items: The nodes.
    ///   - slots: Each layer's slots, nodes and edge placeholders, in swept order.
    ///   - bands: Consecutive runs of layers that each get lanes of their own, top to bottom.
    ///   - chains: Each edge's slots from its upper end to its lower end.
    ///   - edges: Each edge's link, at the same index as its chain.
    ///   - reversed: Whether each edge is drawn against the flow, at the same index.
    ///   - groupOf: The lane each slot belongs in.
    ///   - emphasis: The group whose lanes are drawn a little warmer.
    /// - Returns: The placed figure with its lanes.
    private static func lanes(_ items: [Item], slots: [[Slot]], bands: [Range<Int>], chains: [[Slot]], edges: [Link],
                              reversed: [Bool], groupOf: (Slot) -> String, emphasis: String?) -> GraphLayout {
        let dummyWidth = 8.0
        let slotGap = 18.0
        let layerGap = 54.0
        let wrapGap = 14.0
        let laneLimit = maxRowWidth / 2
        let padding = 12.0
        let laneGap = 16.0
        let labelHeight = 18.0
        func slotWidth(_ slot: Slot) -> Double {
            if case .node(let node) = slot { return width(of: items[node]) }
            return dummyWidth
        }
        func rowWidth(_ row: [Slot]) -> Double {
            row.map(slotWidth).reduce(0, +) + slotGap * Double(max(row.count - 1, 0))
        }

        /// One band's plan: its lanes in order, each layer's rows by lane, and where each lane sits.
        struct Band {
            var order: [String] = []
            var rows: [[String: [[Slot]]]] = []
            var laneWidth: [String: Double] = [:]
            var laneX: [String: Double] = [:]
            var width = 0.0
        }
        var planned: [Band] = []
        for range in bands {
            var band = Band()
            // Lanes go in the order the sweeps placed their slots on average, which keeps crossings low.
            var positions: [String: [Double]] = [:]
            for layer in slots[range] {
                for (offset, slot) in layer.enumerated() {
                    positions[groupOf(slot), default: []].append((Double(offset) + 0.5) / Double(layer.count))
                }
            }
            band.order = positions.map { (name: $0.key, mean: $0.value.reduce(0, +) / Double($0.value.count)) }
                .sorted { ($0.mean, $0.name) < ($1.mean, $1.name) }.map(\.name)
            let rank = Dictionary(uniqueKeysWithValues: band.order.enumerated().map { ($0.element, $0.offset) })
            // Each layer, each lane: its slots in swept order, wrapped onto rows no wider than the lane limit.
            for layer in slots[range] {
                var byLane: [String: [[Slot]]] = [:]
                let ordered = layer.enumerated().sorted {
                    (rank[groupOf($0.element)] ?? 0, $0.offset) < (rank[groupOf($1.element)] ?? 0, $1.offset)
                }.map(\.element)
                for slot in ordered {
                    let lane = groupOf(slot)
                    var wrapped = byLane[lane] ?? [[]]
                    let current = wrapped[wrapped.count - 1]
                    if !current.isEmpty, rowWidth(current + [slot]) > laneLimit { wrapped.append([]) }
                    wrapped[wrapped.count - 1].append(slot)
                    byLane[lane] = wrapped
                }
                band.rows.append(byLane)
            }
            for layer in band.rows {
                for (lane, wrapped) in layer { band.laneWidth[lane] = max(band.laneWidth[lane] ?? 0, wrapped.map(rowWidth).max() ?? 0) }
            }
            var x = 0.0
            for lane in band.order {
                band.laneX[lane] = x + padding
                x += padding + (band.laneWidth[lane] ?? 0) + padding + laneGap
            }
            band.width = max(x - laneGap, 0)
            planned.append(band)
        }
        let widest = planned.map(\.width).max() ?? 0

        var layout = GraphLayout()
        var anchors: [Slot: Anchor] = [:]
        var top = margin + labelHeight + padding
        for (index, band) in planned.enumerated() {
            let offset = margin + (widest - band.width) / 2
            let first = layout.boxes.count
            for layer in band.rows {
                let height = layer.values.map(\.count).max() ?? 1
                for (lane, wrapped) in layer {
                    for (row, slotsInRow) in wrapped.enumerated() {
                        let y = top + Double(row) * (boxHeight + wrapGap)
                        var left = offset + (band.laneX[lane] ?? 0) + ((band.laneWidth[lane] ?? 0) - rowWidth(slotsInRow)) / 2
                        for slot in slotsInRow {
                            let slotWidth = slotWidth(slot)
                            if case .node(let node) = slot { layout.boxes.append(Box(item: items[node], x: left, y: y, width: slotWidth)) }
                            anchors[slot] = Anchor(x: left + slotWidth / 2, top: y, bottom: y + boxHeight)
                            left += slotWidth + slotGap
                        }
                    }
                }
                top += Double(height) * (boxHeight + wrapGap) - wrapGap + layerGap
            }
            let bandBoxes = layout.boxes[first...]
            for lane in band.order {
                let boxes = bandBoxes.filter { $0.item.group == lane }
                guard let firstY = boxes.map(\.y).min(), let lastY = boxes.map(\.y).max(), let left = band.laneX[lane] else { continue }
                layout.lanes.append(Lane(name: lane, x: offset + left - padding, y: firstY - labelHeight - padding,
                                         width: (band.laneWidth[lane] ?? 0) + padding * 2,
                                         height: lastY + boxHeight + padding - (firstY - labelHeight - padding),
                                         isEmphasized: lane == emphasis))
            }
            if index < planned.count - 1 { top += labelHeight + padding }
        }
        layout.boxes.sort { ($0.y, $0.x) < ($1.y, $1.x) }
        for (index, chain) in chains.enumerated() {
            layout.curves.append(Curve(link: edges[index], points: chain.compactMap { anchors[$0] }, reversed: reversed[index]))
        }
        layout.width = widest + margin * 2
        layout.height = top - layerGap + padding + margin
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

import LucidRead
import GlossModel

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
    ///     drawn, its rows are split into bands with lanes of their own wherever that saves width.
    /// - Returns: The placed figure.
    ///
    /// Cycles are broken by reversing the back edges of a depth-first search, layers come from the
    /// longest path from a source, and order within a layer from repeated barycenter sweeps. When every
    /// item has a group and there are two or more, each group keeps to a lane of its own on every row,
    /// lanes in the order the sweeps placed their boxes on average, and an edge's placeholders run down
    /// its source's lane. Split at an item, the figure is bands of rows stacked and centered, each laid
    /// out in lanes for only the groups it holds, so a group on both sides of the item can get a
    /// container on each. Splitting only stays where it saves width: two neighboring bands merge when a
    /// group continues across the rows where they meet and the merged band is no wider than the widest
    /// band, and within a band, lanes whose rows never meet can stack in one column.
    public static func layered(_ items: [Item], _ links: [Link], emphasis: String? = nil,
                               splitAt: String? = nil) -> GraphLayout {
        let phase = Timing.begin("layout"); defer { Timing.end(phase, "\(items.count) boxes, \(links.count) links") }
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
            // Split at an item, every row starts as a band of its own and merges back where splitting buys
            // nothing; otherwise the figure is one band.
            let split = splitAt.flatMap { position[$0] } != nil
            let bands = split ? (0..<layerCount).map { $0..<$0 + 1 } : [0..<layerCount]
            return lanes(items, slots: slots, bands: bands, merging: split, anchor: split ? splitAt.flatMap { position[$0] } : nil,
                         chains: chains, edges: edges.map(\.link), reversed: flow.map(\.reversed), groupOf: groupOf, emphasis: emphasis)
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

    /// Places ordered layers in group lanes, band by band: in each band, each group a lane as wide as its
    /// widest row there, its boxes kept inside it on every row, and a container drawn behind them.
    ///
    /// - Parameters:
    ///   - items: The nodes.
    ///   - slots: Each layer's slots, nodes and edge placeholders, in swept order.
    ///   - bands: Consecutive runs of layers that each get lanes of their own, top to bottom.
    ///   - merging: `true` to merge neighboring bands where that joins a group's containers without
    ///     widening the figure.
    ///   - anchor: The index of the item the figure grows from, which the lanes center on, lanes whose
    ///     rows never meet stacking in one column where that is no wider; `nil` orders lanes by the sweeps,
    ///     one column each, and centers each band on its own.
    ///   - chains: Each edge's slots from its upper end to its lower end.
    ///   - edges: Each edge's link, at the same index as its chain.
    ///   - reversed: Whether each edge is drawn against the flow, at the same index.
    ///   - groupOf: The lane each slot belongs in.
    ///   - emphasis: The group whose lanes are drawn a little warmer.
    /// - Returns: The placed figure with its lanes.
    private static func lanes(_ items: [Item], slots: [[Slot]], bands: [Range<Int>], merging: Bool, anchor: Int?,
                              chains: [[Slot]], edges: [Link], reversed: [Bool], groupOf: (Slot) -> String,
                              emphasis: String?) -> GraphLayout {
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
            /// The center of the band's middle column, from the band's left edge, which a figure grown from
            /// an anchor lines up across bands.
            var axis = 0.0
        }

        // How strongly each group connects to the anchor: the edges between the anchor and its boxes.
        var pull: [String: Int] = [:]
        if let anchor {
            for chain in chains {
                guard case .node(let upper)? = chain.first, case .node(let lower)? = chain.last else { continue }
                if upper == anchor, let group = items[lower].group { pull[group, default: 0] += 1 }
                if lower == anchor, let group = items[upper].group { pull[group, default: 0] += 1 }
            }
        }
        let anchorGroup = anchor.flatMap { items[$0].group }
        /// Plans one band: its lanes' rows and widths, then their order and positions.
        ///
        /// - Parameters:
        ///   - range: The layers the band holds.
        ///   - reach: How far the bands already placed reach left and right of the axis; with an anchor,
        ///     each lane goes on the side that keeps the whole figure narrowest.
        /// - Returns: The band's plan.
        func plan(_ range: Range<Int>, around reach: (left: Double, right: Double) = (0, 0)) -> Band {
            var band = Band()
            // The sweeps' average placement orders lanes when nothing anchors them, and breaks ties when
            // something does.
            var positions: [String: [Double]] = [:]
            for layer in slots[range] {
                for (offset, slot) in layer.enumerated() {
                    positions[groupOf(slot), default: []].append((Double(offset) + 0.5) / Double(layer.count))
                }
            }
            let swept = positions.map { (name: $0.key, mean: $0.value.reduce(0, +) / Double($0.value.count)) }
                .sorted { ($0.mean, $0.name) < ($1.mean, $1.name) }.map(\.name)
            let sweptRank = Dictionary(uniqueKeysWithValues: swept.enumerated().map { ($0.element, $0.offset) })
            // Each layer, each lane: its slots in swept order, wrapped onto rows no wider than the lane limit.
            for layer in slots[range] {
                var byLane: [String: [[Slot]]] = [:]
                for slot in layer {
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

            let full = { (lane: String) in (band.laneWidth[lane] ?? 0) + padding * 2 }
            // Each lane's rows in the band, first to last; lanes whose rows never meet can stack in one column.
            var span: [String: ClosedRange<Int>] = [:]
            for (row, layer) in band.rows.enumerated() {
                for lane in layer.keys { span[lane] = span[lane].map { min($0.lowerBound, row)...max($0.upperBound, row) } ?? row...row }
            }
            func meets(_ lane: String, _ column: [String]) -> Bool {
                column.contains { other in span[other].map { span[lane]?.overlaps($0) ?? true } ?? true }
            }

            // Columns left to right, each holding lanes top to bottom.
            var columns = swept.map { [$0] }
            var middle: Int?
            if anchor != nil {
                // Organ-pipe around the anchor: its group in the middle, then the rest by their pull toward
                // it, heaviest nearest, each on the side that keeps the figure narrowest, which keeps edges
                // to the anchor short and the figure balanced. A lane stacks in a column whose lanes it never
                // meets when that costs no more than a column of its own.
                var rest = swept.sorted { (-(pull[$0] ?? 0), sweptRank[$0] ?? 0) < (-(pull[$1] ?? 0), sweptRank[$1] ?? 0) }
                let center = anchorGroup.flatMap { group in rest.firstIndex(of: group).map { rest.remove(at: $0) } }
                    ?? (rest.isEmpty ? nil : rest.removeFirst())
                /// A column being filled: its lanes and the width of the widest.
                struct Column {
                    var lanes: [String]
                    var width: Double
                }
                var mid = Column(lanes: center.map { [$0] } ?? [], width: center.map(full) ?? 0)
                var left: [Column] = []
                var right: [Column] = []
                for lane in rest {
                    let width = full(lane)
                    let leftSpan = mid.width / 2 + left.reduce(0) { $0 + $1.width + laneGap }
                    let rightSpan = mid.width / 2 + right.reduce(0) { $0 + $1.width + laneGap }
                    func cost(_ addLeft: Double, _ addRight: Double) -> Double {
                        max(reach.left, leftSpan + addLeft) + max(reach.right, rightSpan + addRight)
                    }
                    // Candidates in order of preference, so the first of the cheapest wins: the middle, the
                    // columns nearest it, then a column of its own.
                    var choices: [(cost: Double, place: () -> Void)] = []
                    if !meets(lane, mid.lanes) {
                        let grow = max(width - mid.width, 0)
                        choices.append((cost(grow / 2, grow / 2), { mid.lanes.append(lane); mid.width += grow }))
                    }
                    for index in 0..<max(left.count, right.count) {
                        if index < left.count, !meets(lane, left[index].lanes) {
                            let grow = max(width - left[index].width, 0)
                            choices.append((cost(grow, 0), { left[index].lanes.append(lane); left[index].width += grow }))
                        }
                        if index < right.count, !meets(lane, right[index].lanes) {
                            let grow = max(width - right[index].width, 0)
                            choices.append((cost(0, grow), { right[index].lanes.append(lane); right[index].width += grow }))
                        }
                    }
                    let ifLeft = cost(width + laneGap, 0)
                    let ifRight = cost(0, width + laneGap)
                    let newLeft: (cost: Double, place: () -> Void) = (ifLeft, { left.append(Column(lanes: [lane], width: width)) })
                    let newRight: (cost: Double, place: () -> Void) = (ifRight, { right.append(Column(lanes: [lane], width: width)) })
                    choices += ifLeft < ifRight || (ifLeft == ifRight && leftSpan < rightSpan) ? [newLeft, newRight] : [newRight, newLeft]
                    let cheapest = choices.map(\.cost).min() ?? 0
                    choices.first { $0.cost == cheapest }?.place()
                }
                columns = left.reversed().map(\.lanes) + [mid.lanes] + right.map(\.lanes)
                middle = left.count
            }

            var x = 0.0
            for (index, column) in columns.enumerated() {
                let width = column.map(full).max() ?? 0
                for lane in column.sorted(by: { (span[$0]?.lowerBound ?? 0) < (span[$1]?.lowerBound ?? 0) }) {
                    band.order.append(lane)
                    band.laneX[lane] = x + padding + (width - full(lane)) / 2
                }
                if index == middle { band.axis = x + width / 2 }
                x += width + laneGap
            }
            band.width = max(x - laneGap, 0)
            if middle == nil { band.axis = band.width / 2 }
            return band
        }

        // Two neighboring bands merge where that joins containers, a group on both sides of the rows where
        // they meet becoming one lane, and the merged band is no wider than the widest. The merge joining
        // the most goes first, the narrowest among equals. A group the meeting rows lack stays split, so no
        // container spans a row it has nothing on.
        var ranges = bands
        var planned = ranges.map { plan($0) }
        let widest = planned.map(\.width).max() ?? 0
        while merging {
            var best: (index: Int, joined: Int, band: Band)?
            for index in ranges.indices.dropLast() {
                guard let last = planned[index].rows.last, let first = planned[index + 1].rows.first else { continue }
                let shared = Set(planned[index].order).intersection(planned[index + 1].order)
                guard !shared.isEmpty, shared.allSatisfy({ last[$0] != nil && first[$0] != nil }) else { continue }
                let merged = plan(ranges[index].lowerBound..<ranges[index + 1].upperBound)
                guard merged.width <= widest else { continue }
                if let best, (best.joined, -best.band.width) >= (shared.count, -merged.width) { continue }
                best = (index, shared.count, merged)
            }
            guard let best else { break }
            ranges[best.index] = ranges[best.index].lowerBound..<ranges[best.index + 1].upperBound
            ranges.remove(at: best.index + 1)
            planned[best.index] = best.band
            planned.remove(at: best.index + 1)
        }

        // Grown from an anchor, the bands are planned again outward from the anchor's own, each lane on
        // the side that keeps the figure narrowest given the bands already placed.
        if let anchor, let layer = slots.firstIndex(where: { $0.contains(.node(anchor)) }),
           let home = ranges.firstIndex(where: { $0.contains(layer) }) {
            var reach = (left: 0.0, right: 0.0)
            let outward = [home] + (1..<max(ranges.count, 1)).flatMap { [home - $0, home + $0] }.filter(ranges.indices.contains)
            for index in outward {
                planned[index] = plan(ranges[index], around: reach)
                reach.left = max(reach.left, planned[index].axis)
                reach.right = max(reach.right, planned[index].width - planned[index].axis)
            }
        }

        // Grown from an anchor, every band hangs on one vertical axis through it.
        let leftOfAxis = planned.map(\.axis).max() ?? 0
        let rightOfAxis = planned.map { $0.width - $0.axis }.max() ?? 0

        var layout = GraphLayout()
        var anchors: [Slot: Anchor] = [:]
        var top = margin + labelHeight + padding
        for (index, band) in planned.enumerated() {
            let offset = margin + (anchor != nil ? leftOfAxis - band.axis : (widest - band.width) / 2)
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
        layout.width = (anchor != nil ? leftOfAxis + rightOfAxis : widest) + margin * 2
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

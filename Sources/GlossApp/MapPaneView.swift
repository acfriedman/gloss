import LucidRead
import GlossModel
import GlossMap
import SwiftUI

/// The right pane: the dependency map at the current level, with breadcrumbs back to wider levels.
///
/// Each figure opens centered and shrunk to fit the pane, never past its natural size. A pinch or the
/// magnify control zooms from there, and a new figure fits again. The canvas reaches a pane past the
/// figure on every side, so it pans freely as a canvas does, a strip of it always kept in view.
struct MapPaneView: View {
    @Environment(Workspace.self) private var workspace
    /// The reader's magnification, or `nil` to fit the figure to the pane.
    @State private var zoom: CGFloat?
    /// The magnification the pinch in progress started from.
    @State private var pinchStart: CGFloat?
    @State private var scroller = MapScroller()

    /// The margin kept around a fitted figure.
    static let inset: CGFloat = 24
    /// How much of the figure a pan past its edge leaves in view, in points.
    static let kept: CGFloat = 120

    /// The room a canvas leaves past the figure on each side, so it can be panned until only a strip of
    /// it shows: the pane's width and height, less that strip.
    ///
    /// - Parameter pane: The pane's size.
    /// - Returns: The room to the left and right, and above and below.
    static func margin(for pane: CGSize) -> CGSize {
        CGSize(width: max(0, pane.width - kept), height: max(0, pane.height - kept))
    }

    var body: some View {
        @Bindable var workspace = workspace
        let drawing = workspace.drawing
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array(drawing.crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 { Text("›").foregroundStyle(.tertiary) }
                    if index == drawing.crumbs.count - 1 {
                        Text(crumb.label).fontWeight(.semibold)
                    } else {
                        Button(crumb.label) { workspace.step(to: crumb.scope) }
                            .buttonStyle(.link)
                    }
                }
                Spacer()
                if workspace.scopeID == Workspace.changes, workspace.diff.map({ !$0.isEmpty }) == true {
                    Toggle("Untouched", isOn: $workspace.showsUntouched)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                        .help("Also draw the types around the changes that no change reaches: users of a changed type that touch none of what changed, and types a changed type uses as it did")
                }
                if workspace.scopeID == Workspace.focus {
                    if let depth = drawing.depth, depth.total > 1 {
                        Stepper {
                            Text("Depth \(depth.drawn)").font(.callout).monospacedDigit()
                        } onIncrement: {
                            workspace.reachDepth = min(depth.drawn + 1, depth.total)
                        } onDecrement: {
                            workspace.reachDepth = max(depth.drawn - 1, 1)
                        }
                        .help("Draw more or fewer steps from the type")
                    }
                    Picker("Focus", selection: $workspace.focusMode) {
                        Text("Neighbors").tag(Workspace.FocusMode.neighbors)
                        Text("All below").tag(Workspace.FocusMode.below)
                        Text("All above").tag(Workspace.FocusMode.above)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .help("Neighbors: one step each way. All below: everything it depends on. All above: everything that uses it.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Text(drawing.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            if workspace.comparison != .off {
                ChangesLineView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider()
            GeometryReader { proxy in
                let scale = zoom ?? Self.fit(drawing.layout, in: proxy.size)
                let margin = Self.margin(for: proxy.size)
                ScrollView([.horizontal, .vertical]) {
                    MapCanvasView(layout: drawing.layout, lit: workspace.litID, trail: workspace.litTrail, anchor: workspace.anchorID,
                                  scale: scale, colors: workspace.atlas?.moduleColors ?? [:],
                                  marks: workspace.boxMarks, edgeMarks: workspace.edgeMarks, group: workspace.litGroup,
                                  reach: drawing.reach)
                        .padding(Self.inset)
                        .padding(.horizontal, margin.width)
                        .padding(.vertical, margin.height)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                        // A click on the ground between boxes clears the selection back to the level's page;
                        // a box's own click comes first. A right-button drag pans, which the scroller answers.
                        .contentShape(Rectangle())
                        .onTapGesture { workspace.clickedBackground() }
                        .background(MapScrollReader(scroller: scroller))
                }
                .defaultScrollAnchor(.center)
                .onChange(of: margin, initial: true) {
                    scroller.margin = CGSize(width: margin.width + Self.inset, height: margin.height + Self.inset)
                }
                .onAppear {
                    scroller.zoom = { zoom = $0 }
                    scroller.start()
                }
                .onChange(of: scale, initial: true) { scroller.scale = scale }
                .onDisappear { scroller.stop() }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let start = pinchStart ?? scale
                            pinchStart = start
                            zoom = Self.clamp(start * value.magnification)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
                .overlay(alignment: .bottomTrailing) {
                    // Fitting again centers too, so a figure panned away comes back whole.
                    MagnifierView(scale: scale, isFitted: zoom == nil, zoom: { scale in
                        zoom = scale
                        if scale == nil { scroller.center() }
                    }, recenter: { scroller.center() })
                        .padding(12)
                }
            }
            if let atlas = workspace.atlas, !drawing.loose.isEmpty || !drawing.overflow.isEmpty || !drawing.untouched.isEmpty {
                Divider()
                UnderMapFoldView(drawing: drawing)
                if !workspace.foldsUnderMap {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ChipBlockView(title: "Not connected", units: drawing.loose, atlas: atlas)
                            ChipBlockView(title: workspace.scopeID == Workspace.changes ? "Also changed or reached by a change, not drawn"
                                              : "Least connected, not drawn", units: drawing.overflow, atlas: atlas)
                            ChipBlockView(title: "Around the changes, untouched by them", units: drawing.untouched, atlas: atlas)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .background(Palette.background)
        // A new figure fits again, and opens centered however far the last one was panned.
        .onChange(of: drawing.layout) {
            zoom = nil
            scroller.center()
        }
    }

    /// The scale that fits a figure in a pane with ``inset`` around it, never above its natural size.
    ///
    /// - Parameters:
    ///   - layout: The figure.
    ///   - size: The pane's size.
    /// - Returns: A scale from 0.1 to 1.
    static func fit(_ layout: GraphLayout, in size: CGSize) -> CGFloat {
        guard layout.width > 0, layout.height > 0 else { return 1 }
        let across = (size.width - inset * 2) / layout.width
        let down = (size.height - inset * 2) / layout.height
        return clamp(min(1, across, down))
    }

    /// Keeps a magnification between a tenth and four times the natural size.
    ///
    /// - Parameter scale: Any magnification.
    /// - Returns: The magnification, held to 0.1 through 4.
    static func clamp(_ scale: CGFloat) -> CGFloat {
        min(4, max(0.1, scale))
    }
}

/// The map's place and magnification: a button that centers the figure, then smaller, the current scale,
/// which fits and centers the figure again, and larger.
struct MagnifierView: View {
    /// The map's scale, 1 for natural size, which the control shows as a percentage and steps by 1.25 times.
    var scale: CGFloat
    /// Whether the scale is the fitted one rather than the reader's own, which dims the percentage.
    var isFitted: Bool
    /// Sets the reader's magnification, already held to ``MapPaneView/clamp(_:)``'s range, or `nil` to fit
    /// the figure to the pane again.
    var zoom: (CGFloat?) -> Void
    /// Brings the figure back to the middle of the pane, at the magnification it has.
    var recenter: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: recenter) { Image(systemName: "scope").frame(width: 22, height: 20) }
                .help("Center the figure")
            Divider().frame(height: 14)
            Button { zoom(MapPaneView.clamp(scale / 1.25)) } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                .help("Smaller")
            Button { zoom(nil) } label: {
                Text("\(Int((scale * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help(isFitted ? "Fitted to the pane; click to center it too" : "Fit to the pane and center")
            .foregroundStyle(isFitted ? .secondary : .primary)
            Button { zoom(MapPaneView.clamp(scale * 1.25)) } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                .help("Larger")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
    }
}

/// How the interface differs from the base the comparison reads, counted across the whole interface:
/// what is new, what changed, and what is gone, with the gone types named, since the map cannot draw
/// them.
struct ChangesLineView: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        HStack(spacing: 10) {
            if let problem = workspace.comparisonProblem {
                Text("\(workspace.comparisonTitle): \(problem)").foregroundStyle(.secondary).lineLimit(1)
            } else if let diff = workspace.diff {
                let count = { (change: InterfaceDiff.Change) in diff.nodes.filter { $0.change == change }.count }
                // File scope has no name, so it is called by its module's.
                let removed = diff.nodes.filter { $0.change == .removed }.map { $0.node.name.isEmpty ? "\($0.node.module) top level" : $0.node.name }
                if diff.isEmpty {
                    Text("No changes \(workspace.comparisonPhrase)").foregroundStyle(.secondary)
                } else {
                    Text("+\(count(.added)) new").foregroundStyle(Palette.added)
                    if count(.moved) > 0 {
                        Text("→\(count(.moved)) moved").foregroundStyle(Palette.moved)
                            .help("Moved to another module under the same name")
                    }
                    Text("~\(count(.changed)) changed").foregroundStyle(Palette.changed)
                    Text("~\(count(.implementation)) inside").foregroundStyle(Palette.implementation)
                        .help("Changed only inside their bodies: declared and documented as before")
                    Text("−\(count(.removed)) gone").foregroundStyle(Palette.removed)
                    Text(workspace.comparisonPhrase).foregroundStyle(.secondary)
                    if !removed.isEmpty {
                        Text("· gone: " + removed.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(removed.joined(separator: "\n"))
                    }
                }
            } else {
                Text("Reading what changed \(workspace.comparisonPhrase)…").foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
    }
}

/// One placed figure at a scale: edges drawn on a canvas under the boxes, the lit box's edges and
/// neighbors standing out and the rest dimmed. Everything is drawn at the scale rather than stretched,
/// so text stays sharp at any magnification.
struct MapCanvasView: View {
    /// The placed boxes and curves, in points at natural size.
    var layout: GraphLayout
    /// The id of the box to light with its edges and neighbors; `nil`, or one not drawn, lights nothing.
    var lit: String?
    /// Drawn dependencies to light beyond the lit box's own, with the boxes at their ends: a previewed
    /// type's trails back to the root, so the map shows the chain the details pane reads.
    var trail: [GraphLayout.Link] = []
    /// The box drawn as the current one whether or not anything is lit: a reach's root.
    var anchor: String?
    /// The figure's magnification, 1 for its natural size; line weights follow it, held between 0.6 and 1.5.
    var scale: CGFloat
    /// Each module's color slot, which tints its lanes and its module and folder boxes.
    var colors: [String: Int] = [:]
    /// How each box differs from the base a comparison reads, by box id; a box with no entry is the same.
    var marks: [String: InterfaceDiff.Change] = [:]
    /// How each drawn dependency differs from the base, keyed by its ends joined with a tab.
    var edgeMarks: [String: InterfaceDiff.Change] = [:]
    /// Boxes lit together, such as the types a story's theme is about, in place of the lit box; empty
    /// lights them by ``lit`` alone.
    var group: Set<String> = []
    /// The focus's reach, whose frontier boxes take a pill that expands them and whose expanded boxes one
    /// that folds them; `nil` at the other levels.
    var reach: Reach?

    var body: some View {
        let trailed = Set(trail.map { [$0.from, $0.to] })
        let isGrouping = layout.boxes.contains { group.contains($0.item.id) }
        // Lit as a group, the boxes are the current ones and only the edges between them light.
        let lights = { (link: GraphLayout.Link) in
            isGrouping ? group.contains(link.from) && group.contains(link.to)
                : link.from == lit || link.to == lit || trailed.contains([link.from, link.to])
        }
        let litEdges = layout.curves.filter { lights($0.link) }
        let near = isGrouping ? group : Set(litEdges.flatMap { [$0.link.from, $0.link.to] })
        let isLighting = isGrouping || (lit != nil && layout.boxes.contains { $0.item.id == lit })
        let weight = min(1.5, max(0.6, scale))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                // Module lanes sit behind everything: a soft container and the module's name.
                for lane in layout.lanes {
                    let rect = CGRect(x: lane.x * scale, y: lane.y * scale, width: lane.width * scale, height: lane.height * scale)
                    let shape = Path(roundedRect: rect, cornerRadius: 10 * scale)
                    let slot = colors[lane.name]
                    context.fill(shape, with: .color(slot.map(Palette.moduleTint) ?? Palette.panel))
                    // The focused type's module is outlined in its own color; the others only tinted.
                    if lane.isEmphasized, let slot {
                        context.stroke(shape, with: .color(Palette.moduleInk(slot)), lineWidth: 1.5)
                    } else {
                        context.stroke(shape, with: .color(Palette.line.opacity(0.5)), lineWidth: 1)
                    }
                    let name = Text(lane.name.uppercased())
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .tracking(0.8 * scale)
                        .foregroundColor(slot.map(Palette.moduleInk) ?? Palette.edge)
                    context.draw(name, at: CGPoint(x: rect.minX + 12 * scale, y: rect.minY + 9 * scale), anchor: .topLeading)
                }
                for curve in layout.curves {
                    let isLit = isLighting && lights(curve.link)
                    // A new or changed dependency keeps its mark's color, quieter while another box is lit.
                    let mark = edgeMarks[curve.link.from + "\t" + curve.link.to].map(Palette.color(of:))
                    let color: Color = isLit ? Palette.accent : mark.map { $0.opacity(isLighting ? 0.35 : 0.95) }
                        ?? Palette.edge.opacity(isLighting ? 0.2 : 0.75)
                    let style = StrokeStyle(lineWidth: (isLit ? 1.8 : 1.2) * weight, dash: curve.link.dashed ? [4 * weight, 3 * weight] : [])
                    context.stroke(Self.path(curve.points, scale: scale), with: .color(color), style: style)
                    context.fill(Self.arrowhead(curve, scale: scale, size: weight), with: .color(color))
                }
            }
            .frame(width: layout.width * scale, height: layout.height * scale)
            ForEach(Array(layout.boxes.enumerated()), id: \.offset) { _, box in
                MapBoxView(box: box, scale: scale,
                       isCurrent: isGrouping ? group.contains(box.item.id) : (isLighting && box.item.id == lit) || box.item.id == anchor,
                       isDimmed: isLighting && !near.contains(box.item.id) && (isGrouping || box.item.id != lit),
                       tint: Self.module(of: box.item.unit).flatMap { colors[$0] }.map(Palette.moduleTint),
                       mark: marks[box.item.id], beyond: reach?.beyond[box.item.id],
                       isExpanded: reach?.expanded.contains(box.item.id) ?? false, isAbove: reach?.aboveIDs.contains(box.item.id) ?? false)
                    .offset(x: box.x * scale, y: box.y * scale)
            }
        }
        .frame(width: layout.width * scale, height: layout.height * scale, alignment: .topLeading)
    }

    /// The module a module or folder box stands for, which colors it; types stay neutral.
    ///
    /// - Parameter unit: What a box stands for.
    /// - Returns: The module's name, or `nil` for a type.
    static func module(of unit: MapScope.Unit) -> String? {
        switch unit {
        case .type: nil
        case .module(let module): module
        case .folder(let module, _): module
        }
    }

    /// The curve through an edge's anchors, leaving each bottom and entering the next top vertically.
    ///
    /// - Parameters:
    ///   - points: The anchors in flow order.
    ///   - scale: The magnification the figure is drawn at.
    /// - Returns: The path, the same curve the page draws as SVG, at the scale.
    static func path(_ points: [GraphLayout.Anchor], scale: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.bottom))
        for (index, point) in points.enumerated().dropFirst() {
            let previous = points[index - 1]
            let bend = (point.top - previous.bottom) / 2
            path.addCurve(to: CGPoint(x: point.x, y: point.top),
                          control1: CGPoint(x: previous.x, y: previous.bottom + bend),
                          control2: CGPoint(x: point.x, y: point.top - bend))
            if index < points.count - 1 { path.addLine(to: CGPoint(x: point.x, y: point.bottom)) }
        }
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    /// The arrowhead at the end an edge points to: down into its target, or up for an edge that closes
    /// a cycle and is drawn against the flow.
    ///
    /// - Parameters:
    ///   - curve: The edge.
    ///   - scale: The magnification the figure is drawn at.
    ///   - size: How large to draw the head, 1 for its natural size.
    /// - Returns: A filled triangle.
    static func arrowhead(_ curve: GraphLayout.Curve, scale: CGFloat, size: CGFloat) -> Path {
        var path = Path()
        guard let first = curve.points.first, let last = curve.points.last else { return path }
        let (end, back) = curve.reversed ? (CGPoint(x: first.x, y: first.bottom), 7.0 * size) : (CGPoint(x: last.x, y: last.top), -7.0 * size)
        let tip = CGPoint(x: end.x * scale, y: end.y * scale)
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 4 * size, y: tip.y + back))
        path.addLine(to: CGPoint(x: tip.x + 4 * size, y: tip.y + back))
        path.closeSubpath()
        return path
    }
}

/// One box on the map: a type, a module, or a folder. A click selects it, or in a focus pins its tie
/// to the focused type; a double click on a type focuses on it.
struct MapBoxView: View {
    @Environment(Workspace.self) private var workspace
    /// The placed box: its label and detail, its flags and width, and what clicking it selects.
    var box: GraphLayout.Box
    /// The magnification the box's size, text, and corners are drawn at, 1 for its natural size.
    var scale: CGFloat
    /// Whether this is the lit box, drawn with a thicker accent border on the soft accent fill.
    var isCurrent: Bool
    /// Whether another box is lit and this one is not its neighbor, which fades it.
    var isDimmed: Bool
    /// The module's tint for a module or folder box, or `nil` for a type, which stays neutral.
    var tint: Color?
    /// How the box differs from the base a comparison reads, drawn as a badge on its corner; `nil` for
    /// none.
    var mark: InterfaceDiff.Change?
    /// In a focus, what waits past the box, drawn as a pill on the edge it waits past that expands it;
    /// `nil` for none.
    var beyond: Reach.Beyond?
    /// Whether the reader expanded the box, which then takes a pill that folds it.
    var isExpanded = false
    /// Whether the box is above the focus's root, so its expanded step, and its pill, are above it.
    var isAbove = false

    /// The tooltip: what a click and a double click do here.
    private var help: String {
        guard case .type = box.item.unit else {
            return box.item.flags.contains(.boundary) ? "Outside this level; select to step into it" : box.item.label
        }
        if workspace.scopeID == Workspace.focus {
            return box.item.id == workspace.anchorID
                ? box.item.label
                : "\(box.item.label): click to see how it ties here, double-click to focus on it"
        }
        return "\(box.item.label): double-click to focus on it"
    }

    var body: some View {
        let flags = box.item.flags
        let shape = RoundedRectangle(cornerRadius: 5 * scale)
        let stroke: Color = isCurrent ? Palette.accent : flags.contains(.dirty) ? Palette.danger : Palette.line
        VStack(alignment: .leading, spacing: 1 * scale) {
            Text(box.item.label)
                .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
            Text(box.item.detail)
                .font(.system(size: 10 * scale, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.leading, 12 * scale)
        .frame(width: box.width * scale, height: GraphLayout.boxHeight * scale, alignment: .leading)
        // Every box is opaque, dashed ones included, so edges passing behind never show through the text.
        .background(shape.fill(isCurrent ? Palette.accentSoft : flags.contains(.scope) ? (tint ?? Palette.panel) : Palette.surface))
        .overlay(shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: isCurrent ? 2 : 1, dash: flags.contains(.boundary) ? [4, 3] : [])))
        // The mark is a badge on the corner, not a border, so a box with findings keeps its red edge.
        .overlay(alignment: .topTrailing) {
            if let mark, mark != .removed {
                Text(Palette.glyph(of: mark))
                    .font(.system(size: 10 * scale, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Palette.surface)
                    .frame(width: 15 * scale, height: 15 * scale)
                    .background(Circle().fill(Palette.color(of: mark)))
                    .offset(x: 6 * scale, y: -6 * scale)
                    .help(mark == .added ? "New since the base" : mark == .implementation ? "Changed only inside its bodies since the base"
                          : mark == .moved ? "Moved from another module since the base" : "Holds a change since the base")
            }
        }
        .opacity(isDimmed ? 0.4 : flags.contains(.private) ? 0.7 : 1)
        .contentShape(shape)
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                workspace.openInNewTab(Workspace.selection(of: box.item.unit))
            } else {
                workspace.clicked(box.item.unit, count: NSApp.currentEvent?.clickCount ?? 1)
            }
        }
        .onHover { $0 ? workspace.hoverBegan(Workspace.selection(of: box.item.unit)) : workspace.hoverEnded() }
        .contextMenu {
            Button("Open in New Tab") { workspace.openInNewTab(Workspace.selection(of: box.item.unit)) }
            if let beyond {
                Button("Expand One Step \(beyond.isBelow ? "Below" : "Above")") { workspace.expand(box.item.id) }
            }
            if isExpanded {
                Button("Fold") { workspace.fold(box.item.id) }
            }
        }
        .help(help)
        // Outside the box's own click area, so clicking the pill expands or folds without selecting.
        .overlay(alignment: (beyond.map { !$0.isBelow } ?? isAbove) ? .top : .bottom) {
            let below = !(beyond.map { !$0.isBelow } ?? isAbove)
            Group {
                if let beyond {
                    ExpandPillView(text: "+\(beyond.count)", scale: scale) { workspace.expand(box.item.id) }
                        .help("Draw the \(beyond.count) type\(beyond.count == 1 ? "" : "s") \(beyond.isBelow ? "it depends on" : "that use it") past it")
                } else if isExpanded {
                    ExpandPillView(text: "−", scale: scale) { workspace.fold(box.item.id) }
                        .help("Fold the step drawn past it")
                }
            }
            .offset(y: (below ? 9 : -9) * scale)
        }
    }
}

/// The pill on a box's edge in a focus that draws the step past it, or folds that step away again.
struct ExpandPillView: View {
    @State private var isHovered = false
    /// What the pill says: how many types it would draw, or `−` to fold them.
    var text: String
    /// The magnification the map is drawn at.
    var scale: CGFloat
    /// What a click does.
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 9.5 * scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(isHovered ? Palette.accent : .secondary)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 1.5 * scale)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(isHovered ? Palette.accent : Palette.line))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The line over the lists under the map: what the map leaves undrawn, counted, and a chevron that folds
/// the lists to this line or opens them again, as the reader last left it.
struct UnderMapFoldView: View {
    @Environment(Workspace.self) private var workspace
    /// The drawing whose undrawn types the lists hold.
    var drawing: Workspace.Drawing

    var body: some View {
        let changes = workspace.scopeID == Workspace.changes
        let counts = [(drawing.loose.count, "not connected"),
                      (drawing.overflow.count, changes ? "also changed or reached" : "least connected"),
                      (drawing.untouched.count, "untouched around the changes")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        Button { workspace.foldsUnderMap.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(workspace.foldsUnderMap ? 0 : 90))
                Text("Not drawn").font(.callout.weight(.semibold))
                Text(counts.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(workspace.foldsUnderMap ? "Show what the map leaves undrawn" : "Fold these lists away, for as long as gloss runs")
    }
}

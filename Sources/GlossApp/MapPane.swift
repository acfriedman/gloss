import GlossCore
import GlossMap
import SwiftUI

/// The right pane: the dependency map at the current level, with breadcrumbs back to wider levels.
///
/// Each figure opens centered and shrunk to fit the pane, never past its natural size. A pinch or the
/// magnify control zooms from there, and a new figure fits again.
struct MapPane: View {
    @Environment(Workspace.self) private var workspace
    /// The reader's magnification, or `nil` to fit the figure to the pane.
    @State private var zoom: CGFloat?
    /// The magnification the pinch in progress started from.
    @State private var pinchStart: CGFloat?

    /// The margin kept around a fitted figure.
    static let inset: CGFloat = 24

    var body: some View {
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
                Text(drawing.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            GeometryReader { proxy in
                let scale = zoom ?? Self.fit(drawing.layout, in: proxy.size)
                ScrollView([.horizontal, .vertical]) {
                    MapCanvas(layout: drawing.layout, lit: workspace.litID, scale: scale)
                        .padding(Self.inset)
                        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                }
                .defaultScrollAnchor(.center)
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
                    Magnifier(scale: scale, isFitted: zoom == nil) { zoom = $0 }
                        .padding(12)
                }
            }
            if let atlas = workspace.atlas, !drawing.loose.isEmpty || !drawing.overflow.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ChipBlock(title: "Not connected", units: drawing.loose, atlas: atlas)
                        ChipBlock(title: "Least connected, not drawn", units: drawing.overflow, atlas: atlas)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onChange(of: drawing.layout) { zoom = nil }
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

/// The map's magnification: smaller, the current scale, which fits the figure again, and larger.
struct Magnifier: View {
    var scale: CGFloat
    var isFitted: Bool
    var zoom: (CGFloat?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { zoom(MapPane.clamp(scale / 1.25)) } label: { Image(systemName: "minus").frame(width: 22, height: 20) }
                .help("Smaller")
            Button { zoom(nil) } label: {
                Text("\(Int((scale * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help(isFitted ? "Fitted to the pane" : "Fit to the pane")
            .foregroundStyle(isFitted ? .secondary : .primary)
            Button { zoom(MapPane.clamp(scale * 1.25)) } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
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

/// One placed figure at a scale: edges drawn on a canvas under the boxes, the lit box's edges and
/// neighbors standing out and the rest dimmed. Everything is drawn at the scale rather than stretched,
/// so text stays sharp at any magnification.
struct MapCanvas: View {
    @Environment(Workspace.self) private var workspace
    var layout: GraphLayout
    var lit: String?
    var scale: CGFloat

    var body: some View {
        let litEdges = layout.curves.filter { $0.link.from == lit || $0.link.to == lit }
        let near = Set(litEdges.flatMap { [$0.link.from, $0.link.to] })
        let isLighting = lit != nil && layout.boxes.contains { $0.item.id == lit }
        let weight = min(1.5, max(0.6, scale))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for curve in layout.curves {
                    let isLit = isLighting && (curve.link.from == lit || curve.link.to == lit)
                    let color: Color = isLit ? .accentColor : .secondary.opacity(isLighting ? 0.25 : 0.55)
                    let style = StrokeStyle(lineWidth: (isLit ? 1.8 : 1.2) * weight, dash: curve.link.dashed ? [4 * weight, 3 * weight] : [])
                    context.stroke(Self.path(curve.points, scale: scale), with: .color(color), style: style)
                    context.fill(Self.arrowhead(curve, scale: scale, size: weight), with: .color(color))
                }
            }
            .frame(width: layout.width * scale, height: layout.height * scale)
            ForEach(Array(layout.boxes.enumerated()), id: \.offset) { _, box in
                MapBox(box: box, scale: scale, isCurrent: isLighting && box.item.id == lit,
                       isDimmed: isLighting && !near.contains(box.item.id) && box.item.id != lit)
                    .offset(x: box.x * scale, y: box.y * scale)
            }
        }
        .frame(width: layout.width * scale, height: layout.height * scale, alignment: .topLeading)
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

/// One box on the map: a type, a module, or a folder, selecting it when clicked.
struct MapBox: View {
    @Environment(Workspace.self) private var workspace
    var box: GraphLayout.Box
    var scale: CGFloat
    var isCurrent: Bool
    var isDimmed: Bool

    var body: some View {
        let flags = box.item.flags
        let shape = RoundedRectangle(cornerRadius: 5 * scale)
        let stroke: Color = isCurrent ? .accentColor : flags.contains(.dirty) ? .red : .secondary.opacity(0.6)
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
        .background(shape.fill(isCurrent ? Color.accentColor.opacity(0.18) : flags.contains(.scope) ? Color.secondary.opacity(0.08) : Color(nsColor: .textBackgroundColor)))
        .overlay(shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: isCurrent ? 2 : 1, dash: flags.contains(.boundary) ? [4, 3] : [])))
        .opacity(isDimmed ? 0.4 : flags.contains(.private) ? 0.7 : 1)
        .contentShape(shape)
        .onTapGesture { workspace.select(unit: box.item.unit) }
        .onHover { $0 ? workspace.hoverBegan(Workspace.selection(of: box.item.unit)) : workspace.hoverEnded() }
        .help(box.item.flags.contains(.boundary) ? "Outside this level; select to step into it" : box.item.label)
    }
}

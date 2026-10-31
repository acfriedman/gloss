import GlossCore
import GlossMap
import SwiftUI

/// The right pane: the dependency map at the current level, with breadcrumbs back to wider levels.
struct MapPane: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let drawing = workspace.drawing
        VStack(alignment: .leading, spacing: 0) {
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
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 16) {
                    MapCanvas(layout: drawing.layout, lit: workspace.litID)
                    if let atlas = workspace.atlas {
                        ChipBlock(title: "Not connected", units: drawing.loose, atlas: atlas)
                        ChipBlock(title: "Least connected, not drawn", units: drawing.overflow, atlas: atlas)
                    }
                }
                .padding(24)
            }
            .defaultScrollAnchor(.top)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// One placed figure: edges drawn on a canvas under the boxes, the lit box's edges and neighbors
/// standing out and the rest dimmed.
struct MapCanvas: View {
    @Environment(Workspace.self) private var workspace
    var layout: GraphLayout
    var lit: String?

    var body: some View {
        let litEdges = layout.curves.filter { $0.link.from == lit || $0.link.to == lit }
        let near = Set(litEdges.flatMap { [$0.link.from, $0.link.to] })
        let isLighting = lit != nil && layout.boxes.contains { $0.item.id == lit }
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for curve in layout.curves {
                    let isLit = isLighting && (curve.link.from == lit || curve.link.to == lit)
                    let color: Color = isLit ? .accentColor : .secondary.opacity(isLighting ? 0.25 : 0.55)
                    let style = StrokeStyle(lineWidth: isLit ? 1.8 : 1.2, dash: curve.link.dashed ? [4, 3] : [])
                    context.stroke(Self.path(curve.points), with: .color(color), style: style)
                    context.fill(Self.arrowhead(curve), with: .color(color))
                }
            }
            .frame(width: layout.width, height: layout.height)
            ForEach(Array(layout.boxes.enumerated()), id: \.offset) { _, box in
                MapBox(box: box, isCurrent: isLighting && box.item.id == lit,
                       isDimmed: isLighting && !near.contains(box.item.id) && box.item.id != lit)
                    .offset(x: box.x, y: box.y)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    /// The curve through an edge's anchors, leaving each bottom and entering the next top vertically.
    ///
    /// - Parameter points: The anchors in flow order.
    /// - Returns: The path, the same curve the page draws as SVG.
    static func path(_ points: [GraphLayout.Anchor]) -> Path {
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
        return path
    }

    /// The arrowhead at the end an edge points to: down into its target, or up for an edge that closes
    /// a cycle and is drawn against the flow.
    ///
    /// - Parameter curve: The edge.
    /// - Returns: A filled triangle.
    static func arrowhead(_ curve: GraphLayout.Curve) -> Path {
        var path = Path()
        guard let first = curve.points.first, let last = curve.points.last else { return path }
        let (tip, back) = curve.reversed ? (CGPoint(x: first.x, y: first.bottom), 7.0) : (CGPoint(x: last.x, y: last.top), -7.0)
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 4, y: tip.y + back))
        path.addLine(to: CGPoint(x: tip.x + 4, y: tip.y + back))
        path.closeSubpath()
        return path
    }
}

/// One box on the map: a type, a module, or a folder, selecting it when clicked.
struct MapBox: View {
    @Environment(Workspace.self) private var workspace
    var box: GraphLayout.Box
    var isCurrent: Bool
    var isDimmed: Bool

    var body: some View {
        let flags = box.item.flags
        let shape = RoundedRectangle(cornerRadius: 5)
        let stroke: Color = isCurrent ? .accentColor : flags.contains(.dirty) ? .red : .secondary.opacity(0.6)
        VStack(alignment: .leading, spacing: 1) {
            Text(box.item.label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(box.item.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.leading, 12)
        .frame(width: box.width, height: GraphLayout.boxHeight, alignment: .leading)
        .background(shape.fill(isCurrent ? Color.accentColor.opacity(0.18) : flags.contains(.scope) ? Color.secondary.opacity(0.08) : Color(nsColor: .textBackgroundColor)))
        .overlay(shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: isCurrent ? 2 : 1, dash: flags.contains(.boundary) ? [4, 3] : [])))
        .opacity(isDimmed ? 0.4 : flags.contains(.private) ? 0.7 : 1)
        .contentShape(shape)
        .onTapGesture { workspace.select(unit: box.item.unit) }
        .onHover { $0 ? workspace.hoverBegan(Workspace.selection(of: box.item.unit)) : workspace.hoverEnded() }
        .help(box.item.flags.contains(.boundary) ? "Outside this level; select to step into it" : box.item.label)
    }
}

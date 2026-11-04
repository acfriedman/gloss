import GlossRead
import GlossModel
import GlossMap
import SwiftUI

/// The summary page: the interface's size, how much of what must be documented is, and what the linter
/// found, then the findings by rule, each module's share, the types with the most findings, and the
/// declarations by access.
struct SummaryPageView: View {
    /// The arranged interface the summary is taken from.
    var atlas: Atlas

    var body: some View {
        let summary = atlas.interfaceSummary()
        let percent = summary.owed == 0 ? 100 : Int((Double(summary.documented) / Double(summary.owed) * 100).rounded())
        HeadingView(title: "Summary",
                    lede: "\(summary.declarations) declarations in \(summary.types) types across \(summary.modules.count) module\(summary.modules.count == 1 ? "" : "s").")
        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
            GridRow {
                StatView(title: "Declarations", value: "\(summary.declarations)")
                StatView(title: "Public", value: "\(summary.publicDeclarations)")
                StatView(title: "Types", value: "\(summary.types)")
            }
            GridRow {
                StatView(title: "Documented", value: "\(summary.documented)/\(summary.owed)")
                StatView(title: "Coverage", value: "\(percent)%", tint: percent == 100 ? Palette.ok : .primary)
                StatView(title: "Findings", value: "\(summary.findings)", tint: summary.findings == 0 ? Palette.ok : Palette.danger)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            EyebrowView(text: "Findings by rule · \(summary.findingsByRule.count)")
            if summary.findingsByRule.isEmpty {
                Text("No findings: every declaration's doc has the shape the rules ask for.")
                    .textStyle(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(summary.findingsByRule, id: \.name) { rule in
                        GridRow {
                            Text(rule.name).textStyle(.callout, design: .monospaced)
                            Text("\(rule.count)").textStyle(.callout, design: .monospaced).foregroundStyle(Palette.danger)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            EyebrowView(text: "Modules · \(summary.modules.count)")
            // Two lines a module rather than a table's columns, so a long name and its counts both fit the
            // details pane.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(summary.modules, id: \.name) { module in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            ModuleNameView(module: module.name)
                            Text(module.findings == 0 ? "no findings" : "\(module.findings) finding\(module.findings == 1 ? "" : "s")")
                                .textStyle(.callout)
                                .foregroundStyle(module.findings == 0 ? Palette.ok : Palette.danger)
                                .fixedSize()
                        }
                        Text("\(module.types) type\(module.types == 1 ? "" : "s") · \(module.declarations) declarations · "
                             + "\(module.publicDeclarations) public · \(module.documented) of \(module.owed) documented")
                            .textStyle(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        if !summary.mostFindings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowView(text: "Most findings")
                ForEach(summary.mostFindings, id: \.name) { type in
                    HStack(spacing: 8) {
                        ChipView(unit: .type(type.name), atlas: atlas)
                        Text("\(type.count)").textStyle(.callout, design: .monospaced).foregroundStyle(Palette.danger)
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            EyebrowView(text: "By access")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(summary.byAccess, id: \.name) { access in
                    GridRow {
                        Text(access.name).textStyle(.callout, design: .monospaced)
                        Self.number(access.count).gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }

    /// A count in a table's column.
    ///
    /// - Parameter count: The count.
    /// - Returns: The count, monospaced so a column lines up, and never wrapped.
    static func number(_ count: Int) -> some View {
        Text("\(count)").textStyle(.callout, design: .monospaced).lineLimit(1).fixedSize()
    }
}

/// A module's name in a table: its color and its name on one line, truncated in the middle when the
/// column is narrow, opening the module when clicked and lighting its box while hovered.
struct ModuleNameView: View {
    @Environment(Workspace.self) private var workspace
    /// The module's name.
    var module: String

    var body: some View {
        Button { workspace.select(.module(module)) } label: {
            HStack(spacing: 6) {
                ModuleDotView(module: module)
                Text(module)
                    .textStyle(.callout, design: .monospaced)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(module)
        .onHover { workspace.hovered = $0 ? MapScope.Unit.module(module).id : nil }
    }
}

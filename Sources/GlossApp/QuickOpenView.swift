import GlossCore
import GlossMap
import SwiftUI

/// Open Quickly, as in Xcode: type a few letters of a type's name, move with the arrow keys, and
/// press Return to open it in the map's focus. Esc or a click outside closes it.
struct QuickOpenView: View {
    @Environment(Workspace.self) private var workspace
    @State private var query = ""
    @State private var chosen = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let matches = Timing.measure("quick open", query) { workspace.atlas?.quickOpen(query, limit: 40) ?? [] }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Open Quickly", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit { open(matches.indices.contains(chosen) ? matches[chosen] : nil) }
                    .onKeyPress(.downArrow) {
                        chosen = min(chosen + 1, max(matches.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        chosen = max(chosen - 1, 0)
                        return .handled
                    }
                    .onExitCommand { workspace.isQuickOpenShown = false }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            if !matches.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                                QuickOpenRowView(match: match, isChosen: index == chosen)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(match) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: chosen) { _, index in proxy.scrollTo(index) }
                }
            }
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .onAppear { isFocused = true }
        .onChange(of: query) { chosen = 0 }
    }

    private func open(_ match: QuickOpenMatch?) {
        guard let match else { return }
        workspace.isQuickOpenShown = false
        // Option-Return opens the type in a new tab, as Xcode's Open Quickly does.
        if NSEvent.modifierFlags.contains(.option) {
            workspace.focusInNewTab(on: match.node.id)
        } else {
            workspace.focus(on: match.node.id)
        }
    }
}

/// One result: a badge for its kind, its name with the typed letters drawn bold, and where it lives.
struct QuickOpenRowView: View {
    @Environment(Workspace.self) private var workspace
    /// The result the row shows: its kind badge, its name with the typed letters bold, and where it lives.
    var match: QuickOpenMatch
    /// Whether the arrow keys rest on this row, which Return opens; the row is filled with the soft accent.
    var isChosen: Bool

    var body: some View {
        let node = match.node
        let place = ([node.module] + (workspace.atlas?.directories(of: node) ?? [])).joined(separator: "/")
        HStack(spacing: 10) {
            Text(Self.badge(node.keyword))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 22, height: 18)
                .foregroundStyle(Palette.accent)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.accentSoft))
            Text(Self.marked(match))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            if (workspace.atlas?.group(node.id).findingCount ?? 0) > 0 {
                Circle().fill(Palette.danger).frame(width: 6, height: 6)
            }
            Spacer(minLength: 12)
            ModuleDotView(module: node.module)
            Text(place)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isChosen ? Palette.accentSoft : .clear))
    }

    /// The short mark for a kind of type, as Xcode badges them.
    ///
    /// - Parameter keyword: The node's keyword.
    /// - Returns: `S` for a struct, `C` for a class, and so on; `Ext` for an extension, `F` for file scope.
    static func badge(_ keyword: String) -> String {
        switch keyword {
        case "struct": "S"
        case "class": "C"
        case "enum": "E"
        case "protocol": "P"
        case "actor": "A"
        case "extension": "Ext"
        default: "F"
        }
    }

    /// The matched name with its typed letters bold.
    ///
    /// - Parameter match: A result.
    /// - Returns: The name, its matched characters set in a heavier weight.
    static func marked(_ match: QuickOpenMatch) -> AttributedString {
        var result = AttributedString()
        let matched = Set(match.matched)
        for (offset, character) in match.name.enumerated() {
            var piece = AttributedString(String(character))
            if matched.contains(offset) { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }
}

import GlossMap
import SwiftUI

/// Swift source colored the way Xcode's default themes color it, from the shared highlighter.
struct CodeView: View {
    var runs: [Highlight.Run]

    var body: some View {
        Text(Self.attributed(runs))
    }

    /// Joins runs into one string, each run in its kind's color; keywords are bold, as in Xcode.
    ///
    /// - Parameter runs: Runs from ``GlossMap/Highlight``.
    /// - Returns: The source, with plain runs left to the surrounding style.
    static func attributed(_ runs: [Highlight.Run]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if let color = color(run.kind) { piece.foregroundColor = color }
            if run.kind == .keyword { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }

    /// The color a kind of run is drawn in, with Xcode's default light and dark values.
    ///
    /// - Parameter kind: A run's kind.
    /// - Returns: The color, or `nil` for plain text.
    static func color(_ kind: Highlight.Kind) -> Color? {
        switch kind {
        case .plain: nil
        case .keyword: Palette.adaptive(light: 0x9B2393, dark: 0xFF7AB2)
        case .attribute: Palette.adaptive(light: 0x815F03, dark: 0xCC9768)
        case .string: Palette.adaptive(light: 0xC41A16, dark: 0xFF8170)
        case .number: Palette.adaptive(light: 0x1C00CF, dark: 0xD9C97C)
        case .comment: Palette.adaptive(light: 0x5D6C79, dark: 0x7F8C98)
        case .type: Palette.adaptive(light: 0x3900A0, dark: 0xDABAFF)
        case .projectType: Palette.adaptive(light: 0x2F7C84, dark: 0x9EF1DD)
        case .declaration: Palette.adaptive(light: 0x0F68A0, dark: 0x41A1C0)
        }
    }
}

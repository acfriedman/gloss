import AppKit
import SwiftUI

/// How big the detail pane sets its text, as a scale of macOS's own sizes, remembered between launches.
///
/// macOS has no Dynamic Type for an app's text styles to follow, so the pane's text scales itself: each
/// view names a text style with ``SwiftUI/View/textStyle(_:design:weight:monospacedDigit:)``,
/// and the style becomes a font at the scale the View menu and Settings choose.
enum TextSize {
    /// The key the scale is stored under.
    static let key = "textSize"
    /// The scale `GLOSS_TEXT_SIZE` sets for one run, as a snapshot asks, without storing it.
    static let override = ProcessInfo.processInfo.environment["GLOSS_TEXT_SIZE"].flatMap(Double.init)
    /// The scales the View menu steps through, smallest first; 1 is macOS's own size.
    static let steps: [Double] = [0.85, 1, 1.15, 1.3, 1.5, 1.75, 2]

    /// The next scale up.
    ///
    /// - Parameter scale: The scale now.
    /// - Returns: The smallest step bigger than it, or `nil` at the biggest.
    static func bigger(than scale: Double) -> Double? {
        steps.first { $0 > scale + 0.001 }
    }

    /// The next scale down.
    ///
    /// - Parameter scale: The scale now.
    /// - Returns: The biggest step smaller than it, or `nil` at the smallest.
    static func smaller(than scale: Double) -> Double? {
        steps.last { $0 < scale - 0.001 }
    }

    /// The scale as a reader sees it.
    ///
    /// - Parameter scale: A scale.
    /// - Returns: A percentage such as `115%`.
    static func percent(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }

    /// The point size macOS gives a text style, read from AppKit so a scale of 1 matches the system's own.
    ///
    /// - Parameter style: A text style.
    /// - Returns: Its size in points.
    static func pointSize(of style: Font.TextStyle) -> CGFloat {
        let appKit: NSFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return NSFont.preferredFont(forTextStyle: appKit).pointSize
    }
}

extension EnvironmentValues {
    /// The scale the detail pane's text is set at; 1 outside it, so views shared with other panes keep
    /// their size there.
    @Entry var textScale: Double = 1
}

/// Sets a text style at the environment's ``SwiftUI/EnvironmentValues/textScale``: the style itself at
/// 1, so the default looks as it did, and a system font of the style's size times the scale otherwise.
struct ScaledTextStyle: ViewModifier {
    @Environment(\.textScale) private var scale
    /// The text style.
    var style: Font.TextStyle
    /// The design, such as `monospaced`.
    var design: Font.Design
    /// The weight, or `nil` for the style's own.
    var weight: Font.Weight?
    /// `true` for digits of one width, so counts line up.
    var monospacedDigit: Bool

    func body(content: Content) -> some View {
        var font = scale == 1 ? Font.system(style, design: design, weight: weight)
            : Font.system(size: TextSize.pointSize(of: style) * scale, weight: weight ?? (style == .headline ? .bold : .regular), design: design)
        if monospacedDigit { font = font.monospacedDigit() }
        return content.font(font)
    }
}

/// Sets a fixed point size, such as a badge's, at the environment's ``SwiftUI/EnvironmentValues/textScale``.
struct ScaledPointSize: ViewModifier {
    @Environment(\.textScale) private var scale
    /// The size in points at a scale of 1.
    var size: CGFloat
    /// The weight.
    var weight: Font.Weight
    /// The design.
    var design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// Sets the text in a text style that follows the detail pane's text size.
    ///
    /// - Parameters:
    ///   - style: The text style, such as `callout`.
    ///   - design: The design, such as `monospaced`.
    ///   - weight: The weight, or `nil` for the style's own.
    ///   - monospacedDigit: `true` for digits of one width.
    /// - Returns: The view with the font set.
    func textStyle(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil,
                   monospacedDigit: Bool = false) -> some View {
        modifier(ScaledTextStyle(style: style, design: design, weight: weight, monospacedDigit: monospacedDigit))
    }

    /// Sets the text at a point size that follows the detail pane's text size.
    ///
    /// - Parameters:
    ///   - size: The size in points at macOS's own text size.
    ///   - weight: The weight.
    ///   - design: The design.
    /// - Returns: The view with the font set.
    func textSize(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledPointSize(size: size, weight: weight, design: design))
    }
}

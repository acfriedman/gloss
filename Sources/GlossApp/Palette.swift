import AppKit
import GlossMap
import SwiftUI

/// The page's colors, so the app and the page read alike: a muted indigo accent on a pale tint,
/// neutral lines and surfaces, and a brick red for findings, each with a light and a dark value.
enum Palette {
    /// The color of lit boxes and edges on the map, hovered chips, Open Quickly badges, and controls.
    static let accent = adaptive(light: 0x2F4FBF, dark: 0x94A9FF)
    /// The pale accent behind the lit box on the map, Open Quickly's badges, and its chosen row.
    static let accentSoft = adaptive(light: 0xE6EBFA, dark: 0x1F2740)
    /// The ground the map pane is drawn on.
    static let background = adaptive(light: 0xF6F7F9, dark: 0x11141A)
    /// The fill of chips and of type boxes on the map.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1A1E26)
    /// The fill of module and folder boxes on the map, setting them apart from type boxes.
    static let panel = adaptive(light: 0xEEF0F4, dark: 0x151920)
    /// The border of chips and map boxes at rest, and of the Open Quickly panel.
    static let line = adaptive(light: 0xB9C0CC, dark: 0x3D4552)
    /// The color of map edges that are not lit, faded further while another box is lit.
    static let edge = adaptive(light: 0x7B8494, dark: 0x7D8698)
    /// The color of findings and missing docs: finding text, and the marks and borders on what has findings.
    static let danger = adaptive(light: 0xB4321C, dark: 0xFF8A73)
    /// The color of the findings count in the list's summary when there are none.
    static let ok = adaptive(light: 0x2C7A4B, dark: 0x6FCF97)

    /// The soft tint a module's containers and boxes are filled with.
    ///
    /// - Parameter slot: The module's color slot; any value wraps into the palette.
    /// - Returns: A color that follows the appearance.
    static func moduleTint(_ slot: Int) -> Color {
        let color = ModulePalette.color(slot)
        return adaptive(light: color.tintLight, dark: color.tintDark)
    }

    /// The stronger color a module's name and marks are drawn in.
    ///
    /// - Parameter slot: The module's color slot; any value wraps into the palette.
    /// - Returns: A color that follows the appearance.
    static func moduleInk(_ slot: Int) -> Color {
        let color = ModulePalette.color(slot)
        return adaptive(light: color.inkLight, dark: color.inkDark)
    }

    /// A color that follows the window's appearance.
    ///
    /// - Parameters:
    ///   - light: The sRGB value in light mode, as `0xRRGGBB`.
    ///   - dark: The sRGB value in dark mode.
    /// - Returns: A color that resolves when drawn, so it changes with the appearance.
    static func adaptive(light: Int, dark: Int) -> Color {
        func color(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

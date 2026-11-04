import AppKit
import GlossRead
import GlossModel
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
    /// The mark of what is new since the base a comparison reads: a badge on a box, an edge's stroke.
    static let added = adaptive(light: 0x1A7F37, dark: 0x3FB950)
    /// The mark of what changed since the base: a badge on a box holding a change, an edge's stroke.
    static let changed = adaptive(light: 0x9A6700, dark: 0xD29922)
    /// The mark of what is gone since the base: the count of changes, and a dropped dependency's stroke.
    static let removed = adaptive(light: 0xCF222E, dark: 0xF85149)
    /// The quieter mark of what changed only inside since the base: its bodies, not what it declares.
    static let implementation = adaptive(light: 0x6E7781, dark: 0x8B949E)
    /// The mark of a type that moved to another module since the base: a badge on its box.
    static let moved = adaptive(light: 0x0969DA, dark: 0x58A6FF)

    /// The color a change is marked in.
    ///
    /// - Parameter change: A change.
    /// - Returns: Green for new, amber for changed, red for gone, gray for changed only inside, and blue
    ///   for moved.
    static func color(of change: InterfaceDiff.Change) -> Color {
        switch change {
        case .added: added
        case .changed: changed
        case .removed: removed
        case .implementation: implementation
        case .moved: moved
        }
    }

    /// The glyph a change is marked with: `+`, `~`, `−`, or `→` for a move, a change made only inside
    /// sharing `~` in its quieter color.
    ///
    /// - Parameter change: A change.
    /// - Returns: The glyph.
    static func glyph(of change: InterfaceDiff.Change) -> String {
        switch change {
        case .added: "+"
        case .changed, .implementation: "~"
        case .removed: "−"
        case .moved: "→"
        }
    }

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

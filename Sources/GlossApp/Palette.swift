import AppKit
import SwiftUI

/// The page's colors, so the app and the page read alike: a muted indigo accent on a pale tint,
/// neutral lines and surfaces, and a brick red for findings, each with a light and a dark value.
enum Palette {
    static let accent = adaptive(light: 0x2F4FBF, dark: 0x94A9FF)
    static let accentSoft = adaptive(light: 0xE6EBFA, dark: 0x1F2740)
    static let background = adaptive(light: 0xF6F7F9, dark: 0x11141A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1A1E26)
    static let panel = adaptive(light: 0xEEF0F4, dark: 0x151920)
    static let line = adaptive(light: 0xB9C0CC, dark: 0x3D4552)
    static let edge = adaptive(light: 0x7B8494, dark: 0x7D8698)
    static let danger = adaptive(light: 0xB4321C, dark: 0xFF8A73)
    static let ok = adaptive(light: 0x2C7A4B, dark: 0x6FCF97)

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

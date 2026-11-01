/// The colors modules are told apart by, shared by every front end so a module looks the same in the
/// app and on the page: for each slot of ``Atlas/moduleColors``, a soft tint for what a module contains
/// and a stronger ink for its name, each in a light and a dark value.
public enum ModulePalette {
    /// One module color, as `0xRRGGBB` sRGB values.
    public struct Color: Sendable, Equatable {
        /// The tint in light appearance.
        public var tintLight: Int
        /// The tint in dark appearance.
        public var tintDark: Int
        /// The ink in light appearance.
        public var inkLight: Int
        /// The ink in dark appearance.
        public var inkDark: Int
    }

    /// Teal, rose, amber, violet, lime, sky, orange, brown, green, and slate: hues apart from the
    /// accent indigo and the findings red, ordered so neighboring slots contrast, since a module whose
    /// slot is taken moves to the next.
    public static let colors: [Color] = [
        Color(tintLight: 0xE0F2F1, tintDark: 0x12302E, inkLight: 0x0F766E, inkDark: 0x5EEAD4),
        Color(tintLight: 0xFBE4EA, tintDark: 0x3A1A24, inkLight: 0xB42352, inkDark: 0xFDA4BC),
        Color(tintLight: 0xFBF1DC, tintDark: 0x33290F, inkLight: 0x92600A, inkDark: 0xFCD34D),
        Color(tintLight: 0xEEE6FB, tintDark: 0x271D3D, inkLight: 0x6D3FC0, inkDark: 0xC4B5FD),
        Color(tintLight: 0xEEF6D8, tintDark: 0x26300F, inkLight: 0x5B7A0F, inkDark: 0xBEF264),
        Color(tintLight: 0xE0F0FB, tintDark: 0x12293A, inkLight: 0x1F6FA8, inkDark: 0x7DD3FC),
        Color(tintLight: 0xFCE9DC, tintDark: 0x3A2414, inkLight: 0xB4531A, inkDark: 0xFDBA74),
        Color(tintLight: 0xF1ECE6, tintDark: 0x2C2620, inkLight: 0x7A5A3A, inkDark: 0xD6B994),
        Color(tintLight: 0xE3F4E5, tintDark: 0x15301B, inkLight: 0x2F7D3A, inkDark: 0x86EFAC),
        Color(tintLight: 0xE7EBF0, tintDark: 0x222833, inkLight: 0x4B5A6E, inkDark: 0xCBD5E1)
    ]

    /// The color for a slot.
    ///
    /// - Parameter slot: A module's color slot; any value wraps into the palette.
    /// - Returns: Its tint and ink.
    public static func color(_ slot: Int) -> Color {
        colors[((slot % colors.count) + colors.count) % colors.count]
    }
}

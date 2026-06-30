import SwiftUI

/// Monochrome design tokens for the AcmeBank UI.
///
/// **Strictly monochrome by design.** The Home story explicitly
/// forbids semantic colour (a red tint for negatives, a green tint
/// for positives, tinted category icons, etc.) — every surface is
/// some shade of navy, grey, or near-white. A negative balance is
/// communicated by the U+2212 minus glyph emitted by
/// `CurrencyFormatter`, NOT by tint. If a future PR needs a new
/// token, keep it in the navy-to-white spectrum; never reach for
/// `Color(.systemRed)` / `Color(.systemGreen)` here.
///
/// Hex values from the design spec:
///   navy900   #16223C   darkest brand surface (card backgrounds)
///   navy800   #1B2A4A   secondary navy (icon tiles, app bar)
///   background #F2F3F5  near-white screen background
///   surface   #FFFFFF   card surfaces above the background
///   text      #1A1A1A   near-black primary text
///   subtext   #6B7280   grey secondary text
///   divider   #E5E7EB   hairline separators
public enum AcmeColors {
    public static let navy900 = hex(0x16223C)
    public static let navy800 = hex(0x1B2A4A)
    public static let background = hex(0xF2F3F5)
    public static let surface = Color.white
    public static let text = hex(0x1A1A1A)
    public static let subtext = hex(0x6B7280)
    public static let divider = hex(0xE5E7EB)
    public static let onNavy = Color.white
    public static let onNavySubtle = Color.white.opacity(0.7)

    /// Build a SwiftUI `Color` from a 24-bit RGB hex literal
    /// (e.g. `0x16223C`). Keeps the token table compact and free of
    /// semantic colour-channel labels.
    private static func hex(_ rgb: UInt32) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

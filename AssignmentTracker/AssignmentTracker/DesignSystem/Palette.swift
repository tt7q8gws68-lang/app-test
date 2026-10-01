import SwiftUI
import UIKit

/// The Dusk theme as semantic tokens. Each resolves per trait collection, so the whole app
/// follows the system appearance. Views use these names, never raw colors.
enum Palette {
    // MARK: Surfaces and text
    static let background = Color(light: 0xECEAF6, dark: 0x0D0B1A)
    static let text = Color(light: 0x17142B, dark: 0xF4F2FB)
    static let secondaryText = Color(light: 0x57527A, dark: 0xABA6C8)
    static let tertiaryText = Color(light: 0x433E63, dark: 0xC0BBDB)
    static let completedText = Color(light: 0x767190, dark: 0x8A85A8)
    /// Past day numbers, chevrons and open step rings.
    static let mutedNumber = Color(light: 0x9A95B5, dark: 0x6F6A8C)
    static let hairline = Color(light: 0x17142B, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.10)
    static let track = Color(light: 0x17142B, dark: 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.12)
    /// Faint fill for empty day circles and neutral chips.
    static let faintFill = Color(light: 0x17142B, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    static let dashedOutline = Color(light: 0x17142B, dark: 0xFFFFFF, lightAlpha: 0.18, darkAlpha: 0.22)

    // MARK: Accent
    static let accent = Color(light: 0x5B4BEA, dark: 0x8C7DFF)
    static let accentText = Color(light: 0x4A3BD6, dark: 0xA89BFF)
    /// End of the progress ring gradient.
    static let ringEnd = Color(light: 0xD6477A, dark: 0xFF7FA6)
    /// Solid accent buttons (+, Mark as complete). A touch deeper than the accent in dark mode,
    /// as in the dark mockup, so white text and icons on it keep their contrast.
    static let accentFill = Color(light: 0x5B4BEA, dark: 0x7C6CFF)
    /// Marks drawn on top of an accent or course-colored fill.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0D0B1A)

    // MARK: Glass
    /// The selected tab's frosted pill.
    static let selectedPill = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.75, darkAlpha: 0.16)
    /// The selected segment in glass segmented controls (more opaque than the tab pill).
    static let selectedSegment = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.92, darkAlpha: 0.16)

    // MARK: Status (unchanged from earlier themes)
    static let streakOrange = Color(light: 0xE8700F, dark: 0xFF9A5C)
    static let onTimeGreen = Color(light: 0x1F9D55, dark: 0x34C77B)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A80)
    /// Medium priority and soft warnings.
    static let warning = Color(light: 0x9A5800, dark: 0xFFB35C)

    // MARK: Backdrop glows
    static let glowTopLeft = Color(light: 0x8FA8FF, dark: 0x4B3BFF)
    static let glowRight = Color(light: 0xD9A8F5, dark: 0xB03DE0)
    static let glowBottomLeft = Color(light: 0xFFB8CC, dark: 0xFF4D8D)
}

extension Color {
    nonisolated init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? rgbColor(dark, alpha: darkAlpha)
                : rgbColor(light, alpha: lightAlpha)
        })
    }
}

private nonisolated func rgbColor(_ hex: UInt32, alpha: CGFloat) -> UIColor {
    UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

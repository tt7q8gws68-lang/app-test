import SwiftUI
import UIKit

/// Colors taken from the light and dark mockups. Each one resolves per trait collection,
/// so the whole app follows the system appearance.
enum Palette {
    static let canvas = Color(light: 0xE9ECF2, dark: 0x0B0D12)
    static let secondaryText = Color(light: 0x4E5460, dark: 0xA3A9B5)
    static let completedText = Color(light: 0x6B717C, dark: 0x7C828E)
    static let chevron = Color(light: 0x8A909B, dark: 0x6E7480)
    static let openStep = Color(light: 0x9AA0AA, dark: 0x6E7480)
    static let track = Color(light: 0x14161C, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.12)
    /// Checkmark drawn on top of a filled course-colored circle.
    static let onFill = Color(light: 0xFFFFFF, dark: 0x0B0D12)
    static let danger = Color(light: 0xB3261E, dark: 0xFF8A80)
    static let warning = Color(light: 0xA15C00, dark: 0xFFB35C)
    static let success = Color(light: 0x1F9D55, dark: 0x30D158)

    static let blobBlue = Color(light: 0x7FB2FF, dark: 0x2F5BFF)
    static let blobPeach = Color(light: 0xFFB38A, dark: 0xFF6A2B)
    static let blobMint = Color(light: 0x9EE6D3, dark: 0x14B892)
    static let blobLilac = Color(light: 0xB9A6FF, dark: 0x7B4DFF)
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

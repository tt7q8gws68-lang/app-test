import SwiftUI

/// Stored by name so each course shows its light or dark variant automatically. New cases can be
/// added freely; existing courses keep decoding by their raw value.
nonisolated enum CourseColor: String, Codable, CaseIterable {
    case blue, indigo, purple, pink, red, orange, amber, green, teal, cyan, brown, graphite

    /// Dusk hues. Blue, pink, purple and teal are the theme's course colors; the rest are tuned
    /// to sit with them and stay readable on glass in both appearances.
    var color: Color {
        switch self {
        case .blue: Color(light: 0x5B4BEA, dark: 0x8C7DFF)
        case .indigo: Color(light: 0x3E5BD6, dark: 0x8FA4FF)
        case .purple: Color(light: 0x9B4FD6, dark: 0xC98BFF)
        case .pink: Color(light: 0xD6477A, dark: 0xFF7FA6)
        case .red: Color(light: 0xC2364A, dark: 0xFF8A95)
        case .orange: Color(light: 0xC8571E, dark: 0xFF9A66)
        case .amber: Color(light: 0x9E6700, dark: 0xF2C14E)
        case .green: Color(light: 0x2E8B57, dark: 0x5FD49A)
        case .teal: Color(light: 0x1A8FA8, dark: 0x4FD0E0)
        case .cyan: Color(light: 0x1F7FC4, dark: 0x6FC3FF)
        case .brown: Color(light: 0x8C5E46, dark: 0xD9A98C)
        case .graphite: Color(light: 0x6A6585, dark: 0xB3AECD)
        }
    }

    var name: String { rawValue.capitalized }
}

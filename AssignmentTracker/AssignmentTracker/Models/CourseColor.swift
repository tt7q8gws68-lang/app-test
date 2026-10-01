import SwiftUI

/// Stored by name so each course shows its light or dark variant automatically. New cases can be
/// added freely; existing courses keep decoding by their raw value.
nonisolated enum CourseColor: String, Codable, CaseIterable {
    case blue, indigo, purple, pink, red, orange, amber, green, teal, cyan, brown, graphite

    var color: Color {
        switch self {
        case .blue: Color(light: 0x0A62E0, dark: 0x5B97FF)
        case .indigo: Color(light: 0x3F4FC9, dark: 0x8C97FF)
        case .purple: Color(light: 0x7A4FD6, dark: 0xAE93FF)
        case .pink: Color(light: 0xC2347A, dark: 0xFF85C0)
        case .red: Color(light: 0xC62E3A, dark: 0xFF7A84)
        case .orange: Color(light: 0xC85A17, dark: 0xFF9A5C)
        case .amber: Color(light: 0xA86B00, dark: 0xF6C445)
        case .green: Color(light: 0x2E8B3A, dark: 0x6FD67E)
        case .teal: Color(light: 0x0E8A74, dark: 0x3CCFA9)
        case .cyan: Color(light: 0x0A7FA3, dark: 0x5AD2F4)
        case .brown: Color(light: 0x8A5A3C, dark: 0xD2A27F)
        case .graphite: Color(light: 0x5B6270, dark: 0xAEB4BF)
        }
    }

    var name: String { rawValue.capitalized }
}

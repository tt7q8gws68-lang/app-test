import SwiftUI

/// Stored by name so each course shows its light or dark variant automatically.
nonisolated enum CourseColor: String, Codable, CaseIterable {
    case blue, orange, purple, teal

    var color: Color {
        switch self {
        case .blue: Color(light: 0x0A62E0, dark: 0x5B97FF)
        case .orange: Color(light: 0xC85A17, dark: 0xFF9A5C)
        case .purple: Color(light: 0x7A4FD6, dark: 0xAE93FF)
        case .teal: Color(light: 0x0E8A74, dark: 0x3CCFA9)
        }
    }
}

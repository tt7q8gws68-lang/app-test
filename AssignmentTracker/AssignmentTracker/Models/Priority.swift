import SwiftUI

enum Priority: Int, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: Self { self }

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var color: Color {
        switch self {
        case .low: Palette.secondaryText
        case .medium: Palette.warning
        case .high: Palette.danger
        }
    }
}

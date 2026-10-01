import SwiftUI

/// Accent-colored icon plus title, used for rows in glass cards.
struct RowLabel: View {
    let title: String
    let icon: AppIcon.Name

    init(_ title: String, icon: AppIcon.Name) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(icon, size: 22)
                .foregroundStyle(Palette.accentText)
                .frame(width: 24)
            Text(title)
        }
    }
}

extension RowLabel {
    /// For the few rows the app's icon set has no glyph for (photo library): a regular-weight
    /// SF Symbol in the same accent color.
    struct SymbolFallback: View {
        let title: String
        let systemImage: String

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 24)
                Text(title)
            }
        }
    }
}

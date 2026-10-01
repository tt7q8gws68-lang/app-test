import SwiftUI

/// The header used by the tab-root screens: a small secondary line above a left-aligned large
/// title, with the screen's circular buttons on the right, level with the title.
struct ScreenHeader<Trailing: View>: View {
    let subtitle: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
                Text(title)
                    .font(.largeTitle.bold())
                    .tracking(-0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                trailing
            }
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(subtitle: String, title: String) {
        self.init(subtitle: subtitle, title: title) { EmptyView() }
    }
}

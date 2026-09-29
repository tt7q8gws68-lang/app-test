import SwiftUI

/// Small uppercase label above a group ("TODAY", "COURSE", "PRIORITY").
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Palette.secondaryText)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

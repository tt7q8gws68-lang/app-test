import SwiftUI

/// The floating glass tab bar: four equal tabs, each an icon over an 11pt label. The active tab
/// sits on a frosted pill in the accent text color.
struct DuskTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.snappy) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        AppIcon(tab.icon, size: 22)
                        Text(tab.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Palette.accentText : Palette.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Palette.selectedPill)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .frame(height: 64)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
    }
}

extension AppTab: CaseIterable {
    static var allCases: [AppTab] { [.assignments, .calendar, .courses, .streaks] }

    var title: String {
        switch self {
        case .assignments: "Assignments"
        case .calendar: "Calendar"
        case .courses: "Courses"
        case .streaks: "Streaks"
        }
    }

    var icon: AppIcon.Name {
        switch self {
        case .assignments: .assignments
        case .calendar: .calendar
        case .courses: .courses
        case .streaks: .streaks
        }
    }
}

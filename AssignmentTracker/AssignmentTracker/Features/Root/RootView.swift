import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case assignments, calendar, streaks
}

/// The tab bar from the mockups, plus app-wide celebrations when a streak or day is completed.
struct RootView: View {
    @Query private var assignments: [Assignment]
    @State private var tab: AppTab = .assignments
    @State private var celebration: Celebration?
    @State private var lastStats: HabitStats?

    private var stats: HabitStats {
        HabitStats(records: assignments.map(\.completionRecord))
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Assignments", systemImage: "checklist", value: AppTab.assignments) {
                AssignmentsView(streak: stats.currentStreak) { tab = .streaks }
            }
            Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                CalendarView()
            }
            Tab("Streaks", systemImage: "flame", value: AppTab.streaks) {
                StreaksView(stats: stats)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .top) {
            if let celebration {
                CelebrationToast(celebration: celebration)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { self.celebration = nil } }
            }
        }
        .sensoryFeedback(.success, trigger: celebration) { _, new in new != nil }
        .onChange(of: stats) { _, new in
            // The first value is just the app opening; only changes after that are celebrated.
            defer { lastStats = new }
            guard let old = lastStats, let found = new.celebration(since: old) else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { celebration = found }
        }
        .onAppear { lastStats = stats }
        .task(id: celebration) {
            guard celebration != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.snappy) { celebration = nil }
        }
    }
}

struct CelebrationToast: View {
    let celebration: Celebration
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: celebration.systemImage)
                .font(.title2)
                .foregroundStyle(.orange.gradient)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text(celebration.title)
                    .font(.subheadline.weight(.semibold))
                Text(celebration.detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .onAppear { bounce.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    RootView()
        .modelContainer(.preview)
}

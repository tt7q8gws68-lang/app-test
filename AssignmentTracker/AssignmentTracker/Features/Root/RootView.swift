import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case assignments, calendar, courses, streaks
}

/// The tab bar from the mockups, plus app-wide celebrations when a streak or day is completed.
struct RootView: View {
    @Query private var assignments: [Assignment]
    @State private var tab: AppTab = .assignments
    @State private var celebration: Celebration?
    @State private var lastStats: HabitStats?
    @State private var lastStatsDay = Calendar.current.startOfDay(for: .now)
    /// Start of the current day. Changing it rebuilds the tabs, so "Today", "Overdue" and the
    /// streak are right after the app sits in the background overnight or stays open past midnight.
    @State private var currentDay = Calendar.current.startOfDay(for: .now)
    @Environment(\.scenePhase) private var scenePhase

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
            Tab("Courses", systemImage: "books.vertical", value: AppTab.courses) {
                CoursesView()
            }
            Tab("Streaks", systemImage: "flame", value: AppTab.streaks) {
                StreaksView(stats: stats)
            }
        }
        .id(currentDay)
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
            // The first value is just the app opening, and a change of day isn't progress:
            // only changes within the same day are celebrated.
            let statsDay = lastStatsDay
            defer {
                lastStats = new
                lastStatsDay = Calendar.current.startOfDay(for: .now)
            }
            guard Calendar.current.isDateInToday(statsDay),
                  let old = lastStats, let found = new.celebration(since: old) else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { celebration = found }
        }
        .onAppear { lastStats = stats }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshDay()
        }
        .task(id: celebration) {
            guard celebration != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.snappy) { celebration = nil }
        }
    }
}

extension RootView {
    private func refreshDay() {
        let today = Calendar.current.startOfDay(for: .now)
        guard today != currentDay else { return }
        currentDay = today
        // A new day isn't an achievement: re-baseline so it can't trigger a celebration.
        lastStats = stats
        lastStatsDay = today
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

import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case assignments, calendar, courses, streaks
}

/// The four tabs in the system Liquid Glass tab bar (with the app's own icons), plus app-wide
/// celebrations when a streak or day is completed.
struct RootView: View {
    @Query private var assignments: [Assignment]
    @State private var tab: AppTab = .assignments
    /// The day shown in Calendar; the Assignments week strip sets it.
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @State private var calendarFocus = 0
    @State private var celebration: Celebration?
    /// Worked out when completion history changes (or the time does), not on every render.
    @State private var stats = HabitStats()
    @State private var lastStats: HabitStats?
    @State private var lastStatsDay = Calendar.current.startOfDay(for: .now)
    /// Finished items at the last update. Celebrations need this to go up, so deleting or
    /// rescheduling an open item can't trigger "All done for today" or a streak milestone.
    @State private var lastFinishedCount = 0
    /// The time the screens compare due dates against. It moves on at each due time, at midnight
    /// and when the app comes back, so "Today", "Overdue" and the streak stay right without
    /// rebuilding the tabs (which would throw away open sheets and navigation).
    @State private var now = Date.now
    @Environment(\.scenePhase) private var scenePhase

    private var records: [CompletionRecord] {
        assignments.map(\.completionRecord)
    }

    /// The soonest due time still ahead for open work: when something next turns overdue.
    private var nextDueTime: Date? {
        assignments.lazy.filter { !$0.isCompleted && $0.dueDate > now }.map(\.dueDate).min()
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.assignments) {
                AssignmentsView { day in
                    calendarDay = day
                    calendarFocus += 1
                    withAnimation(.snappy) { tab = .calendar }
                }
            } label: { AppTab.assignments.label }
            Tab(value: AppTab.calendar) {
                CalendarView(selectedDay: $calendarDay, focusRequest: calendarFocus)
            } label: { AppTab.calendar.label }
            Tab(value: AppTab.courses) {
                CoursesView()
            } label: { AppTab.courses.label }
            Tab(value: AppTab.streaks) {
                StreaksView(stats: stats)
            } label: { AppTab.streaks.label }
        }
        .environment(\.currentTime, now)
        .foregroundStyle(Palette.text)
        .overlay(alignment: .top) {
            if let celebration {
                CelebrationToast(celebration: celebration)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { self.celebration = nil } }
            }
        }
        .sensoryFeedback(.success, trigger: celebration) { _, new in new != nil }
        .onChange(of: records, initial: true) { _, records in
            updateStats(from: records, celebrate: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshTime() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshTime()
        }
        .task(id: nextDueTime) {
            guard let nextDueTime else { return }
            try? await Task.sleep(for: .seconds(max(nextDueTime.timeIntervalSinceNow, 0) + 1))
            guard !Task.isCancelled else { return }
            refreshTime()
        }
        .task(id: celebration) {
            guard celebration != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.snappy) { celebration = nil }
        }
    }
}

extension EnvironmentValues {
    /// The time screens compare due dates against, kept by `RootView` (see `now` there).
    @Entry var currentTime: Date = .now
}

extension AppTab {
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

    /// The tab bar item: the outline icon as a template image, tinted by the system bar.
    var label: Label<Text, Image> {
        Label(title, appIcon: icon)
    }
}

extension RootView {
    /// Moves `now` on; every screen that shows "Today" or "Overdue" reads it.
    private func refreshTime() {
        // Calendar was showing today: keep it on today once the day changes.
        let calendar = Calendar.current
        if calendar.isDate(calendarDay, inSameDayAs: now), !calendar.isDate(now, inSameDayAs: .now) {
            calendarDay = calendar.startOfDay(for: .now)
        }
        now = .now
        // Time passing isn't an achievement: update without celebrating.
        updateStats(from: records, celebrate: false)
    }

    private func updateStats(from records: [CompletionRecord], celebrate: Bool) {
        let new = HabitStats(records: records)
        // The first value is just the app opening, and a change of day isn't progress:
        // only changes within the same day are celebrated.
        let old = lastStats
        let statsDay = lastStatsDay
        let finished = records.filter { $0.completedAt != nil }.count
        let finishedMore = finished > lastFinishedCount
        stats = new
        lastStats = new
        lastStatsDay = Calendar.current.startOfDay(for: .now)
        lastFinishedCount = finished
        guard celebrate, finishedMore, Calendar.current.isDateInToday(statsDay),
              let old, let found = new.celebration(since: old) else { return }
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { celebration = found }
    }
}

struct CelebrationToast: View {
    let celebration: Celebration
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(celebration.icon, size: 26)
                .foregroundStyle(Palette.streakOrange)
                .scaleEffect(bounce ? 1 : 0.6)
                .animation(.spring(duration: 0.4, bounce: 0.5), value: bounce)
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
        .duskGlass(in: Capsule())
        .onAppear { bounce = true }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    RootView()
        .modelContainer(.preview)
}

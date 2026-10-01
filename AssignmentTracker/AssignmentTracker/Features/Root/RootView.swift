import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case assignments, calendar, courses, streaks
}

/// The four tabs under a floating Dusk tab bar, plus app-wide celebrations when a streak or day
/// is completed.
struct RootView: View {
    @Query private var assignments: [Assignment]
    @State private var tab: AppTab = .assignments
    @State private var tabBarVisibility = TabBarVisibility()
    /// The day shown in Calendar; the Assignments week strip sets it.
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
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
            Tab(value: AppTab.assignments) {
                AssignmentsView { day in
                    calendarDay = day
                    withAnimation(.snappy) { tab = .calendar }
                }
                .tabContent(barVisible: tabBarVisibility.isVisible)
            }
            Tab(value: AppTab.calendar) {
                CalendarView(selectedDay: $calendarDay)
                    .tabContent(barVisible: tabBarVisibility.isVisible)
            }
            Tab(value: AppTab.courses) {
                CoursesView()
                    .tabContent(barVisible: tabBarVisibility.isVisible)
            }
            Tab(value: AppTab.streaks) {
                StreaksView(stats: stats)
                    .tabContent(barVisible: tabBarVisibility.isVisible)
            }
        }
        .id(currentDay)
        .overlay(alignment: .bottom) {
            if tabBarVisibility.isVisible {
                DuskTabBar(selection: $tab)
                    // The system bar's soft scroll edge: content fades out under the bar, so
                    // the clear glass shows the glows rather than text running into the labels.
                    .background(alignment: .bottom) {
                        LinearGradient(
                            stops: [
                                .init(color: Palette.background.opacity(0), location: 0),
                                .init(color: Palette.background.opacity(0.75), location: 0.55),
                                .init(color: Palette.background.opacity(0.9), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 140)
                        .padding(.bottom, -30)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    // 30pt above the screen's bottom edge, which sits inside the bottom safe area.
                    .padding(.bottom, 30)
                    // Stays put (behind the keyboard) instead of riding up over the content.
                    .ignoresSafeArea(.all, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(tabBarVisibility)
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

private extension View {
    /// A tab's page: the system tab bar is replaced by `DuskTabBar`. While that bar shows, its
    /// scroll views add bottom room so the last row ends clear of it (the bar's top is 94pt above
    /// the screen edge; the home-indicator inset covers 34pt, plus 16pt breathing room).
    func tabContent(barVisible: Bool) -> some View {
        toolbarVisibility(.hidden, for: .tabBar)
            .environment(\.tabBarClearance, barVisible ? 76 : 0)
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

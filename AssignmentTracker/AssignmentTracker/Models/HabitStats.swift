import Foundation

/// The parts of an assignment the streak logic needs, so it can be tested without SwiftData.
nonisolated struct CompletionRecord: Equatable, Sendable {
    var dueDate: Date
    var createdAt: Date
    var completedAt: Date?

    init(dueDate: Date, createdAt: Date, completedAt: Date?) {
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// Only work added before it was due can be on time or late. Items created after their due
    /// date (past items from a syllabus import, say) don't count either way.
    var countsTowardStreak: Bool { createdAt < dueDate }

    var isOnTime: Bool {
        guard let completedAt else { return false }
        return completedAt <= dueDate
    }
}

nonisolated struct Badge: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let icon: AppIcon.Name
    /// Progress toward the badge, e.g. best streak 1 of 3. Unlocked when current ≥ goal.
    let current: Int
    let goal: Int
    /// Difficulty rank: the highest-tier unlocked badge stands in for the most recent one,
    /// since badges are worked out from history rather than stored with a date.
    let tier: Int

    var isUnlocked: Bool { current >= goal }
    var fraction: Double { goal == 0 ? 1 : min(Double(current) / Double(goal), 1) }
}

/// One day in the streak screen's Monday-to-Sunday strip.
nonisolated struct WeekDayStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Something was finished on time that day.
        case onTime
        /// A past day (or today so far) with nothing finished on time.
        case empty
        case future
    }

    var date: Date
    var kind: Kind
    var isToday: Bool
}

/// On-time streaks, perfect weeks and activity, worked out from completion history.
nonisolated struct HabitStats: Equatable, Sendable {
    /// On-time completions in a row, most recent last. Resets on anything finished late
    /// or left undone past its due time.
    var currentStreak = 0
    var bestStreak = 0
    /// Share of settled work (due in the last 30 days, or finished early) that was on time;
    /// nil when there's nothing to measure yet.
    var onTimeRate: Double?
    /// Monday-to-Sunday weeks, already over, where everything due was finished on time.
    var perfectWeeks = 0
    /// Finished at least a day before the due time.
    var earlyFinishes = 0
    var totalOnTime = 0
    /// Due today and still open, and due today in total (for "all done for today").
    var openToday = 0
    var dueToday = 0
    /// On-time completions per day, keyed by the start of the day they were finished.
    var activity: [Date: Int] = [:]

    var allDoneToday: Bool { dueToday > 0 && openToday == 0 }

    init() {}

    init(records: [CompletionRecord], now: Date = .now, calendar: Calendar = .current) {
        let counted = records.filter(\.countsTowardStreak)
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        // Settled items: finished, or past due. Open items not yet due can't break a streak.
        let settled = counted
            .filter { $0.completedAt != nil || $0.dueDate <= now }
            .sorted { ($0.dueDate, $0.completedAt ?? .distantFuture) < ($1.dueDate, $1.completedAt ?? .distantFuture) }

        var run = 0
        for record in settled {
            if record.isOnTime {
                run += 1
                bestStreak = max(bestStreak, run)
            } else {
                run = 0
            }
        }
        currentStreak = run
        totalOnTime = settled.filter(\.isOnTime).count

        earlyFinishes = counted.filter { record in
            guard let completedAt = record.completedAt else { return false }
            return completedAt <= record.dueDate.addingTimeInterval(-24 * 3600)
        }.count

        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        // Settled work due in the last 30 days, plus anything already finished ahead of time.
        let recent = settled.filter { $0.dueDate >= monthAgo }
        onTimeRate = recent.isEmpty ? nil : Double(recent.filter(\.isOnTime).count) / Double(recent.count)

        let today = counted.filter { $0.dueDate >= startOfToday && $0.dueDate < tomorrow }
        dueToday = today.count
        openToday = today.filter { $0.completedAt == nil }.count

        perfectWeeks = Self.perfectWeekCount(counted, now: now, calendar: calendar)

        for record in settled where record.isOnTime {
            activity[calendar.startOfDay(for: record.completedAt!), default: 0] += 1
        }
    }

    private static func perfectWeekCount(_ records: [CompletionRecord], now: Date, calendar: Calendar) -> Int {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let thisWeek = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let byWeek = Dictionary(grouping: records.filter { $0.dueDate < thisWeek }) {
            mondayCalendar.dateInterval(of: .weekOfYear, for: $0.dueDate)?.start ?? $0.dueDate
        }
        return byWeek.values.filter { $0.allSatisfy(\.isOnTime) }.count
    }

    // MARK: - Rewards

    static let streakMilestones = [3, 5, 10, 15, 25, 50, 100]

    var badges: [Badge] {
        [
            Badge(id: "first", title: "Off the Mark", detail: "Finish something on time",
                  icon: .badge, current: totalOnTime, goal: 1, tier: 0),
            Badge(id: "streak3", title: "Hat Trick", detail: "3 on time in a row",
                  icon: .streaks, current: bestStreak, goal: 3, tier: 1),
            Badge(id: "streak5", title: "On a Roll", detail: "5 on time in a row",
                  icon: .streaks, current: bestStreak, goal: 5, tier: 3),
            Badge(id: "streak10", title: "Ten Straight", detail: "10 on time in a row",
                  icon: .streaks, current: bestStreak, goal: 10, tier: 5),
            Badge(id: "streak25", title: "Unstoppable", detail: "25 on time in a row",
                  icon: .streaks, current: bestStreak, goal: 25, tier: 7),
            Badge(id: "perfectWeek", title: "Perfect Week", detail: "Everything on time for a week",
                  icon: .calendar, current: perfectWeeks, goal: 1, tier: 2),
            Badge(id: "perfectMonth", title: "Month of Focus", detail: "4 perfect weeks",
                  icon: .calendar, current: perfectWeeks, goal: 4, tier: 6),
            Badge(id: "early", title: "Early Bird", detail: "Finish 5 things a day early",
                  icon: .clock, current: earlyFinishes, goal: 5, tier: 4),
        ]
    }

    /// The hardest badge earned so far.
    var mostRecentEarned: Badge? {
        badges.filter(\.isUnlocked).max { $0.tier < $1.tier }
    }

    /// The locked badge closest to done; ties go to the easier one.
    var nextToEarn: Badge? {
        badges.filter { !$0.isUnlocked }.max { a, b in
            a.fraction == b.fraction ? a.tier > b.tier : a.fraction < b.fraction
        }
    }

    /// Monday to Sunday of the week containing `now`.
    func weekDays(now: Date = .now, calendar: Calendar = .current) -> [WeekDayStatus] {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let start = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start)!)
            let kind: WeekDayStatus.Kind = (activity[day] ?? 0) > 0 ? .onTime : (day > today ? .future : .empty)
            return WeekDayStatus(date: day, kind: kind, isToday: day == today)
        }
    }

    /// On-time completions during the week containing `now`.
    func onTimeThisWeek(now: Date = .now, calendar: Calendar = .current) -> Int {
        weekDays(now: now, calendar: calendar).reduce(0) { $0 + (activity[$1.date] ?? 0) }
    }

    /// What's worth celebrating in going from `old` to `self`, most notable first.
    func celebration(since old: HabitStats) -> Celebration? {
        let newBadges = badges.filter { badge in
            badge.isUnlocked && !(old.badges.first { $0.id == badge.id }?.isUnlocked ?? false)
        }
        if let badge = newBadges.first {
            return Celebration(title: "Badge unlocked: \(badge.title)", detail: badge.detail, icon: badge.icon)
        }
        if currentStreak > old.currentStreak, Self.streakMilestones.contains(currentStreak) {
            return Celebration(title: "\(currentStreak) on time in a row!", detail: "Keep the streak going",
                               icon: .streaks)
        }
        if allDoneToday, !old.allDoneToday {
            return Celebration(title: "All done for today", detail: currentStreak > 1 ? "Streak: \(currentStreak)" : "Nice work",
                               icon: .check)
        }
        return nil
    }
}

nonisolated struct Celebration: Equatable, Sendable {
    var title: String
    var detail: String
    var icon: AppIcon.Name
}

import Foundation

/// The numbers on the Assignments hero card, worked out from assignments.
///
/// The ring and "N to go" cover the same span as the list's Today and This week sections
/// (`WeekWindow`: today plus six days). The strip below is the Monday–Sunday calendar week.
nonisolated struct WeekHeroSummary: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var dueDate: Date
        var isCompleted: Bool
        var color: CourseColor?
    }

    struct Day: Equatable, Sendable {
        var date: Date
        var isToday: Bool
        var isPast: Bool
        /// One entry per assignment due that day (nil when it has no class).
        var dots: [CourseColor?]
    }

    var done = 0
    var total = 0
    /// Due today and still open.
    var dueToday = 0
    var days: [Day] = []

    var remaining: Int { total - done }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var dueTodayText: String { dueToday == 0 ? "Nothing due today" : "\(dueToday) due today" }

    init(items: [Item], now: Date = .now, calendar: Calendar = .current) {
        let window = WeekWindow(now: now, calendar: calendar)
        let inWindow = items.filter { window.contains($0.dueDate) }
        total = inWindow.count
        done = inWindow.filter(\.isCompleted).count
        dueToday = items.filter { !$0.isCompleted && calendar.isDate($0.dueDate, inSameDayAs: now) }.count

        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let monday = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start else { return }
        let today = calendar.startOfDay(for: now)
        days = (0..<7).map { offset in
            let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: monday)!)
            let due = items
                .filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
                .sorted { $0.dueDate < $1.dueDate }
            return Day(date: day, isToday: day == today, isPast: day < today, dots: due.map(\.color))
        }
    }

    /// "Friday, October 2, 1 due" for the strip's accessibility labels.
    static func accessibilityLabel(for day: Day) -> String {
        var parts = [day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if day.isToday { parts.append("today") }
        if !day.dots.isEmpty { parts.append("\(day.dots.count) due") }
        return parts.joined(separator: ", ")
    }
}

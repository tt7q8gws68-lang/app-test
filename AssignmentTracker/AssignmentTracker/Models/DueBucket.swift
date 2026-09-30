import Foundation

/// The list's groups, in display order.
enum DueBucket: Int, CaseIterable, Identifiable {
    case overdue, today, thisWeek, later, earlier

    var id: Self { self }

    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .thisWeek: "This week"
        case .later: "Later"
        case .earlier: "Earlier"
        }
    }

    static func of(_ assignment: Assignment, now: Date = .now, calendar: Calendar = .current) -> DueBucket {
        let window = WeekWindow(now: now, calendar: calendar)
        let due = assignment.dueDate
        if due < window.startOfToday { return assignment.isCompleted ? .earlier : .overdue }
        if due < window.startOfTomorrow { return .today }
        if due < window.end { return .thisWeek }
        return .later
    }
}

/// Today plus the next six days: the span covered by the Today and This week groups
/// and by the weekly progress card.
struct WeekWindow {
    let startOfToday: Date
    let startOfTomorrow: Date
    let end: Date

    init(now: Date = .now, calendar: Calendar = .current) {
        startOfToday = calendar.startOfDay(for: now)
        startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        end = calendar.date(byAdding: .day, value: 7, to: startOfToday)!
    }

    func contains(_ date: Date) -> Bool {
        date >= startOfToday && date < end
    }
}

extension Date {
    /// Short due label for list rows: "11:59 PM", "Thu, 9:00 AM", "Oct 12, 9:00 AM".
    func dueRowLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let time = formatted(date: .omitted, time: .shortened)
        if calendar.isDate(self, inSameDayAs: now) { return time }
        if calendar.isDateInYesterday(self) { return "Yesterday, \(time)" }
        if WeekWindow(now: now, calendar: calendar).contains(self) {
            return "\(formatted(.dateTime.weekday(.abbreviated))), \(time)"
        }
        let sameYear = calendar.isDate(self, equalTo: now, toGranularity: .year)
        let day = sameYear
            ? formatted(.dateTime.month(.abbreviated).day())
            : formatted(.dateTime.month(.abbreviated).day().year())
        return "\(day), \(time)"
    }

    /// Day label for the detail screen: "Today", "Tomorrow", "Thu, Oct 1".
    func dueDayLabel(calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

extension Date {
    /// "Today", "Tomorrow", "Thu", or "Oct 12" for a planned work day.
    func plannedLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        if WeekWindow(now: now, calendar: calendar).contains(self) {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

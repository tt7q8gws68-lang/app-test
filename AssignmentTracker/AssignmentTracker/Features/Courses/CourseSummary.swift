import Foundation

/// What a course row shows, worked out from its assignments.
nonisolated struct CourseSummary: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case noAssignments
        case caughtUp
        case open(Int)
    }

    var initials: String
    var state: State
    var nextTitle: String?
    var nextDue: Date?

    init(name: String, assignments: [(title: String, dueDate: Date, isCompleted: Bool)]) {
        initials = Self.initials(for: name)
        let open = assignments.filter { !$0.isCompleted }
        if assignments.isEmpty {
            state = .noAssignments
        } else if open.isEmpty {
            state = .caughtUp
        } else {
            state = .open(open.count)
        }
        // The earliest open item, overdue ones included: that's the most urgent.
        let next = open.min { $0.dueDate < $1.dueDate }
        nextTitle = next?.title
        nextDue = next?.dueDate
    }

    var openCount: Int {
        if case .open(let count) = state { count } else { 0 }
    }

    /// "Next: Problem Set 4 · Today", "All caught up" or "No assignments yet".
    func detail(now: Date = .now, calendar: Calendar = .current) -> String {
        switch state {
        case .noAssignments: return "No assignments yet"
        case .caughtUp: return "All caught up"
        case .open:
            guard let nextTitle, let nextDue else { return "" }
            return "Next: \(nextTitle) · \(Self.dueLabel(nextDue, now: now, calendar: calendar))"
        }
    }

    static func dueLabel(_ due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if due < now { return "Overdue" }
        if calendar.isDate(due, inSameDayAs: now) { return "Today" }
        return due.dueRowLabel(now: now, calendar: calendar)
    }

    /// First letters of the first two words ("Corporate Finance" → "CF", skipping "&"), or the
    /// first two letters of a single word ("Statistics" → "ST").
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { !$0.isEmpty }
        if words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
        }
        return String(words.first?.prefix(2) ?? "?").uppercased()
    }
}

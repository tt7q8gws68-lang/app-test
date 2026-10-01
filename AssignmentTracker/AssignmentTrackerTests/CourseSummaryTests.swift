import Foundation
import Testing
@testable import AssignmentTracker

struct CourseSummaryTests {
    let now = Fixtures.today

    private func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
        let start = Fixtures.calendar.startOfDay(for: now)
        return Fixtures.calendar.date(bySettingHour: hour, minute: minute, second: 0,
                                      of: Fixtures.calendar.date(byAdding: .day, value: offset, to: start)!)!
    }

    @Test(arguments: [
        ("Corporate Finance", "CF"),
        ("Money & Banking", "MB"),
        ("Statistics", "ST"),
        ("intro to psych", "IT"),
        ("ECON 220", "E2"),
        ("", "?"),
    ])
    func initials(name: String, expected: String) {
        #expect(CourseSummary.initials(for: name) == expected)
    }

    @Test func noAssignments() {
        let summary = CourseSummary(name: "Statistics", assignments: [])
        #expect(summary.state == .noAssignments)
        #expect(summary.detail(now: now, calendar: Fixtures.calendar) == "No assignments yet")
    }

    @Test func caughtUp() {
        let summary = CourseSummary(name: "Econometrics", assignments: [("Read Chapter 7", day(0), true)])
        #expect(summary.state == .caughtUp)
        #expect(summary.openCount == 0)
        #expect(summary.detail(now: now, calendar: Fixtures.calendar) == "All caught up")
    }

    @Test func nextIsEarliestOpenIncludingOverdue() {
        let summary = CourseSummary(name: "Corporate Finance", assignments: [
            ("Slides", day(5, 20, 0), false),
            ("Problem Set 4", day(-2), false),
            ("Done thing", day(-5), true),
        ])
        #expect(summary.state == .open(2))
        #expect(summary.detail(now: now, calendar: Fixtures.calendar) == "Next: Problem Set 4 · Overdue")
    }

    @Test func todayLabel() {
        let summary = CourseSummary(name: "Corporate Finance", assignments: [("Problem Set 4", day(0), false)])
        #expect(summary.detail(now: now, calendar: Fixtures.calendar) == "Next: Problem Set 4 · Today")
    }
}

import Foundation
import Testing
@testable import AssignmentTracker

struct DueBucketTests {
    let window = WeekWindow(now: Fixtures.today, calendar: Fixtures.calendar)

    private func bucket(_ due: Date, done: Bool = false) -> DueBucket {
        DueBucket.of(dueDate: due, isCompleted: done, in: window)
    }

    @Test func bucketsAroundTheWeekWindow() {
        // Today is Tue Sep 29, 2026 at 10:00.
        #expect(bucket(Fixtures.date(2026, 9, 28, 23, 59)) == .overdue)
        #expect(bucket(Fixtures.date(2026, 9, 28, 23, 59), done: true) == .earlier)
        // Earlier today but past its time still counts as Today, not Overdue.
        #expect(bucket(Fixtures.date(2026, 9, 29, 8, 0)) == .today)
        #expect(bucket(Fixtures.date(2026, 9, 29, 23, 59)) == .today)
        #expect(bucket(Fixtures.date(2026, 9, 30, 0, 0)) == .thisWeek)
        #expect(bucket(Fixtures.date(2026, 10, 5, 23, 59)) == .thisWeek)
        #expect(bucket(Fixtures.date(2026, 10, 6, 0, 0)) == .later)
    }
}

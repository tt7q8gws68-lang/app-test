import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import AssignmentTracker

struct SVGPathTests {
    private func bounds(_ data: String) -> CGRect {
        SVGPath.path(data).boundingRect
    }

    private func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.05) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test func absoluteAndRelativeLines() {
        #expect(close(bounds("M14.5 6l-6 6 6 6"), CGRect(x: 8.5, y: 6, width: 6, height: 12)))
        #expect(close(bounds("M12 5.5v13M5.5 12h13"), CGRect(x: 5.5, y: 5.5, width: 13, height: 13)))
        #expect(close(bounds("M6.5 20V4.5M6.5 5h10l-2 3.75 2 3.75h-10"), CGRect(x: 6.5, y: 4.5, width: 10, height: 15.5)))
    }

    @Test func compactNumbersParse() {
        // "c0-1.9.8-3.2 1.8-4.1" packs six numbers with no separators between some of them.
        let path = SVGPath.path("M0 0c0-1.9.8-3.2 1.8-4.1")
        #expect(abs(path.currentPoint!.x - 1.8) < 0.001)
        #expect(abs(path.currentPoint!.y - -4.1) < 0.001)
    }

    @Test func arcsLandOnTheirEndpoints() {
        // A half circle of radius 5.5 from (6.5, 11) over the top to (17.5, 11).
        let path = SVGPath.path("M6.5 11a5.5 5.5 0 0 1 11 0")
        #expect(abs(path.currentPoint!.x - 17.5) < 0.001)
        let box = path.boundingRect
        #expect(abs(box.minY - 5.5) < 0.05) // the top of the arc
        #expect(abs(box.width - 11) < 0.05)
    }

    @Test func circleAndRoundedRectElements() {
        let search = SVGPath.path(for: AppIcon.Name.search.elements).boundingRect
        #expect(close(search, CGRect(x: 5, y: 5, width: 14.5, height: 14.5)))
        let assignments = SVGPath.path(for: AppIcon.Name.assignments.elements).boundingRect
        #expect(close(assignments, CGRect(x: 4, y: 4, width: 16, height: 16)))
    }

    @Test(arguments: AppIcon.Name.allCases)
    func everyIconFitsTheGrid(name: AppIcon.Name) {
        let box = name.gridPath.boundingRect
        #expect(!box.isEmpty || name == .more, "\(name) produced no geometry")
        #expect(box.minX >= 3 && box.minY >= 3 && box.maxX <= 21 && box.maxY <= 21, "\(name) spills outside the grid: \(box)")
    }

    @Test func iconShapeScalesToItsFrame() {
        let path = IconShape(name: .assignments).path(in: CGRect(x: 0, y: 0, width: 48, height: 48))
        let box = path.boundingRect
        #expect(abs(box.minX - 8) < 0.1 && abs(box.width - 32) < 0.1)
    }
}

struct WeekHeroSummaryTests {
    let calendar = Fixtures.calendar
    /// Tue Sep 29, 2026, 10:00.
    let now = Fixtures.today

    private func day(_ offset: Int, _ hour: Int = 23) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: offset, to: start)!)!
    }

    private func summary(_ items: [WeekHeroSummary.Item]) -> WeekHeroSummary {
        WeekHeroSummary(items: items, now: now, calendar: calendar)
    }

    @Test func countsTheWeekWindow() {
        let result = summary([
            .init(dueDate: day(0, 17), isCompleted: true, color: .pink),
            .init(dueDate: day(0), isCompleted: false, color: .blue),
            .init(dueDate: day(3), isCompleted: false, color: .teal),
            .init(dueDate: day(9), isCompleted: false, color: .blue),   // beyond the window
            .init(dueDate: day(-2), isCompleted: false, color: .blue),  // overdue: not this week
        ])
        #expect(result.total == 3)
        #expect(result.done == 1)
        #expect(result.remaining == 2)
        #expect(abs(result.fraction - 1.0 / 3) < 0.0001)
        #expect(result.dueToday == 1)
        #expect(result.dueTodayText == "1 due today")
    }

    @Test func emptyWeek() {
        let result = summary([])
        #expect(result.total == 0)
        #expect(result.fraction == 0)
        #expect(result.dueTodayText == "Nothing due today")
        #expect(result.days.count == 7)
        #expect(result.days.allSatisfy { $0.dots.isEmpty })
    }

    @Test func stripRunsMondayToSundayWithDots() {
        // Today is Tuesday; Monday is yesterday.
        let result = summary([
            .init(dueDate: day(-1), isCompleted: true, color: .purple),
            .init(dueDate: day(0, 9), isCompleted: false, color: .blue),
            .init(dueDate: day(0, 17), isCompleted: false, color: nil),
            .init(dueDate: day(5), isCompleted: false, color: .teal), // Sunday
        ])
        #expect(result.days.map { calendar.component(.weekday, from: $0.date) } == [2, 3, 4, 5, 6, 7, 1])
        #expect(result.days.map(\.isPast) == [true, false, false, false, false, false, false])
        #expect(result.days.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(result.days[0].dots == [.purple])
        #expect(result.days[1].dots == [.blue, nil])
        #expect(result.days[6].dots == [.teal])
    }

    @Test func accessibilityLabelReadsNaturally() {
        let result = summary([.init(dueDate: day(3), isCompleted: false, color: .teal)])
        #expect(WeekHeroSummary.accessibilityLabel(for: result.days[4]) == "Friday, October 2, 1 due")
        #expect(WeekHeroSummary.accessibilityLabel(for: result.days[1]) == "Tuesday, September 29, today")
    }
}

@MainActor
struct DuskMigrationTests {
    @Test func econometricsMovesFromOrangeToPinkOnce() throws {
        let defaults = UserDefaults(suiteName: "DuskMigrationTests")!
        defaults.removePersistentDomain(forName: "DuskMigrationTests")
        let container = try ModelContainer(for: ModelContainer.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let econometrics = Course(name: "Econometrics", color: .orange, sortIndex: 0)
        let other = Course(name: "Organic Chemistry", color: .orange, sortIndex: 1)
        context.insert(econometrics)
        context.insert(other)

        SampleData.migrateToDuskColors(context, defaults: defaults)
        #expect(econometrics.colorToken == .pink)
        #expect(other.colorToken == .orange)

        // Runs only once: a later deliberate choice of orange sticks.
        econometrics.colorToken = .orange
        SampleData.migrateToDuskColors(context, defaults: defaults)
        #expect(econometrics.colorToken == .orange)
    }
}

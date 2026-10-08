import Foundation
import SwiftData
import Testing
@testable import AssignmentTracker

@MainActor
struct CoreFlowTests {
    let calendar = Fixtures.calendar
    let now = Fixtures.today
    let window = WeekWindow(now: Fixtures.today, calendar: Fixtures.calendar)

    /// The container must outlive the context, so tests hold on to both.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: ModelContainer.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Due `offset` days from the fixed today at the given time.
    private func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: offset, to: start)!)!
    }

    private func bucket(_ a: Assignment) -> DueBucket {
        DueBucket.of(dueDate: a.dueDate, isCompleted: a.isCompleted, in: window)
    }

    private func summary(_ name: String, _ items: [Assignment]) -> CourseSummary {
        CourseSummary(name: name, assignments: items.map { ($0.title, $0.dueDate, $0.isCompleted) })
    }

    // MARK: 1. Completing

    @Test func setCompletedSetsAndClearsCompletedAt() {
        let a = Assignment(title: "Essay", dueDate: day(3))
        #expect(!a.isCompleted && a.completedAt == nil)
        #expect(a.completionRecord.completedAt == nil)

        a.setCompleted(true)
        #expect(a.isCompleted)
        #expect(a.completedAt != nil)
        #expect(a.completionRecord.completedAt == a.completedAt)
        #expect(a.completionRecord.dueDate == a.dueDate)

        a.setCompleted(false)
        #expect(!a.isCompleted)
        #expect(a.completedAt == nil)
        #expect(a.completionRecord.completedAt == nil)
    }

    @Test func toggleCompletedFlipsStateBothWays() {
        let a = Assignment(title: "Essay", dueDate: day(3))
        a.toggleCompleted()
        #expect(a.isCompleted && a.completedAt != nil)
        a.toggleCompleted()
        #expect(!a.isCompleted && a.completedAt == nil)
    }

    @Test func completionRecordIgnoresStaleCompletedAtWhenOpen() {
        let a = Assignment(title: "Essay", dueDate: day(3))
        a.completedAt = day(-1)
        #expect(a.completionRecord.completedAt == nil)
    }

    @Test func completingEarlyCountsOnTimeAndRaisesStreak() {
        // Due far in the future so completing "now" is always before the due date.
        let due = Fixtures.date(2100, 1, 1)
        let a = Assignment(title: "Early", dueDate: due)
        a.createdAt = day(-30)
        let before = HabitStats(records: [a.completionRecord], now: now, calendar: calendar)
        #expect(before.currentStreak == 0 && before.totalOnTime == 0)

        a.setCompleted(true)
        #expect(a.completionRecord.isOnTime)
        let after = HabitStats(records: [a.completionRecord], now: now, calendar: calendar)
        #expect(after.currentStreak == 1)
        #expect(after.bestStreak == 1)
        #expect(after.totalOnTime == 1)

        a.setCompleted(false)
        let undone = HabitStats(records: [a.completionRecord], now: now, calendar: calendar)
        #expect(undone.currentStreak == 0)
        #expect(undone.totalOnTime == 0)
    }

    // MARK: 2. Planning

    @Test func planStoresStartOfDayAndNilClears() {
        let a = Assignment(title: "Lab", dueDate: day(4))
        a.plan(for: day(2, 15, 45), calendar: calendar)
        #expect(a.plannedDate == calendar.startOfDay(for: day(2)))

        a.plan(for: nil, calendar: calendar)
        #expect(a.plannedDate == nil)
    }

    // MARK: 3. Deleting

    @Test func deletingAssignmentCascadesToItsSteps() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = Assignment(title: "Project", dueDate: day(5))
        let keep = Assignment(title: "Other", dueDate: day(6))
        context.insert(a)
        context.insert(keep)
        for i in 0..<3 { a.steps.append(Step(title: "Step \(i)", sortIndex: i)) }
        keep.steps.append(Step(title: "Survivor", sortIndex: 0))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Step>()) == 4)

        a.delete(from: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Assignment>()) == 1)
        let steps = try context.fetch(FetchDescriptor<Step>())
        #expect(steps.map(\.title) == ["Survivor"])
    }

    @Test func deletingCourseNullifiesAssignmentsButKeepsThem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let course = Course(name: "Statistics", color: .blue, sortIndex: 0)
        context.insert(course)
        let a = Assignment(title: "PS1", dueDate: day(2))
        let b = Assignment(title: "PS2", dueDate: day(3))
        context.insert(a)
        context.insert(b)
        a.course = course
        b.course = course
        try context.save()
        #expect(course.assignments.count == 2)

        context.delete(course)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
        let remaining = try context.fetch(FetchDescriptor<Assignment>())
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { $0.course == nil })
    }

    // MARK: 4. Steps

    @Test func sortedStepsOrdersBySortIndexRegardlessOfInsertion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = Assignment(title: "Project", dueDate: day(5))
        context.insert(a)
        for (title, index) in [("third", 2), ("first", 0), ("fourth", 3), ("second", 1)] {
            a.steps.append(Step(title: title, sortIndex: index))
        }
        #expect(a.sortedSteps.map(\.title) == ["first", "second", "third", "fourth"])
    }

    // MARK: 5. Bucketing

    @Test func mixedSetBucketsAndOpenCounts() {
        let items = [
            Assignment(title: "overdue open", dueDate: day(-2)),
            Assignment(title: "overdue open 2", dueDate: day(-1)),
            Assignment(title: "overdue done", dueDate: day(-3)),
            Assignment(title: "today open", dueDate: day(0)),
            Assignment(title: "today done", dueDate: day(0, 8, 0)),
            Assignment(title: "day 1", dueDate: day(1)),
            Assignment(title: "day 6", dueDate: day(6)),
            Assignment(title: "day 7", dueDate: Fixtures.date(2026, 10, 6, 0, 0)),
            Assignment(title: "far later done", dueDate: day(40)),
        ]
        for title in ["overdue done", "today done", "far later done"] {
            items.first { $0.title == title }!.setCompleted(true)
        }
        let grouped = Dictionary(grouping: items, by: bucket)
        func titles(_ b: DueBucket) -> Set<String> { Set((grouped[b] ?? []).map(\.title)) }
        func open(_ b: DueBucket) -> Int { (grouped[b] ?? []).filter { !$0.isCompleted }.count }

        #expect(titles(.overdue) == ["overdue open", "overdue open 2"])
        #expect(titles(.earlier) == ["overdue done"])
        #expect(titles(.today) == ["today open", "today done"])
        #expect(titles(.thisWeek) == ["day 1", "day 6"])
        #expect(titles(.later) == ["day 7", "far later done"])

        #expect(open(.overdue) == 2)
        #expect(open(.earlier) == 0)
        #expect(open(.today) == 1)
        #expect(open(.thisWeek) == 2)
        #expect(open(.later) == 1)
    }

    @Test func completingMovesAnOverdueItemToEarlier() {
        let a = Assignment(title: "late", dueDate: day(-2))
        #expect(bucket(a) == .overdue)
        a.setCompleted(true)
        #expect(bucket(a) == .earlier)
        a.setCompleted(false)
        #expect(bucket(a) == .overdue)
    }

    // MARK: 6. Course summary

    @Test func courseSummaryWithMixedItems() {
        let items = [
            Assignment(title: "Slides", dueDate: day(5)),
            Assignment(title: "Problem Set 4", dueDate: day(-2)),
            Assignment(title: "Quiz", dueDate: day(1)),
            Assignment(title: "Done thing", dueDate: day(-5)),
        ]
        items[3].setCompleted(true)
        let s = summary("Corporate Finance", items)
        #expect(s.state == .open(3))
        #expect(s.openCount == 3)
        #expect(s.nextTitle == "Problem Set 4")
        #expect(s.nextDue == day(-2))

        items[1].setCompleted(true)
        let after = summary("Corporate Finance", items)
        #expect(after.openCount == 2)
        #expect(after.nextTitle == "Quiz")

        items.forEach { $0.setCompleted(true) }
        let done = summary("Corporate Finance", items)
        #expect(done.state == .caughtUp)
        #expect(done.openCount == 0)
        #expect(done.nextTitle == nil && done.nextDue == nil)
    }

    @Test func courseRelationshipFeedsSummary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let course = Course(name: "Statistics", color: .teal, sortIndex: 0)
        context.insert(course)
        let a = Assignment(title: "PS1", dueDate: day(2))
        context.insert(a)
        a.course = course
        #expect(course.assignments.map(\.title) == ["PS1"])
        #expect(summary(course.name, course.assignments).state == .open(1))
    }

    // MARK: 7. Edge cases

    @Test func emptyDataDoesNotCrashAndIsZeroed() {
        let hero = WeekHeroSummary(items: [], now: now, calendar: calendar)
        #expect(hero.total == 0 && hero.done == 0 && hero.remaining == 0)
        #expect(hero.fraction == 0)
        #expect(hero.dueToday == 0)
        #expect(hero.days.count == 7)
        #expect(hero.days.allSatisfy { $0.dots.isEmpty })

        let stats = HabitStats(records: [], now: now, calendar: calendar)
        #expect(stats.currentStreak == 0 && stats.bestStreak == 0 && stats.totalOnTime == 0)
        #expect(stats.onTimeRate == nil)
        #expect(stats.perfectWeeks == 0)
        #expect(!stats.allDoneToday)
        #expect(stats.activity.isEmpty)

        let course = CourseSummary(name: "Empty", assignments: [])
        #expect(course.state == .noAssignments)
        #expect(course.openCount == 0)
        #expect(course.nextTitle == nil)
    }

    @Test func emptyTitleAndExtremeDatesAreHandled() {
        let blank = Assignment(title: "", dueDate: day(0))
        let ancient = Assignment(title: "ancient", dueDate: Fixtures.date(1900, 1, 1))
        let distant = Assignment(title: "distant", dueDate: Fixtures.date(2999, 12, 31))
        let items = [blank, ancient, distant]

        #expect(bucket(blank) == .today)
        #expect(bucket(ancient) == .overdue)
        #expect(bucket(distant) == .later)
        ancient.setCompleted(true)
        #expect(bucket(ancient) == .earlier)

        let hero = WeekHeroSummary(
            items: items.map { .init(dueDate: $0.dueDate, isCompleted: $0.isCompleted, color: nil) },
            now: now, calendar: calendar)
        #expect(hero.total == 1)
        #expect(hero.dueToday == 1)

        let stats = HabitStats(records: items.map(\.completionRecord), now: now, calendar: calendar)
        #expect(stats.currentStreak >= 0)

        let s = summary("", items)
        #expect(s.initials == "?")
        #expect(s.nextTitle == "")
        #expect(s.openCount == 2)
    }

    @Test func itemsCreatedAfterTheirDueDateDoNotCountTowardStreaks() {
        let imported = Assignment(title: "imported", dueDate: day(-10))
        imported.createdAt = day(0, 9, 0)
        imported.setCompleted(true)
        let missedImport = Assignment(title: "missed import", dueDate: day(-8))
        missedImport.createdAt = day(0, 9, 0)

        #expect(!imported.completionRecord.countsTowardStreak)
        let stats = HabitStats(records: [imported, missedImport].map(\.completionRecord), now: now, calendar: calendar)
        #expect(stats.currentStreak == 0)
        #expect(stats.bestStreak == 0)
        #expect(stats.totalOnTime == 0)
        #expect(stats.onTimeRate == nil)

        // A real on-time item next to them still gives a streak of exactly one.
        let real = Assignment(title: "real", dueDate: day(-1))
        real.createdAt = day(-20)
        real.completedAt = day(-1, 12)
        real.isCompleted = true
        let mixed = HabitStats(records: [imported, missedImport, real].map(\.completionRecord), now: now, calendar: calendar)
        #expect(mixed.currentStreak == 1)
        #expect(mixed.totalOnTime == 1)
    }

    @Test func weekHeroCountsOnlyTheWindow() {
        let items: [WeekHeroSummary.Item] = [
            .init(dueDate: day(-1), isCompleted: false, color: nil),   // before window
            .init(dueDate: day(0), isCompleted: true, color: .blue),
            .init(dueDate: day(0, 18, 0), isCompleted: false, color: nil),
            .init(dueDate: day(6), isCompleted: false, color: .teal),
            .init(dueDate: Fixtures.date(2026, 10, 6, 0, 0), isCompleted: false, color: nil), // day 7: outside
        ]
        let hero = WeekHeroSummary(items: items, now: now, calendar: calendar)
        #expect(hero.total == 3)
        #expect(hero.done == 1)
        #expect(hero.remaining == 2)
        #expect(hero.dueToday == 1)
    }
}

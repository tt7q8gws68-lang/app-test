import Foundation
import Testing
@testable import AssignmentTracker

/// All tests run against a fixed "today" of Tue Sep 29, 2026.
enum Fixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let today = date(2026, 9, 29, 10, 0)
    /// Monday, first day of the fall term.
    static let fallStart = date(2026, 8, 31)
}

struct SyllabusDateResolverTests {
    let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: Fixtures.fallStart, referenceDate: Fixtures.today)
    let noTerm = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: nil, referenceDate: Fixtures.today)

    // MARK: Explicit dates

    @Test(arguments: [
        ("Oct 12", Fixtures.date(2026, 10, 12, 23, 59)),
        ("October 12th", Fixtures.date(2026, 10, 12, 23, 59)),
        ("Oct. 12, 2027", Fixtures.date(2027, 10, 12, 23, 59)),
        ("12 October", Fixtures.date(2026, 10, 12, 23, 59)),
        ("10/12", Fixtures.date(2026, 10, 12, 23, 59)),
        ("10/12/27", Fixtures.date(2027, 10, 12, 23, 59)),
        ("2026-11-03", Fixtures.date(2026, 11, 3, 23, 59)),
        ("Sept 3", Fixtures.date(2026, 9, 3, 23, 59)),
    ])
    func explicitDates(text: String, expected: Date) {
        let result = resolver.resolve(text)
        #expect(result.date == expected)
        #expect(result.status == .confident)
    }

    @Test(arguments: [
        ("Oct 12 at 5pm", 17, 0),
        ("Oct 12, 11:59 PM", 23, 59),
        ("Oct 12 by 9:30 a.m.", 9, 30),
        ("Oct 12 at noon", 12, 0),
        ("Oct 12 at midnight", 23, 59),
        ("Oct 12 14:00", 14, 0),
        ("Oct 12 12am", 0, 0),
    ])
    func times(text: String, hour: Int, minute: Int) {
        let date = try! #require(resolver.resolve(text).date)
        #expect(Fixtures.calendar.component(.hour, from: date) == hour)
        #expect(Fixtures.calendar.component(.minute, from: date) == minute)
    }

    @Test func missingTimeUsesEndOfDay() {
        let date = try! #require(resolver.resolve("Nov 2").date)
        #expect(Fixtures.calendar.component(.hour, from: date) == 23)
        #expect(Fixtures.calendar.component(.minute, from: date) == 59)
    }

    // MARK: Year inference

    @Test func yearlessDatesStayInTheTerm() {
        #expect(resolver.resolve("Aug 31").date == Fixtures.date(2026, 8, 31, 23, 59))
        #expect(resolver.resolve("Dec 10").date == Fixtures.date(2026, 12, 10, 23, 59))
        #expect(resolver.resolve("Jan 5").date == Fixtures.date(2027, 1, 5, 23, 59))
    }

    @Test func yearlessDatesWithoutTermLookBackFourMonths() {
        // Imported late in September: early-fall dates stay in 2026.
        #expect(noTerm.resolve("Aug 31").date == Fixtures.date(2026, 8, 31, 23, 59))
        #expect(noTerm.resolve("Feb 14").date == Fixtures.date(2027, 2, 14, 23, 59))
    }

    @Test func invalidDateIsMissing() {
        let result = resolver.resolve("Feb 30")
        #expect(result.date == nil)
        if case .missing = result.status {} else { Issue.record("expected missing, got \(result.status)") }
    }

    // MARK: Ranges and weekdays

    @Test func rangeUsesLastDayAndAsksForReview() {
        let result = resolver.resolve("Oct 12–14")
        #expect(result.date == Fixtures.date(2026, 10, 14, 23, 59))
        #expect(result.status == .needsReview("Date range in syllabus – using the last day"))
    }

    @Test func rangeAcrossMonths() {
        #expect(resolver.resolve("Oct 30 - Nov 2").date == Fixtures.date(2026, 11, 2, 23, 59))
        #expect(resolver.resolve("10/30 – 11/2").date == Fixtures.date(2026, 11, 2, 23, 59))
    }

    @Test func matchingWeekdayIsConfident() {
        // Oct 12, 2026 is a Monday.
        #expect(resolver.resolve("Mon, Oct 12").status == .confident)
    }

    @Test func mismatchedWeekdayIsFlagged() {
        let result = resolver.resolve("Tue, Oct 12")
        #expect(result.date == Fixtures.date(2026, 10, 12, 23, 59))
        #expect(result.status == .needsReview("Syllabus says Tuesday but that date is a Monday"))
    }

    // MARK: Relative weeks

    @Test(arguments: [
        ("Week 3, Friday", Fixtures.date(2026, 9, 18, 23, 59)),
        ("Week 3 Fri", Fixtures.date(2026, 9, 18, 23, 59)),
        ("Wk 1 Monday", Fixtures.date(2026, 8, 31, 23, 59)),
        ("Friday of week 3 at 9am", Fixtures.date(2026, 9, 18, 9, 0)),
        ("week 10, Wednesday", Fixtures.date(2026, 11, 4, 23, 59)),
    ])
    func relativeWeeks(text: String, expected: Date) {
        let result = resolver.resolve(text)
        #expect(result.date == expected)
        #expect(result.status == .confident)
    }

    @Test func weekWithoutDayDefaultsToFridayForReview() {
        let result = resolver.resolve("Week 5")
        #expect(result.date == Fixtures.date(2026, 10, 2, 23, 59))
        #expect(result.status == .needsReview("Only the week is given – using Friday"))
    }

    @Test func weekRangeUsesLastWeek() {
        let result = resolver.resolve("Weeks 3-4, Friday")
        #expect(result.date == Fixtures.date(2026, 9, 25, 23, 59))
        if case .needsReview = result.status {} else { Issue.record("expected review") }
    }

    @Test func weekStartingMidweekAnchorsToThatWeeksMonday() {
        // Classes start on a Wednesday; Week 1 still runs Monday to Sunday.
        let midweek = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: Fixtures.date(2026, 9, 2), referenceDate: Fixtures.today)
        #expect(midweek.resolve("Week 2, Monday").date == Fixtures.date(2026, 9, 7, 23, 59))
    }

    @Test func relativeWeekNeedsTermStart() {
        let result = noTerm.resolve("Week 3, Friday")
        #expect(result.date == nil)
        #expect(result.status == .missing("Set the semester start date to place Week 3"))
    }

    @Test func explicitDateBeatsWeekLabel() {
        #expect(resolver.resolve("Oct 16 (Week 7)").date == Fixtures.date(2026, 10, 16, 23, 59))
    }

    // MARK: Missing

    @Test(arguments: ["TBA", "Date TBD", "to be announced", "", "end of the month", "Satisfactory"])
    func noUsableDate(text: String) {
        let result = resolver.resolve(text)
        #expect(result.date == nil)
        if case .missing = result.status {} else { Issue.record("“\(text)” should be missing, got \(result.status)") }
    }

    // MARK: Finding expressions

    @Test func findsDateWithWeekdayAndTime() {
        let expression = resolver.firstExpression(in: "Problem Set 1 due Mon, Oct 12 at 11:59pm (5%)")
        #expect(expression?.text == "Mon, Oct 12 at 11:59pm")
    }

    @Test func findsWeekWithDay() {
        #expect(resolver.firstExpression(in: "Quiz 2 — Week 6, Thursday")?.text == "Week 6, Thursday")
    }

    @Test func monthIsNotAWeekday() {
        #expect(resolver.firstExpression(in: "Reading list for the month") == nil)
    }

    @Test(arguments: [
        "Classes begin Monday, August 31, 2026.",
        "First day of classes: 8/31/2026",
        "The semester starts Aug 31",
    ])
    func findsTermStart(text: String) {
        #expect(noTerm.termStart(in: "FIN 301\n\(text)\nOffice hours: Tue 2-4pm") == Fixtures.date(2026, 8, 31))
    }
}

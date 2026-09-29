import Foundation
import Testing
@testable import AssignmentTracker

struct RuleBasedSyllabusParserTests {
    let parser = RuleBasedSyllabusParser(calendar: Fixtures.calendar, referenceDate: Fixtures.today)

    @Test func tableScheduleWithGradingBreakdown() throws {
        let text = """
        FIN 301 — Corporate Finance
        Fall 2026 · Prof. Rivera
        Classes begin Monday, August 31, 2026.

        GRADING
        Problem Sets ............ 20%
        Midterm Exam ............ 25%
        Final Exam .............. 30%
        Group Project ........... 20%
        Participation ........... 5%

        SCHEDULE
        Date        Topic                         Due
        Sep 14      Time value of money           Problem Set 1 (4%)
        Sep 28      Bond valuation                Problem Set 2 (4%)
        Oct 12      No class — Fall break
        Oct 15      Midterm Exam (in class, 9:30am)
        Nov 2–6     Project proposal due
        Dec 14      Final Exam, 8:00 AM
        """
        let result = parser.parse(text)

        #expect(result.termStart == Fixtures.date(2026, 8, 31))
        #expect(result.items.map(\.title) == [
            "Problem Set 1", "Problem Set 2", "Midterm Exam", "Project proposal", "Final Exam",
        ])
        #expect(result.items.map(\.kind) == [.assignment, .assignment, .exam, .project, .exam])
        #expect(result.items.map(\.dateText) == [
            "Sep 14", "Sep 28", "Oct 15 at 9:30am", "Nov 2–6", "Dec 14 at 8:00 AM",
        ])
        // Row weights win; grading-section weights fill in the rest.
        #expect(result.items.map(\.weight) == ["4%", "4%", "25%", nil, "30%"])
    }

    @Test func weekByWeekScheduleResolvesThroughHeaders() throws {
        let text = """
        ECON 220 Econometrics
        Week 1 (Aug 31 – Sep 4): Introduction
        Week 2: Regression basics
          Tue: Read Chapter 2
        Week 3: Inference
          Fri: Quiz 1
          Problem Set 1 due
        """
        let result = parser.parse(text)

        // The term start comes from the "Week 1 (Aug 31 …)" header.
        #expect(result.termStart == Fixtures.date(2026, 8, 31))
        #expect(result.items.map(\.title) == ["Read Chapter 2", "Quiz 1", "Problem Set 1"])
        #expect(result.items.map(\.dateText) == ["Week 2, Tue", "Week 3, Fri", "Week 3"])
        #expect(result.items.map(\.kind) == [.reading, .quiz, .assignment])

        let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: result.termStart, referenceDate: Fixtures.today)
        #expect(resolver.resolve(result.items[1].dateText!).date == Fixtures.date(2026, 9, 18, 23, 59))
    }

    @Test func syllabusWithoutDatesStillListsItems() {
        let text = """
        Course requirements
        Weekly reading responses — 20%
        Midterm paper — 30%
        Final exam — 50%
        """
        let result = parser.parse(text)
        #expect(result.items.count == 3)
        #expect(result.items.allSatisfy { $0.dateText == nil })
        #expect(result.items.map(\.weight) == ["20%", "30%", "50%"])
    }

    @Test func ignoresPolicyAndLogistics() {
        let text = """
        Office hours: Tue 2–4pm
        Late policy: assignments lose 10% per day
        Oct 12: No class (holiday)
        Oct 14: Essay 1 due
        """
        #expect(parser.parse(text).items.map(\.title) == ["Essay 1"])
    }

    @Test func policySentenceDoesNotBorrowADate() {
        let text = "Classes begin Monday, August 31, 2026. All problem sets are submitted on Canvas by 11:59 PM on the due date."
        let result = parser.parse(text)
        #expect(result.items.isEmpty)
        #expect(result.termStart == Fixtures.date(2026, 8, 31))
    }

    @Test func dateDoesNotCarryIntoTheNextSentence() {
        let items = parser.parse("Oct 12: review session. Essay 2 due at the end of term").items
        #expect(items.count == 1)
        #expect(items[0].dateText == nil)
    }

    @Test func splitsSeveralItemsOnOneLine() {
        let items = parser.parse("Oct 20: Quiz 3; Lab report 2 due").items
        #expect(items.map(\.title) == ["Quiz 3", "Lab report 2"])
        #expect(items.map(\.dateText) == ["Oct 20", "Oct 20"])
    }

    @Test(arguments: [
        ("Final Project presentation", AssignmentKind.project),
        ("Final Exam", .exam),
        ("Final", .exam),
        ("Read Chapter 7", .reading),
        ("Problem Set 3", .assignment),
        ("HW 4", .assignment),
        ("Quiz 2", .quiz),
        ("Unit Test 1", .exam),
        ("Participation", nil),
    ])
    func classifiesKinds(text: String, kind: AssignmentKind?) {
        #expect(RuleBasedSyllabusParser.kind(of: text) == kind)
    }

    @Test(arguments: [
        ("Essay (15% of final grade)", "15%"),
        ("Lab 2 – 50 points", "50 pts"),
        ("Project 12.5%", "12.5%"),
        ("Quiz 1", nil),
    ])
    func extractsWeights(text: String, weight: String?) {
        #expect(RuleBasedSyllabusParser.weight(in: text) == weight)
    }

    @Test func deduplicatesRepeatedLines() {
        let items = parser.parse("Oct 14: Essay 1 due\nOct 14 — Essay 1").items
        #expect(items.count == 1)
    }
}

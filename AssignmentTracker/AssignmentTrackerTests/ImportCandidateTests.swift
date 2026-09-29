import Foundation
import Testing
@testable import AssignmentTracker

struct ImportCandidateTests {
    let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: Fixtures.fallStart, referenceDate: Fixtures.today)

    private func build(_ items: [DetectedItem], existing: [ExistingAssignment] = []) -> [ImportCandidate] {
        ImportCandidateBuilder.candidates(from: items, resolver: resolver, existing: existing)
    }

    @Test func upcomingItemsAreIncluded() {
        let candidate = build([DetectedItem(title: "Essay 2", kind: .assignment, dateText: "Oct 14")])[0]
        #expect(candidate.isIncluded)
        #expect(candidate.dueDate == Fixtures.date(2026, 10, 14, 23, 59))
        #expect(candidate.reviewReason == nil)
    }

    @Test func pastItemsStartUnchecked() {
        let candidate = build([DetectedItem(title: "Essay 1", kind: .assignment, dateText: "Sep 14")])[0]
        #expect(!candidate.isIncluded)
        #expect(candidate.dueDate != nil)
    }

    @Test func undatedItemsStartUncheckedWithReason() {
        let candidate = build([DetectedItem(title: "Book review", kind: .assignment, dateText: nil)])[0]
        #expect(!candidate.isIncluded)
        #expect(candidate.reviewReason == "No date in the syllabus")
    }

    @Test func ambiguousItemsAreIncludedButFlagged() {
        let candidate = build([DetectedItem(title: "Proposal", kind: .project, dateText: "Nov 2–6")])[0]
        #expect(candidate.isIncluded)
        #expect(candidate.reviewReason == "Date range in syllabus – using the last day")
    }

    @Test func duplicatesOfExistingAssignmentsAreSkipped() {
        let existing = [ExistingAssignment(title: "Quiz 3", dueDate: Fixtures.date(2026, 10, 1, 9, 0))]
        let candidates = build([
            DetectedItem(title: "quiz 3", kind: .quiz, dateText: "Oct 1"),   // same day, different case
            DetectedItem(title: "Quiz 3", kind: .quiz, dateText: "Oct 8"),   // different day: not a duplicate
        ], existing: existing)
        #expect(candidates[0].duplicateOf == "Quiz 3")
        #expect(!candidates[0].isIncluded)
        #expect(candidates[1].duplicateOf == nil)
        #expect(candidates[1].isIncluded)
    }

    @Test func changingTermStartReresolvesWeekDates() {
        var candidates = ImportCandidateBuilder.candidates(
            from: [DetectedItem(title: "Quiz 1", kind: .quiz, dateText: "Week 6, Thursday")],
            resolver: SyllabusDateResolver(calendar: Fixtures.calendar, termStart: nil, referenceDate: Fixtures.today),
            existing: []
        )
        #expect(candidates[0].dueDate == nil)
        #expect(!candidates[0].isIncluded)

        ImportCandidateBuilder.reresolve(&candidates, with: resolver)
        #expect(candidates[0].dueDate == Fixtures.date(2026, 10, 8, 23, 59))
        #expect(candidates[0].isIncluded)
    }

    @Test func reresolvingKeepsDatesThePersonPicked() {
        var candidates = build([DetectedItem(title: "Quiz 1", kind: .quiz, dateText: "Week 6, Thursday")])
        let picked = Fixtures.date(2026, 10, 9, 12, 0)
        candidates[0].dueDate = picked
        candidates[0].dateSetByUser = true

        let later = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: Fixtures.date(2026, 9, 7), referenceDate: Fixtures.today)
        ImportCandidateBuilder.reresolve(&candidates, with: later)
        #expect(candidates[0].dueDate == picked)
    }

    @Test(arguments: [
        (AssignmentKind.exam, nil as String?, Priority.high),
        (.assignment, "25%", .high),
        (.assignment, "10%", .medium),
        (.reading, nil, .low),
        (.project, "15%", .medium),
    ])
    func suggestedPriority(kind: AssignmentKind, weight: String?, priority: Priority) {
        #expect(ImportCandidate(title: "x", kind: kind, weight: weight).suggestedPriority == priority)
    }
}

struct FoundationModelParserHelpersTests {
    @Test func chunksRepeatTheCurrentWeekHeader() {
        let filler = String(repeating: "Lecture notes and discussion. ", count: 40)
        let text = (1...12).map { "Week \($0): Topic\n\(filler)\nFri: Quiz \($0)" }.joined(separator: "\n")
        let chunks = FoundationModelSyllabusParser.chunks(of: text)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= FoundationModelSyllabusParser.chunkSize + 1_300 })
        for chunk in chunks.dropFirst() {
            #expect(chunk.hasPrefix("Week "), "chunk should start with its week header")
        }
        #expect(chunks.joined().contains("Fri: Quiz 12"))
    }

    @Test func dropsItemsNotInTheSource() {
        let source = "Oct 14: Essay 1 due\nOct 20: Quiz 2"
        let real = GeneratedItem(title: "Essay 1", kind: .assignment, dateText: "Oct 14", weight: "", details: "")
        let invented = GeneratedItem(title: "Laboratory Practical", kind: .exam, dateText: "Nov 3", weight: "", details: "")
        #expect(FoundationModelSyllabusParser.detectedItem(from: real, source: source)?.title == "Essay 1")
        #expect(FoundationModelSyllabusParser.detectedItem(from: invented, source: source) == nil)
    }

    @Test func normalizesModelWeights() {
        let item = GeneratedItem(title: "Essay 1", kind: .assignment, dateText: "", weight: "15 percent (15%)", details: "")
        let detected = FoundationModelSyllabusParser.detectedItem(from: item, source: "Essay 1 15%")
        #expect(detected?.weight == "15%")
        #expect(detected?.dateText == nil)
    }
}

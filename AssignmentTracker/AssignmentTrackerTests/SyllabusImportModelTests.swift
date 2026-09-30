import Foundation
import SwiftData
import Testing
@testable import AssignmentTracker

@MainActor
struct SyllabusImportModelTests {
    @Test func saveAddsCheckedItemsAndMarksPastOnesDone() throws {
        let container = try ModelContainer(for: ModelContainer.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let course = Course(name: "Psychology", color: .purple, sortIndex: 0)
        context.insert(course)

        let model = SyllabusImportModel(course: course, calendar: Fixtures.calendar, referenceDate: Fixtures.today)
        model.candidates = ImportCandidateBuilder.candidates(
            from: [
                DetectedItem(title: "Discussion Post 1", kind: .assignment, dateText: "Sep 8"),
                DetectedItem(title: "Exam 1", kind: .exam, dateText: "Oct 15", weight: "20%"),
                DetectedItem(title: "Book review", kind: .assignment, dateText: nil),
            ],
            resolver: model.resolver, existing: []
        )
        #expect(model.includedCount == 2)
        #expect(model.pastIncludedCount == 1)

        #expect(model.save(in: context) == 2)
        let saved = try context.fetch(FetchDescriptor<Assignment>(sortBy: [SortDescriptor(\.dueDate)]))
        #expect(saved.map(\.title) == ["Discussion Post 1", "Exam 1"])
        #expect(saved[0].isCompleted)
        #expect(!saved[1].isCompleted)
        #expect(saved[1].priority == .high)
        #expect(saved.allSatisfy { $0.course === course })
    }

    @Test func skipAllUnchecksOnlyPastItems() {
        let model = SyllabusImportModel(calendar: Fixtures.calendar, referenceDate: Fixtures.today)
        model.candidates = ImportCandidateBuilder.candidates(
            from: [
                DetectedItem(title: "Quiz 1", kind: .quiz, dateText: "Sep 10"),
                DetectedItem(title: "Quiz 2", kind: .quiz, dateText: "Oct 10"),
            ],
            resolver: model.resolver, existing: []
        )
        model.setPastIncluded(false)
        #expect(model.candidates.map(\.isIncluded) == [false, true])
    }
}

import Foundation
import SwiftData

/// The courses and assignments from the mockups, placed relative to today.
enum SampleData {
    static func seedIfNeeded(_ context: ModelContext) {
        let courseCount = (try? context.fetchCount(FetchDescriptor<Course>())) ?? 0
        guard courseCount == 0 else { return }
        insert(into: context)
    }

    static func insert(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        func due(inDays days: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        let finance = Course(name: "Corporate Finance", color: .blue, sortIndex: 0)
        let econometrics = Course(name: "Econometrics", color: .orange, sortIndex: 1)
        let macro = Course(name: "Macroeconomics", color: .purple, sortIndex: 2)
        let banking = Course(name: "Money & Banking", color: .teal, sortIndex: 3)
        [finance, econometrics, macro, banking].forEach(context.insert)

        func add(_ title: String, _ course: Course, _ dueDate: Date, _ priority: Priority, notes: String = "") -> Assignment {
            let assignment = Assignment(title: title, notes: notes, dueDate: dueDate, priority: priority)
            context.insert(assignment)
            assignment.course = course
            return assignment
        }

        let problemSet = add(
            "Problem Set 4: Bond Valuation", finance, due(inDays: 0, 23, 59), .high,
            notes: "Use the yield-to-maturity formula from lecture. Submit as one PDF on the course site."
        )
        problemSet.steps = [
            Step(title: "Questions 1–5", isDone: true, sortIndex: 0),
            Step(title: "Questions 6–10", sortIndex: 1),
            Step(title: "Review answers and upload", sortIndex: 2),
        ]

        let reading = add("Read Chapter 7", econometrics, due(inDays: 0, 17, 0), .medium)
        reading.setCompleted(true)

        _ = add("Quiz 3", macro, due(inDays: 2, 9, 0), .medium)
        _ = add("Fed Policy Essay", banking, due(inDays: 3, 23, 59), .high)
        _ = add("Group Presentation Slides", finance, due(inDays: 5, 20, 0), .medium)
    }
}

extension ModelContainer {
    static let schema = Schema([Assignment.self, Course.self, Step.self])

    /// In-memory container filled with sample data, for SwiftUI previews.
    static var preview: ModelContainer {
        let container = try! ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        SampleData.insert(into: container.mainContext)
        return container
    }
}

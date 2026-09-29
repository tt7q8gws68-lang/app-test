import SwiftData
import SwiftUI

@Model
final class Assignment {
    /// Stable identifier for the pending reminder notification.
    var reminderID: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var priority: Priority
    var remindDayBefore: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var course: Course?

    @Relationship(deleteRule: .cascade, inverse: \Step.assignment)
    var steps: [Step] = []

    init(
        title: String,
        notes: String = "",
        dueDate: Date,
        priority: Priority = .medium,
        remindDayBefore: Bool = false
    ) {
        self.reminderID = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.remindDayBefore = remindDayBefore
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = .now
    }

    var sortedSteps: [Step] {
        steps.sorted { $0.sortIndex < $1.sortIndex }
    }

    var tint: Color {
        course?.color ?? .accentColor
    }

    func setCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? .now : nil
    }
}

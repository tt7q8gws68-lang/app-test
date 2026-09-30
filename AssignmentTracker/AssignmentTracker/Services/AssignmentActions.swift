import SwiftData
import SwiftUI

/// Mutations shared by the list and the detail screen, so reminders stay in sync.
@MainActor
extension Assignment {
    func toggleCompleted() {
        withAnimation(.snappy) {
            setCompleted(!isCompleted)
        }
        ReminderScheduler.sync(self)
    }

    /// Plans work for a day (or clears the plan with nil).
    func plan(for day: Date?, calendar: Calendar = .current) {
        withAnimation(.snappy) {
            plannedDate = day.map { calendar.startOfDay(for: $0) }
        }
    }

    func delete(from context: ModelContext) {
        ReminderScheduler.cancel(self)
        context.delete(self)
    }
}

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

    func delete(from context: ModelContext) {
        ReminderScheduler.cancel(self)
        context.delete(self)
    }
}

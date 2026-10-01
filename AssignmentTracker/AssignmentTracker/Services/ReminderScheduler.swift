import Foundation
import UserNotifications

/// Keeps one local notification per assignment, fired a day before it's due.
nonisolated enum ReminderScheduler {
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// True when the person has turned notifications off for the app (checked without prompting).
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Cancels any pending reminder for the assignment and schedules a fresh one if it still applies.
    static func sync(_ assignment: Assignment, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        let identifier = assignment.reminderID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard assignment.remindDayBefore, !assignment.isCompleted,
              let fireDate = calendar.date(byAdding: .day, value: -1, to: assignment.dueDate),
              fireDate > .now
        else { return }

        let content = UNMutableNotificationContent()
        content.title = assignment.title
        let time = assignment.dueDate.formatted(date: .omitted, time: .shortened)
        if let course = assignment.course {
            content.body = "\(course.name) · Due tomorrow at \(time)"
        } else {
            content.body = "Due tomorrow at \(time)"
        }
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel(_ assignment: Assignment) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [assignment.reminderID.uuidString])
    }
}

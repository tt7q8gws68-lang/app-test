import SwiftData
import SwiftUI

struct AssignmentRow: View {
    let assignment: Assignment

    @Environment(\.modelContext) private var modelContext

    private var isOverdue: Bool {
        !assignment.isCompleted && assignment.dueDate < .now
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: assignment.toggleCompleted) {
                CheckCircle(isOn: assignment.isCompleted, tint: assignment.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(assignment.isCompleted
                ? "Mark \(assignment.title) as not done"
                : "Mark \(assignment.title) as done")

            NavigationLink(value: assignment) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.title)
                            .font(.body.weight(.semibold))
                            .strikethrough(assignment.isCompleted)
                            .foregroundStyle(assignment.isCompleted ? Palette.completedText : .primary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(assignment.tint)
                                .frame(width: 8, height: 8)
                            if let course = assignment.course {
                                Text(course.name)
                                    .lineLimit(1)
                                Text("·")
                            }
                            Text(assignment.dueDate.dueRowLabel())
                                .foregroundStyle(isOverdue ? Palette.danger : Palette.secondaryText)
                                .fixedSize()
                            if let planned = assignment.plannedDate, !assignment.isCompleted {
                                Label(planned.plannedLabel(), systemImage: "calendar.badge.clock")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Planned for \(planned.plannedLabel())")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.chevron)
                }
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 22)
        .contextMenu {
            Button(
                assignment.isCompleted ? "Mark as Not Done" : "Mark as Done",
                systemImage: assignment.isCompleted ? "circle" : "checkmark.circle",
                action: assignment.toggleCompleted
            )
            if !assignment.isCompleted {
                Menu("Plan to Work On", systemImage: "calendar.badge.clock") {
                    Button("Today") { assignment.plan(for: .now) }
                    Button("Tomorrow") { assignment.plan(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)) }
                    if assignment.plannedDate != nil {
                        Button("Clear Plan", role: .destructive) { assignment.plan(for: nil) }
                    }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                assignment.delete(from: modelContext)
            }
        }
    }
}

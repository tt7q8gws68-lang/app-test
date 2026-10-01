import SwiftData
import SwiftUI

/// One assignment as a row inside a grouped glass panel: a 44pt check button, then the title
/// and a course · due line. Tapping the text opens the detail screen.
struct AssignmentRow: View {
    let assignment: Assignment
    /// Extra small tag after the due time, e.g. "Planned" in Calendar.
    var tag: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentTime) private var now

    private var isOverdue: Bool {
        !assignment.isCompleted && assignment.dueDate < now
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(assignment.title)
                        .font(.callout.weight(.semibold))
                        .strikethrough(assignment.isCompleted)
                        .foregroundStyle(assignment.isCompleted ? Palette.completedText : Palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(assignment.tint)
                            .frame(width: 8, height: 8)
                        if let course = assignment.course {
                            Text(course.name)
                                .lineLimit(1)
                            Text("·")
                        }
                        Text(assignment.dueDate.dueRowLabel(now: now))
                            .foregroundStyle(isOverdue ? Palette.danger : Palette.secondaryText)
                            .fixedSize()
                        if let planned = assignment.plannedDate, !assignment.isCompleted, tag == nil {
                            AppIcon(.plan, size: 14)
                                .foregroundStyle(Palette.accentText)
                                .accessibilityLabel("Planned for \(planned.plannedLabel())")
                                .accessibilityHidden(false)
                        }
                        if let tag {
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.accentText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Palette.accent.opacity(0.14), in: .capsule)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                assignment.toggleCompleted()
            } label: {
                Label(assignment.isCompleted ? "Mark as Not Done" : "Mark as Done", appIcon: .check)
            }
            if !assignment.isCompleted {
                Menu {
                    Button("Today") { assignment.plan(for: .now) }
                    Button("Tomorrow") { assignment.plan(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)) }
                    if assignment.plannedDate != nil {
                        Button("Clear Plan", role: .destructive) { assignment.plan(for: nil) }
                    }
                } label: {
                    Label("Plan to Work On", appIcon: .plan)
                }
            }
            // No delete glyph in the app's icon set; SF Symbol fallback.
            Button("Delete", systemImage: "trash", role: .destructive) {
                assignment.delete(from: modelContext)
            }
        }
    }
}

/// Assignments as one grouped glass panel with inset hairlines (54pt in, 12pt from the right).
struct AssignmentGroup: View {
    let assignments: [Assignment]
    /// A tag per row, keyed by assignment (e.g. "Planned").
    var tag: (Assignment) -> String? = { _ in nil }

    var body: some View {
        GlassGroup {
            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                if index > 0 { InsetDivider(leading: 54) }
                AssignmentRow(assignment: assignment, tag: tag(assignment))
            }
        }
    }
}

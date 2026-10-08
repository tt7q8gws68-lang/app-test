import SwiftData
import SwiftUI

/// Gives class-less assignments a course, one menu per assignment.
struct AssignToCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @Query(filter: #Predicate<Assignment> { $0.course == nil }, sort: \Assignment.dueDate)
    private var unassigned: [Assignment]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if unassigned.isEmpty {
                        Text("Every assignment has a course.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .glassCard(cornerRadius: 26)
                    } else {
                        GlassGroup {
                            ForEach(Array(unassigned.enumerated()), id: \.element.id) { index, assignment in
                                if index > 0 { InsetDivider(leading: 12) }
                                row(for: assignment)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background { DuskBackground() }
            .navigationTitle("Assign Courses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() } label: { Label("Done", appIcon: .check) }
                }
            }
        }
    }

    private func row(for assignment: Assignment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(assignment.dueDate.dueRowLabel())
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(courses) { course in
                    Button(course.name) {
                        withAnimation(.snappy) { assignment.course = course }
                        ReminderScheduler.sync(assignment)
                    }
                }
            } label: {
                Text("Choose")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accentText)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .disabled(courses.isEmpty)
            .accessibilityLabel("Choose a course for \(assignment.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

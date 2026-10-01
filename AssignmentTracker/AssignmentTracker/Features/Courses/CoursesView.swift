import SwiftData
import SwiftUI

/// The classes: each with its color and workload. Tap one to rename, recolor or delete it.
struct CoursesView: View {
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @Query private var assignments: [Assignment]
    @State private var editing: Course?
    @State private var isAdding = false
    @State private var isImporting = false

    private var unassigned: Int {
        assignments.filter { $0.course == nil && !$0.isCompleted }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if courses.isEmpty {
                        VStack(spacing: 8) {
                            Text("No classes yet")
                                .font(.headline)
                            Text("Add a class, or import a syllabus to create one with its assignments.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .glassCard()
                    }

                    ForEach(courses) { course in
                        Button { editing = course } label: {
                            CourseRow(course: course)
                        }
                        .buttonStyle(.plain)
                    }

                    if unassigned > 0 {
                        Text(unassigned == 1 ? "1 open assignment has no class." : "\(unassigned) open assignments have no class.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(variant: .list) }
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import Syllabus", systemImage: "doc.text.viewfinder") { isImporting = true }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Class", systemImage: "plus") { isAdding = true }
                        .buttonStyle(.glassProminent)
                }
            }
            .sheet(item: $editing) { CourseEditorSheet(course: $0) }
            .sheet(isPresented: $isAdding) { CourseEditorSheet() }
            .sheet(isPresented: $isImporting) { SyllabusImportSheet() }
        }
    }
}

private struct CourseRow: View {
    let course: Course

    private var open: Int { course.assignments.filter { !$0.isCompleted }.count }

    private var nextDue: Assignment? {
        course.assignments
            .filter { !$0.isCompleted && $0.dueDate >= .now }
            .min { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(course.color)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.chevron)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: 22)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit class")
    }

    private var detail: String {
        var parts = [open == 1 ? "1 to do" : "\(open) to do"]
        if let nextDue {
            parts.append("next: \(nextDue.title), \(nextDue.dueDate.dueRowLabel())")
        } else if course.assignments.isEmpty {
            parts = ["No assignments"]
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    CoursesView()
        .modelContainer(.preview)
}

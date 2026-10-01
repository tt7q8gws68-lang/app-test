import SwiftData
import SwiftUI

/// The classes, as one grouped glass list. Tap one to rename, recolor or delete it.
struct CoursesView: View {
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @Query private var assignments: [Assignment]
    @State private var editing: Course?
    @State private var isAdding = false
    @State private var isImporting = false
    @State private var isAssigning = false

    private var summaries: [(course: Course, summary: CourseSummary)] {
        courses.map { course in
            (course, CourseSummary(
                name: course.name,
                assignments: course.assignments.map { ($0.title, $0.dueDate, $0.isCompleted) }
            ))
        }
    }

    private var unassigned: [Assignment] {
        assignments.filter { $0.course == nil }
    }

    private var subtitle: String {
        let toDo = summaries.reduce(0) { $0 + $1.summary.openCount }
        let courseWord = courses.count == 1 ? "course" : "courses"
        return "\(courses.count) \(courseWord) · \(toDo) to do"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenHeader(subtitle: subtitle, title: "Courses") {
                        GlassCircleButton(icon: .scan, label: "Import syllabus") {
                            isImporting = true
                        }
                        GlassCircleButton(icon: .add, label: "Add course", isProminent: true) {
                            isAdding = true
                        }
                    }

                    if courses.isEmpty {
                        emptyState
                    } else {
                        GlassGroup {
                            ForEach(Array(summaries.enumerated()), id: \.element.course.id) { index, item in
                                if index > 0 { InsetDivider() }
                                Button { editing = item.course } label: {
                                    CourseRow(course: item.course, summary: item.summary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !unassigned.isEmpty {
                        unassignedRow
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .clearsTabBar()
            .background { DuskBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $editing) { CourseEditorSheet(course: $0) }
            .sheet(isPresented: $isAdding) { CourseEditorSheet() }
            .sheet(isPresented: $isImporting) { SyllabusImportSheet() }
            .sheet(isPresented: $isAssigning) { AssignToCourseSheet() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No courses yet")
                .font(.headline)
            Text("Add a course, or import a syllabus to create one with its assignments.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard(cornerRadius: 26)
    }

    private var unassignedRow: some View {
        let count = unassigned.count
        let text = count == 1 ? "1 assignment has no course" : "\(count) assignments have no course"
        return Button { isAssigning = true } label: {
            HStack(spacing: 12) {
                AppIcon(.notes, size: 22)
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 24)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                Spacer(minLength: 8)
                Text("Assign")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accentText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 22)
        .accessibilityLabel(text)
        .accessibilityHint("Choose a course for each")
    }
}

private struct CourseRow: View {
    let course: Course
    let summary: CourseSummary

    var body: some View {
        HStack(spacing: 14) {
            TintTile(content: .text(summary.initials), color: course.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(summary.detail())
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit course")
    }

    @ViewBuilder
    private var trailing: some View {
        switch summary.state {
        case .open(let count):
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 9)
                .frame(minWidth: 28, minHeight: 28)
                .background(course.color, in: .capsule)
                .accessibilityLabel("\(count) to do")
        case .caughtUp:
            AppIcon(.check, size: 14, weight: 3)
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 28, height: 28)
                .background(Palette.faintFill, in: .circle)
                .accessibilityLabel("All done")
        case .noAssignments:
            Color.clear.frame(width: 28, height: 28)
        }
    }
}

#Preview {
    CoursesView()
        .modelContainer(.preview)
}

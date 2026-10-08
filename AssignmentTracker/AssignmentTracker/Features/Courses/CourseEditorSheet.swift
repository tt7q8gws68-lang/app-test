import SwiftData
import SwiftUI

/// Creates a class, or renames, recolors and deletes an existing one.
struct CourseEditorSheet: View {
    let course: Course?
    var onCreate: (Course) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @State private var name: String
    @State private var color: CourseColor
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool

    init(course: Course? = nil, onCreate: @escaping (Course) -> Void = { _ in }) {
        self.course = course
        self.onCreate = onCreate
        _name = State(initialValue: course?.name ?? "")
        _color = State(initialValue: course?.colorToken ?? .blue)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDuplicateName: Bool {
        courses.contains { $0 !== course && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                        TextField("e.g. Financial Accounting", text: $name)
                            .font(.title3.weight(.semibold))
                            .focused($isNameFocused)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    if isDuplicateName {
                        Text("You already have a class with this name.")
                            .font(.footnote)
                            .foregroundStyle(Palette.warning)
                            .padding(.horizontal, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Color")
                        ColorGrid(selection: $color)
                    }

                    if let course {
                        let count = course.assignments.count
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            // No delete glyph in the app's icon set; SF Symbol fallback.
                            Label("Delete Class", systemImage: "trash")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .duskGlass(in: Capsule(), interactive: true)
                        .confirmationDialog(
                            "Delete “\(course.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible
                        ) {
                            if count > 0 {
                                Button(count == 1 ? "Delete Class and 1 Assignment" : "Delete Class and \(count) Assignments", role: .destructive) {
                                    delete(course, withAssignments: true)
                                }
                                Button("Delete Class, Keep Assignments") {
                                    delete(course, withAssignments: false)
                                }
                            } else {
                                Button("Delete Class", role: .destructive) { delete(course, withAssignments: false) }
                            }
                        } message: {
                            if count > 0 {
                                Text("Kept assignments stay in your list without a class.")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background { DuskBackground() }
            .navigationTitle(course == nil ? "New Class" : "Edit Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Label("Cancel", appIcon: .close) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save) { Label(course == nil ? "Add" : "Save", appIcon: .check) }
                        .disabled(trimmedName.isEmpty || isDuplicateName)
                }
            }
            .onAppear {
                guard course == nil else { return }
                isNameFocused = true
                // Suggest a color no class is using yet, or else the least used.
                let used = Dictionary(grouping: courses, by: \.colorToken).mapValues(\.count)
                color = CourseColor.allCases.min { used[$0, default: 0] < used[$1, default: 0] } ?? .blue
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        if let course {
            let renamed = course.name != trimmedName
            course.name = trimmedName
            course.colorToken = color
            // Pending reminders carry the class name, so refresh them after a rename.
            if renamed {
                for assignment in course.assignments { ReminderScheduler.sync(assignment) }
            }
        } else {
            let course = Course(name: trimmedName, color: color, sortIndex: (courses.map(\.sortIndex).max() ?? -1) + 1)
            modelContext.insert(course)
            onCreate(course)
        }
        dismiss()
    }

    private func delete(_ course: Course, withAssignments: Bool) {
        let keptAssignments = withAssignments ? [] : course.assignments
        if withAssignments {
            for assignment in course.assignments {
                assignment.delete(from: modelContext)
            }
        }
        modelContext.delete(course)
        // Kept work no longer belongs to a class; its reminder must stop naming it.
        for assignment in keptAssignments {
            assignment.course = nil
            ReminderScheduler.sync(assignment)
        }
        dismiss()
    }
}

/// All course colors as large, tappable swatches.
struct ColorGrid: View {
    @Binding var selection: CourseColor

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CourseColor.allCases, id: \.self) { option in
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 38, height: 38)
                        .overlay {
                            if option == selection {
                                AppIcon(.check, size: 14, weight: 3)
                                    .foregroundStyle(Palette.onAccent)
                            }
                        }
                        .padding(3)
                        .overlay {
                            if option == selection {
                                Circle().strokeBorder(option.color, lineWidth: 2)
                            }
                        }
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 24)
    }
}

#Preview {
    CourseEditorSheet()
        .modelContainer(.preview)
}

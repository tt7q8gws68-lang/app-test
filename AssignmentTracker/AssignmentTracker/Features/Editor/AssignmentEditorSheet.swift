import SwiftData
import SwiftUI

/// Creates a new assignment, or edits an existing one when `assignment` is set.
struct AssignmentEditorSheet: View {
    let assignment: Assignment?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \Course.sortIndex) private var courses: [Course]

    @State private var title: String
    @State private var course: Course?
    @State private var dueDate: Date
    @State private var remindDayBefore: Bool
    @State private var priority: Priority
    @State private var notes: String
    @State private var kind: AssignmentKind
    @State private var isAddingCourse = false
    @State private var notificationsBlocked = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, notes }

    init(assignment: Assignment? = nil) {
        self.assignment = assignment
        _title = State(initialValue: assignment?.title ?? "")
        _course = State(initialValue: assignment?.course)
        _dueDate = State(initialValue: assignment?.dueDate ?? Self.defaultDueDate())
        _remindDayBefore = State(initialValue: assignment?.remindDayBefore ?? true)
        _priority = State(initialValue: assignment?.priority ?? .medium)
        _notes = State(initialValue: assignment?.notes ?? "")
        _kind = State(initialValue: assignment?.kind ?? .assignment)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleField

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Course")
                        CourseChips(courses: courses, selection: $course) { isAddingCourse = true }
                    }

                    scheduleCard

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Priority")
                        Picker("Priority", selection: $priority) {
                            ForEach(Priority.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.large)
                    }

                    notesField
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AmbientBackground(variant: .list).opacity(0.6) }
            .navigationTitle(assignment == nil ? "New Assignment" : "Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm, action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                // Only a new assignment gets a default class; editing keeps "no class" as is.
                if assignment == nil {
                    if course == nil { course = courses.first }
                    focusedField = .title
                }
            }
            .sheet(isPresented: $isAddingCourse) {
                CourseEditorSheet { course = $0 }
            }
        }
    }

    // MARK: - Sections

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
            TextField("e.g. Problem Set 5", text: $title)
                .font(.title3.weight(.semibold))
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .accessibilityLabel("Title")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var scheduleCard: some View {
        VStack(spacing: 0) {
            HStack {
                RowLabel("Type", systemImage: kind.systemImage)
                Spacer()
                Picker("Type", selection: $kind) {
                    ForEach(AssignmentKind.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .frame(minHeight: 52)

            Divider()

            DatePicker(selection: $dueDate, displayedComponents: .date) {
                RowLabel("Due date", systemImage: "calendar")
            }
            .frame(minHeight: 52)

            Divider()

            DatePicker(selection: $dueDate, displayedComponents: .hourAndMinute) {
                RowLabel("Time", systemImage: "clock")
            }
            .frame(minHeight: 52)

            Divider()

            Toggle(isOn: $remindDayBefore) {
                RowLabel("Remind me a day before", systemImage: "bell")
            }
            .tint(Palette.success)
            .frame(minHeight: 52)
            .onChange(of: remindDayBefore) { _, isOn in
                guard isOn else { notificationsBlocked = false; return }
                Task { notificationsBlocked = !(await ReminderScheduler.requestAuthorization()) }
            }

            if notificationsBlocked && remindDayBefore {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Notifications are off for this app. Turn them on in Settings.", systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .glassCard()
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
            TextField("Add details, links or steps", text: $notes, axis: .vertical)
                .lineLimit(3...10)
                .focused($focusedField, equals: .notes)
                .accessibilityLabel("Notes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Actions

    private func save() {
        let target: Assignment
        if let assignment {
            target = assignment
        } else {
            target = Assignment(title: trimmedTitle, dueDate: dueDate)
            modelContext.insert(target)
        }
        target.title = trimmedTitle
        target.course = course
        target.dueDate = dueDate
        target.remindDayBefore = remindDayBefore
        target.priority = priority
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.kind = kind

        if remindDayBefore {
            Task {
                await ReminderScheduler.requestAuthorization()
                ReminderScheduler.sync(target)
            }
        } else {
            ReminderScheduler.sync(target)
        }
        dismiss()
    }

    /// Tonight at 11:59 PM.
    private static func defaultDueDate(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AssignmentEditorSheet()
        }
        .modelContainer(.preview)
}

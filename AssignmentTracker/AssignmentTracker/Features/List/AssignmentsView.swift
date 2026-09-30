import SwiftData
import SwiftUI

struct AssignmentsView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case toDo = "To do"
        case done = "Done"

        var id: Self { self }
    }

    private struct Section: Identifiable {
        let bucket: DueBucket
        let items: [Assignment]
        var id: DueBucket { bucket }
    }

    /// Current on-time streak, shown as a chip that opens the Streaks tab.
    var streak = 0
    var onShowStreaks: () -> Void = {}

    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var isAddingAssignment = false
    @State private var isImportingSyllabus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeeklyProgressCard(done: weekDone, total: weekTotal)

                    Picker("Show", selection: $filter.animation(.snappy)) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)

                    if sections.isEmpty {
                        Text(searchText.isEmpty ? "Nothing here yet." : "No matching assignments.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .glassCard()
                    }

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(section.bucket.title)
                            ForEach(section.items) { assignment in
                                AssignmentRow(assignment: assignment)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(variant: .list) }
            .navigationTitle("Assignments")
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Search assignments")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onShowStreaks) {
                        // A plain HStack: toolbar buttons would reduce a Label to its icon.
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(streak > 0 ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(Palette.chevron))
                            Text("\(streak)")
                                .contentTransition(.numericText())
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 6)
                    }
                    .accessibilityLabel("Streak: \(streak) on time in a row")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import Syllabus", systemImage: "doc.text.viewfinder") {
                        isImportingSyllabus = true
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Assignment", systemImage: "plus") {
                        isAddingAssignment = true
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .navigationDestination(for: Assignment.self) { assignment in
                AssignmentDetailView(assignment: assignment)
            }
            .sheet(isPresented: $isAddingAssignment) {
                AssignmentEditorSheet()
            }
            .sheet(isPresented: $isImportingSyllabus) {
                SyllabusImportSheet()
            }
        }
    }

    // MARK: - Derived data

    private var weekAssignments: [Assignment] {
        let window = WeekWindow()
        return assignments.filter { window.contains($0.dueDate) }
    }

    private var weekDone: Int { weekAssignments.filter(\.isCompleted).count }
    private var weekTotal: Int { weekAssignments.count }

    private var sections: [Section] {
        let now = Date.now
        let visible = assignments.filter { assignment in
            switch filter {
            case .all: true
            case .toDo: !assignment.isCompleted
            case .done: assignment.isCompleted
            }
        }
        .filter(matchesSearch)

        let grouped = Dictionary(grouping: visible) { DueBucket.of($0, now: now) }
        return DueBucket.allCases.compactMap { bucket in
            guard var items = grouped[bucket], !items.isEmpty else { return nil }
            // Most recent first for past work; soonest first everywhere else.
            if bucket == .earlier { items.reverse() }
            return Section(bucket: bucket, items: items)
        }
    }

    private func matchesSearch(_ assignment: Assignment) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return assignment.title.localizedStandardContains(query)
            || (assignment.course?.name.localizedStandardContains(query) ?? false)
            || assignment.notes.localizedStandardContains(query)
    }
}

#Preview {
    AssignmentsView()
        .modelContainer(.preview)
}

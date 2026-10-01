import SwiftData
import SwiftUI

/// The main screen: this week at a glance, then assignments grouped by when they're due.
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
        /// Open items in the whole bucket, regardless of the filter.
        let left: Int
        var id: DueBucket { bucket }
    }

    /// Opens a strip day in Calendar.
    var onShowDay: (Date) -> Void = { _ in }

    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @Environment(\.currentTime) private var now
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isAddingAssignment = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let sections = sections
        NavigationStack {
            ScrollView {
                // Lazy, so sections far down (Later, a semester of Earlier) build only when reached.
                LazyVStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        title: "Assignments"
                    ) {
                        GlassCircleButton(icon: .search, label: isSearching ? "Close search" : "Search") {
                            withAnimation(.snappy) { toggleSearch() }
                        }
                        GlassCircleButton(icon: .add, label: "New assignment", isProminent: true) {
                            isAddingAssignment = true
                        }
                    }

                    if isSearching {
                        searchField
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    WeekHeroCard(summary: hero, onShowDay: onShowDay)

                    GlassSegmented(
                        options: Filter.allCases.map { ($0, $0.rawValue) },
                        selection: $filter
                    )

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
                            HStack(alignment: .firstTextBaseline) {
                                SectionHeader(section.bucket.title)
                                Spacer()
                                Text(section.left == 0 ? "All done" : "\(section.left) left")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.secondaryText)
                                    .padding(.trailing, 4)
                            }
                            AssignmentGroup(assignments: section.items)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.snappy, value: filter)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .background { DuskBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Assignment.self) { assignment in
                AssignmentDetailView(assignment: assignment)
            }
            .sheet(isPresented: $isAddingAssignment) {
                AssignmentEditorSheet()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            AppIcon(.search, size: 18)
                .foregroundStyle(Palette.secondaryText)
            TextField("Search assignments", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    AppIcon(.close, size: 16)
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, searchText.isEmpty ? 16 : 0)
        .frame(minHeight: 48)
        .glassCard(cornerRadius: 24)
    }

    private func toggleSearch() {
        isSearching.toggle()
        if isSearching {
            isSearchFocused = true
        } else {
            searchText = ""
            isSearchFocused = false
        }
    }

    // MARK: - Derived data

    private var hero: WeekHeroSummary {
        WeekHeroSummary(items: assignments.map {
            WeekHeroSummary.Item(dueDate: $0.dueDate, isCompleted: $0.isCompleted, color: $0.course?.colorToken)
        }, now: now)
    }

    private var sections: [Section] {
        let window = WeekWindow(now: now)
        let byBucket = Dictionary(grouping: assignments) {
            DueBucket.of(dueDate: $0.dueDate, isCompleted: $0.isCompleted, in: window)
        }
        return DueBucket.allCases.compactMap { bucket in
            let all = byBucket[bucket] ?? []
            var items = all.filter { assignment in
                switch filter {
                case .all: true
                case .toDo: !assignment.isCompleted
                case .done: assignment.isCompleted
                }
            }
            .filter(matchesSearch)
            guard !items.isEmpty else { return nil }
            // Most recent first for past work; soonest first everywhere else.
            if bucket == .earlier { items.reverse() }
            return Section(bucket: bucket, items: items, left: all.filter { !$0.isCompleted }.count)
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

/// The hero card: a progress ring for the week, the count still to go, and a Monday–Sunday strip
/// with a dot per assignment due each day.
private struct WeekHeroCard: View {
    let summary: WeekHeroSummary
    let onShowDay: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ProgressRing(fraction: summary.fraction) {
                    Text("\(summary.done)/\(summary.total)")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("This week")
                .accessibilityValue("\(summary.done) of \(summary.total) done")

                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.secondaryText)
                    Text("\(summary.remaining) to go")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .contentTransition(.numericText())
                    Text(summary.dueTodayText)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                ForEach(summary.days, id: \.date) { day in
                    Button { onShowDay(day.date) } label: {
                        StripDay(day: day)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(WeekHeroSummary.accessibilityLabel(for: day))
                    .accessibilityHint("Opens this day in Calendar")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .glassCard(cornerRadius: 28)
        .animation(.snappy, value: summary)
    }
}

private struct StripDay: View {
    let day: WeekHeroSummary.Day

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
            Text(day.date.formatted(.dateTime.day()))
                .font(.system(size: 15, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? Palette.onAccent : (day.isPast ? Palette.mutedNumber : Palette.text))
                .frame(width: 34, height: 34)
                .background {
                    if day.isToday { Circle().fill(Palette.accent) }
                }
            HStack(spacing: 3) {
                ForEach(Array(day.dots.prefix(4).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color?.color ?? CourseColor.graphite.color)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }
}

#Preview {
    AssignmentsView()
        .modelContainer(.preview)
}

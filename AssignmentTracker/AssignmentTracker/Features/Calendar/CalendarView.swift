import SwiftData
import SwiftUI

/// Look-ahead planning: a month grid with what's due each day, and a weeks-ahead list for
/// spotting busy stretches early.
struct CalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week = "Week"
        var id: Self { self }
    }

    /// Owned by `RootView`, so the Assignments week strip can open a day here.
    @Binding var selectedDay: Date

    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]
    @State private var mode: Mode = .month
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(
                        subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        title: "Calendar"
                    ) {
                        GlassCapsuleButton(title: "Today") {
                            withAnimation(.snappy) {
                                mode = .month
                                selectedDay = Calendar.current.startOfDay(for: .now)
                            }
                        }
                    }

                    GlassSegmented(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $mode)

                    switch mode {
                    case .month:
                        MonthGridCard(month: $month, selectedDay: $selectedDay, assignments: assignments)
                        DayAgenda(day: selectedDay, assignments: assignments)
                    case .week:
                        WeeksAheadList(assignments: assignments)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .clearsTabBar()
            .background { DuskBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Assignment.self) { assignment in
                AssignmentDetailView(assignment: assignment)
            }
            .onChange(of: selectedDay, initial: true) { _, day in
                // A day picked elsewhere (the Assignments strip) brings its month into view.
                let calendar = Calendar.current
                if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
                    month = calendar.dateInterval(of: .month, for: day)!.start
                }
                mode = .month
            }
        }
    }
}

// MARK: - Month grid

struct MonthGridCard: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let assignments: [Assignment]

    private let calendar = Calendar.current


    /// Whole weeks covering the month, starting on the locale's first weekday.
    private var days: [Date] {
        let first = month
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        let cells = Int(ceil(Double(leading + count) / 7)) * 7
        let start = calendar.date(byAdding: .day, value: -leading, to: first)!
        return (0..<cells).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        // Built once per render, not once per day cell.
        let dueByDay = Dictionary(grouping: assignments) { calendar.startOfDay(for: $0.dueDate) }
        let plannedDays = Set(assignments.filter { !$0.isCompleted }.compactMap(\.plannedDate).map { calendar.startOfDay(for: $0) })
        let selected = calendar.startOfDay(for: selectedDay)
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Spacer()
                Button { step(-1) } label: { AppIcon(.back, size: 20).frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel("Previous month")
                Button { step(1) } label: { AppIcon(.forward, size: 20).frame(width: 44, height: 44).contentShape(.rect) }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
            .font(.body.weight(.semibold))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(height: 20)
                }
                ForEach(days, id: \.self) { day in
                    DayCell(
                        day: day,
                        isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        isSelected: day == selected,
                        due: dueByDay[day] ?? [],
                        hasPlanned: plannedDays.contains(day)
                    )
                    .onTapGesture {
                        withAnimation(.snappy) {
                            selectedDay = day
                            if !calendar.isDate(day, equalTo: month, toGranularity: .month) {
                                month = calendar.dateInterval(of: .month, for: day)!.start
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 26)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                step(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func step(_ months: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: months, to: month)!
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let isSelected: Bool
    let due: [Assignment]
    let hasPlanned: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isPast: Bool { day < Calendar.current.startOfDay(for: .now) }

    var body: some View {
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(isToday || isSelected ? .bold : .medium))
                .foregroundStyle(isToday ? Palette.onAccent : (isPast ? Palette.mutedNumber : Palette.text))
                .frame(width: 34, height: 34)
                .background {
                    if isToday { Circle().fill(Palette.accent) }
                }
                .overlay {
                    // The selected day (when it isn't today) gets an accent ring.
                    if isSelected, !isToday {
                        Circle().strokeBorder(Palette.accent, lineWidth: 2)
                    }
                }

            HStack(spacing: 3) {
                ForEach(due.prefix(3)) { assignment in
                    Circle()
                        .fill(assignment.tint.opacity(assignment.isCompleted ? 0.4 : 1))
                        .frame(width: 5, height: 5)
                }
                if hasPlanned {
                    Circle()
                        .strokeBorder(Palette.accent, lineWidth: 1.2)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(isInMonth ? 1 : 0.35)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        let open = due.filter { !$0.isCompleted }.count
        if open > 0 { parts.append("\(open) due") }
        if hasPlanned { parts.append("work planned") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Day agenda

/// The selected day's items in one glass panel: what's due, then planned work sessions.
private struct DayAgenda: View {
    let day: Date
    let assignments: [Assignment]

    private let calendar = Calendar.current

    private var range: Range<Date> {
        let start = calendar.startOfDay(for: day)
        return start..<calendar.date(byAdding: .day, value: 1, to: start)!
    }

    private var title: String {
        calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        let range = range
        let due = assignments.filter { range.contains($0.dueDate) }
        let planned = assignments.filter {
            !$0.isCompleted && $0.plannedDate.map(range.contains) == true && !range.contains($0.dueDate)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Spacer()
                let open = due.filter { !$0.isCompleted }.count
                if !due.isEmpty {
                    Text(open == 0 ? "All done" : "\(open) left")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.trailing, 4)
                }
            }

            if due.isEmpty && planned.isEmpty {
                Text("Nothing due or planned. A good day to get ahead.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
                    .glassCard(cornerRadius: 26)
            } else {
                let plannedIDs = Set(planned.map(\.id))
                AssignmentGroup(assignments: due + planned) { plannedIDs.contains($0.id) ? "Planned" : nil }
            }
        }
    }
}

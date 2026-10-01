import SwiftUI

/// The next eight weeks at a glance: how much is due each week and on which days, so busy
/// stretches (several deadlines, an exam) show up early enough to plan around.
struct WeeksAheadList: View {
    let assignments: [Assignment]

    private let calendar = Calendar.current
    private static let weekCount = 8

    private struct Week: Identifiable {
        let start: Date
        let items: [Assignment]
        var id: Date { start }
    }

    private var overdue: [Assignment] {
        let startOfToday = calendar.startOfDay(for: .now)
        return assignments.filter { !$0.isCompleted && $0.dueDate < startOfToday }
    }

    private var weeks: [Week] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        return (0..<Self.weekCount).map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return Week(start: start, items: assignments.filter { $0.dueDate >= start && $0.dueDate < end })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !overdue.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Overdue")
                    ForEach(overdue) { AssignmentRow(assignment: $0) }
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                WeekSection(title: title(for: week, index: index), start: week.start, items: week.items)
            }
        }
    }

    private func title(for week: Week, index: Int) -> String {
        switch index {
        case 0: return "This week"
        case 1: return "Next week"
        default:
            let end = calendar.date(byAdding: .day, value: 6, to: week.start)!
            return "\(week.start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

private struct WeekSection: View {
    let title: String
    let start: Date
    let items: [Assignment]

    private let calendar = Calendar.current

    private var open: [Assignment] { items.filter { !$0.isCompleted } }
    private var examCount: Int { open.filter { $0.kind == .exam }.count }
    private var isBusy: Bool { open.count >= 5 || examCount > 0 }

    private var summary: String {
        guard !items.isEmpty else { return "Nothing due" }
        var parts = ["\(open.count) due"]
        if examCount > 0 { parts.append(examCount == 1 ? "1 exam" : "\(examCount) exams") }
        if open.count < items.count { parts.append("\(items.count - open.count) done") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Spacer()
                if isBusy {
                    // No warning glyph in the app's icon set; outline SF Symbol fallback.
                    Label("Busy", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.warning)
                }
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.trailing, 4)

            if !items.isEmpty {
                DayLoadStrip(start: start, items: open)
                AssignmentGroup(assignments: open)
            }
        }
    }
}

/// Seven small bars, one per day, sized by how much is due that day.
private struct DayLoadStrip: View {
    let start: Date
    let items: [Assignment]

    private let calendar = Calendar.current

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                let dueThatDay = items.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
                VStack(spacing: 4) {
                    Capsule()
                        .fill(dueThatDay.isEmpty ? AnyShapeStyle(Palette.track) : AnyShapeStyle(barColor(for: dueThatDay)))
                        .frame(height: CGFloat(4 + min(dueThatDay.count, 4) * 7))
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(calendar.isDateInToday(day) ? .bold : .regular))
                        .foregroundStyle(calendar.isDateInToday(day) ? Palette.accent : Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(dueThatDay.isEmpty ? "Nothing due" : "\(dueThatDay.count) due")
            }
        }
        .frame(height: 50, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard()
    }

    private func barColor(for items: [Assignment]) -> Color {
        if items.contains(where: { $0.kind == .exam }) { return Palette.danger }
        return items.count >= 3 ? Palette.warning : Palette.accent
    }
}

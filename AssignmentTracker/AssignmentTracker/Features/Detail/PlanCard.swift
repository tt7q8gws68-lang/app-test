import SwiftUI

/// "Plan to work on": the day the person intends to do the work, shown on the Calendar tab.
struct PlanCard: View {
    let assignment: Assignment

    private var suggestedDay: Date {
        // The day before it's due, but never earlier than today.
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: assignment.dueDate))!
        return max(dayBefore, calendar.startOfDay(for: .now))
    }

    var body: some View {
        HStack(spacing: 12) {
            if let planned = assignment.plannedDate {
                DatePicker(
                    selection: Binding(get: { planned }, set: { assignment.plan(for: $0) }),
                    in: Calendar.current.startOfDay(for: .now)...,
                    displayedComponents: .date
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        RowLabel("Work on", systemImage: "calendar.badge.clock")
                        Text(planHint(for: planned))
                            .font(.caption)
                            .foregroundStyle(planned > assignment.dueDate ? Palette.danger : Palette.secondaryText)
                            .padding(.leading, 36)
                    }
                }
                Button {
                    assignment.plan(for: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Palette.chevron)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear plan")
            } else {
                Button {
                    assignment.plan(for: suggestedDay)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            RowLabel("Plan a day to work on it", systemImage: "calendar.badge.plus")
                            Text("Shows up on that day in Calendar")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                                .padding(.leading, 36)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.chevron)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassCard()
    }

    private func planHint(for planned: Date) -> String {
        let calendar = Calendar.current
        if planned > assignment.dueDate { return "After it’s due" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: planned), to: calendar.startOfDay(for: assignment.dueDate)).day ?? 0
        switch days {
        case 0: return "The day it’s due"
        case 1: return "1 day before it’s due"
        default: return "\(days) days before it’s due"
        }
    }
}

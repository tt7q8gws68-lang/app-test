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
        HStack(spacing: 14) {
            AppIcon(.plan, size: 22)
                .foregroundStyle(Palette.accentText)
                .frame(width: 26)
                .accessibilityHidden(true)

            if let planned = assignment.plannedDate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work day")
                        .font(.body.weight(.semibold))
                    Text(planHint(for: planned))
                        .font(.footnote)
                        .foregroundStyle(planned > assignment.dueDate ? Palette.danger : Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DatePicker(
                    "Work day",
                    selection: Binding(get: { planned }, set: { assignment.plan(for: $0) }),
                    in: Calendar.current.startOfDay(for: .now)...,
                    displayedComponents: .date
                )
                .labelsHidden()
                Button {
                    assignment.plan(for: nil)
                } label: {
                    AppIcon(.close, size: 12, weight: 2.5)
                        .foregroundStyle(Palette.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Palette.faintFill, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear work day")
            } else {
                Button {
                    assignment.plan(for: suggestedDay)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan a work day")
                                .font(.body.weight(.semibold))
                            Text("Adds it to your Calendar")
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        AppIcon(.forward, size: 16)
                            .foregroundStyle(Palette.mutedNumber)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Plans it for the day before it’s due")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .glassCard(cornerRadius: 22)
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

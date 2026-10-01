import SwiftUI

/// Edits one detected item on the review screen. Changes apply on Done.
struct CandidateEditorSheet: View {
    let original: ImportCandidate
    let onSave: (ImportCandidate) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ImportCandidate
    @State private var hasDate: Bool
    @State private var date: Date

    init(candidate: ImportCandidate, onSave: @escaping (ImportCandidate) -> Void, onDelete: @escaping () -> Void) {
        self.original = candidate
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: candidate)
        _hasDate = State(initialValue: candidate.dueDate != nil)
        _date = State(initialValue: candidate.dueDate ?? Self.tomorrowEvening())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if original.dateText != nil || original.reviewReason != nil {
                        syllabusCard
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                        TextField("e.g. Problem Set 3", text: $draft.title)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    VStack(spacing: 0) {
                        HStack {
                            RowLabel("Type", icon: draft.kind.icon)
                            Spacer()
                            // Outside a Form a menu picker shows only its button, so label it here.
                            Picker("Type", selection: $draft.kind) {
                                ForEach(AssignmentKind.allCases) { kind in
                                    Label(kind.label, appIcon: kind.icon).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .frame(minHeight: 52)

                        Divider()
                        Toggle(isOn: $hasDate.animation(.snappy)) {
                            RowLabel("Due date", icon: .calendar)
                        }
                        .tint(Palette.onTimeGreen)
                        .frame(minHeight: 52)

                        if hasDate {
                            Divider()
                            DatePicker(selection: $date, displayedComponents: .date) {
                                RowLabel("Day", icon: .calendar)
                            }
                            .frame(minHeight: 52)
                            Divider()
                            DatePicker(selection: $date, displayedComponents: .hourAndMinute) {
                                RowLabel("Time", icon: .clock)
                            }
                            .frame(minHeight: 52)
                        }

                        Divider()
                        HStack {
                            RowLabel("Weight", icon: .badge)
                            TextField("e.g. 15%", text: Binding(
                                get: { draft.weight ?? "" },
                                set: { draft.weight = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 52)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .glassCard()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                        TextField("Add details", text: $draft.notes, axis: .vertical)
                            .lineLimit(2...8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()

                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        // No delete glyph in the app's icon set; SF Symbol fallback.
                        Label("Remove from Import", systemImage: "trash")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .duskGlass(in: Capsule(), interactive: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background { DuskBackground() }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(original.title.isEmpty ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        // A brand-new, untouched item is discarded rather than left blank.
                        if original.title.isEmpty, draft.title.trimmingCharacters(in: .whitespaces).isEmpty { onDelete() }
                        dismiss()
                    } label: {
                        Label("Cancel", appIcon: .close)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm, action: save) { Label("Done", appIcon: .check) }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var syllabusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In the syllabus")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
            if let text = original.dateText {
                Text("“\(text)”")
                    .font(.subheadline)
            }
            if let reason = original.reviewReason {
                Label { Text(reason) } icon: { AppIcon(.info, size: 16) }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.warning)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func save() {
        var updated = draft
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasDate {
            if updated.dueDate != date || updated.reviewReason != nil {
                // Picking or confirming a date resolves the review flag.
                updated.dueDate = date
                updated.dateStatus = .confident
                updated.dateSetByUser = true
            }
            // A newly dated item becomes importable unless it duplicates one in the class.
            if original.dueDate == nil, updated.duplicateOf == nil { updated.isIncluded = true }
        } else {
            updated.dueDate = nil
            updated.dateStatus = .missing("No date")
            updated.dateSetByUser = true
            updated.isIncluded = false
        }
        onSave(updated)
        dismiss()
    }

    private static func tomorrowEvening() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow)!
    }
}

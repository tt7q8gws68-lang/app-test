import SwiftData
import SwiftUI

/// Step two: every detected item, grouped by how much attention it needs. Items can be
/// checked off, edited, deleted or added before anything is saved.
struct ImportReviewView: View {
    @Bindable var model: SyllabusImportModel
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editing: ImportCandidate.ID?
    @State private var notificationsBlocked = false

    private enum ReviewGroup: CaseIterable {
        case check, ready, noDate, past, duplicate

        var title: String {
            switch self {
            case .check: "Check these dates"
            case .ready: "Ready to add"
            case .noDate: "Needs a date"
            case .past: "Already passed · added as done"
            case .duplicate: "Already in this class"
            }
        }
    }

    private func group(of candidate: ImportCandidate) -> ReviewGroup {
        guard candidate.dueDate != nil else { return .noDate }
        if candidate.duplicateOf != nil { return .duplicate }
        if model.isPast(candidate) { return .past }
        return candidate.reviewReason == nil ? .ready : .check
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if model.candidates.isEmpty {
                    VStack(spacing: 8) {
                        Text("No assignments found")
                            .font(.headline)
                        Text("This syllabus didn’t list any graded work the app could recognize. You can add items yourself.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .glassCard()
                }

                ForEach(ReviewGroup.allCases, id: \.self) { group in
                    let items = model.candidates
                        .filter { self.group(of: $0) == group }
                        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SectionHeader(group.title)
                                Spacer()
                                if group == .past {
                                    let allIncluded = items.allSatisfy(\.isIncluded)
                                    Button(allIncluded ? "Skip All" : "Add All") {
                                        withAnimation(.snappy) { model.setPastIncluded(!allIncluded) }
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.trailing, 4)
                                }
                            }
                            ForEach(items) { candidate in
                                CandidateRow(
                                    candidate: candidate,
                                    courseName: model.course?.name,
                                    tint: model.course?.color ?? Palette.accent,
                                    onToggle: { model.toggleIncluded(candidate.id) },
                                    onOpen: { editing = candidate.id }
                                )
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = candidate.id }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        withAnimation(.snappy) { model.delete(candidate.id) }
                                    }
                                }
                            }
                        }
                    }
                }

                Button {
                    editing = model.addCandidate()
                } label: {
                    HStack(spacing: 8) {
                        AppIcon(.add, size: 20)
                        Text("Add Item")
                    }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .duskGlass(in: Capsule(), interactive: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: model.candidates)
        }
        .background { DuskBackground() }
        .task { notificationsBlocked = await ReminderScheduler.isDenied() }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    model.save(in: modelContext)
                    onFinished()
                } label: {
                    Text(saveTitle)
                        .font(.headline)
                        .foregroundStyle(Palette.onAccentFill)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accentFill(in: Capsule())
                .disabled(model.includedCount == 0)
                .opacity(model.includedCount == 0 ? 0.5 : 1)
                if let saveFootnote {
                    Text(saveFootnote)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(item: Binding(
            get: { editing.flatMap { id in model.candidates.first { $0.id == id } } },
            set: { editing = $0?.id }
        )) { candidate in
            CandidateEditorSheet(candidate: candidate) { updated in
                if let index = model.candidates.firstIndex(where: { $0.id == updated.id }) {
                    model.candidates[index] = updated
                }
            } onDelete: {
                model.delete(candidate.id)
            }
        }
    }

    private var saveTitle: String {
        let count = model.includedCount
        let noun = count == 1 ? "Assignment" : "Assignments"
        return "Add \(count) \(noun) to \(model.course?.name ?? "Class")"
    }

    private var saveFootnote: String? {
        let past = model.pastIncludedCount
        guard past > 0 else { return nil }
        return past == 1 ? "1 past item will be marked done" : "\(past) past items will be marked done"
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                AppIcon(.notes, size: 22)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.sourceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(sourceDetail)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(.vertical, 12)

            Divider()
            engineRow.padding(.vertical, 12)

            if model.alreadyImported {
                Divider()
                Label {
                    Text("You’ve imported this syllabus into \(model.course?.name ?? "this class") before. Items already in the class are unchecked.")
                } icon: {
                    AppIcon(.info, size: 18).foregroundStyle(Palette.warning)
                }
                .font(.footnote)
                .padding(.vertical, 12)
            }

            Divider()
            termStartRow.padding(.vertical, 6)

            Divider()
            Toggle(isOn: $model.remindDayBefore) {
                RowLabel("Remind me a day before", icon: .reminder)
            }
            .tint(Palette.onTimeGreen)
            .frame(minHeight: 52)
            if model.remindDayBefore && notificationsBlocked {
                Text("Notifications are off for this app, so reminders won’t appear. Turn them on in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 16)
        .glassCard()
    }

    private var sourceDetail: String {
        var parts = ["\(model.candidates.count) found", "\(model.includedCount) selected"]
        if model.undatedCount > 0 { parts.append("\(model.undatedCount) need a date") }
        if model.pageCount > 1 { parts.append("\(model.pageCount) pages") }
        if model.recognizedPageCount > 0 {
            parts.append(model.recognizedPageCount == model.pageCount ? "text recognized from image" : "\(model.recognizedPageCount) scanned pages recognized")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var engineRow: some View {
        switch model.engine {
        case .onDeviceModel:
            // No Apple Intelligence glyph in the app's icon set; SF Symbol fallback.
            Label("Found with Apple Intelligence, on this iPhone", systemImage: "apple.intelligence")
                .font(.footnote)
        case .rules(let reason):
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found with basic pattern matching")
                    if let reason {
                        Text("\(reason). Check the list carefully.")
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            } icon: {
                AppIcon(.search, size: 18)
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private var termStartRow: some View {
        if let termStart = model.termStart {
            DatePicker(selection: Binding(get: { termStart }, set: { model.termStart = $0 }), displayedComponents: .date) {
                VStack(alignment: .leading, spacing: 2) {
                    RowLabel("Classes start", icon: .calendar)
                    Text("Places dates like “Week 3, Friday”")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.leading, 36)
                }
            }
            .frame(minHeight: 52)
        } else {
            Button {
                model.termStart = model.startOfReferenceDay
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        RowLabel("Set when classes start", icon: .plan)
                        Text(model.usesRelativeWeeks
                             ? "Needed for dates like “Week 3, Friday”"
                             : "The syllabus doesn’t say")
                            .font(.caption)
                            .foregroundStyle(model.usesRelativeWeeks ? Palette.warning : Palette.secondaryText)
                            .padding(.leading, 36)
                    }
                    Spacer()
                }
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CandidateRow: View {
    let candidate: ImportCandidate
    let courseName: String?
    let tint: Color
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: candidate.dueDate == nil ? onOpen : onToggle) {
                CheckCircle(isOn: candidate.isIncluded, tint: candidate.dueDate == nil ? Palette.mutedNumber : tint)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(candidate.isIncluded ? "Don’t add \(candidate.title)" : "Add \(candidate.title)")

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(candidate.isIncluded ? Palette.text : Palette.completedText)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            AppIcon(candidate.kind.icon, size: 14)
                            Text(dateLabel)
                            if let weight = candidate.weight {
                                Text("·")
                                Text(weight)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)

                        if let note = attentionNote {
                            // No duplicate or warning glyph in the app's icon set; SF Symbol fallbacks.
                            Label(note, systemImage: candidate.duplicateOf != nil ? "doc.on.doc" : "exclamationmark.triangle")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(candidate.duplicateOf != nil ? Palette.secondaryText : Palette.warning)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AppIcon(.forward, size: 16)
                        .foregroundStyle(Palette.mutedNumber)
                }
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .glassCard(cornerRadius: 22)
    }

    private var dateLabel: String {
        guard let due = candidate.dueDate else { return candidate.dateText ?? "No date" }
        let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day), \(due.formatted(date: .omitted, time: .shortened))"
    }

    private var attentionNote: String? {
        if let duplicate = candidate.duplicateOf {
            return "Already in \(courseName ?? "this class") as “\(duplicate)”"
        }
        return candidate.reviewReason
    }
}

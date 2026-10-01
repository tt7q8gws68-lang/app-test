import SwiftData
import SwiftUI

struct AssignmentDetailView: View {
    @Bindable var assignment: Assignment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @FocusState private var isAddingStep: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                StepsCard(assignment: assignment, isAddFieldFocused: $isAddingStep)

                if !assignment.isCompleted {
                    PlanCard(assignment: assignment)
                }

                if !assignment.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Palette.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(assignment.notes)
                            .font(.subheadline)
                            .lineSpacing(3)
                            .foregroundStyle(.primary.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(cornerRadius: 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground(variant: .detail) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More options", systemImage: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Hidden while typing a step so it doesn't ride up over the card on the keyboard.
            if !isAddingStep {
                completeButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $isEditing) {
            AssignmentEditorSheet(assignment: assignment)
        }
        .confirmationDialog(
            "Delete “\(assignment.title)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Assignment", role: .destructive) {
                dismiss()
                assignment.delete(from: modelContext)
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let course = assignment.course {
                HStack(spacing: 8) {
                    Circle()
                        .fill(course.color)
                        .frame(width: 8, height: 8)
                    Text(course.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                }
                .accessibilityElement(children: .combine)
            }

            Text(assignment.title)
                .font(.system(.title, weight: .bold))
                .tracking(-0.7)
                .accessibilityAddTraits(.isHeader)

            FlowLayout(spacing: 8) {
                Tag(text: dueText, systemImage: "clock", color: isOverdue ? Palette.danger : nil)
                    .accessibilityLabel("Due \(dueText)")
                Tag(text: "\(assignment.priority.label) priority", systemImage: "flag", color: assignment.priority.color)
                if let weight = assignment.weight {
                    Tag(text: weight.hasSuffix("%") ? "\(weight) of grade" : weight, systemImage: "percent", color: nil)
                }
                if assignment.kind != .assignment {
                    Tag(text: assignment.kind.label, systemImage: assignment.kind.systemImage, color: nil)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }

    private var isOverdue: Bool {
        !assignment.isCompleted && assignment.dueDate < .now
    }

    private var dueText: String {
        "\(assignment.dueDate.dueDayLabel()), \(assignment.dueDate.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var completeButton: some View {
        if assignment.isCompleted {
            Button(action: assignment.toggleCompleted) {
                Label("Completed · Undo", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Palette.accentText)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Button(action: assignment.toggleCompleted) {
                Label("Mark as complete", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
        }
    }
}

/// A small glass capsule with an icon, for the due date, priority, weight and type.
private struct Tag: View {
    let text: String
    let systemImage: String
    /// Colors icon and text; nil uses primary text with a secondary icon.
    let color: Color?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color ?? Palette.secondaryText)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color ?? .primary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = ModelContainer.preview
    let assignment = try! container.mainContext
        .fetch(FetchDescriptor<Assignment>(sortBy: [SortDescriptor(\.dueDate, order: .reverse)]))
        .first { !$0.steps.isEmpty }!
    return NavigationStack {
        AssignmentDetailView(assignment: assignment)
    }
    .modelContainer(container)
}

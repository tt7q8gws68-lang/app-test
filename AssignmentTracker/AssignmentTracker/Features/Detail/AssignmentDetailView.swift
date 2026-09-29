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
            VStack(alignment: .leading, spacing: 22) {
                header

                GlassEffectContainer {
                    HStack(alignment: .top, spacing: 12) {
                        InfoTile(
                            label: "Due",
                            value: assignment.dueDate.dueDayLabel(),
                            detail: assignment.dueDate.formatted(date: .omitted, time: .shortened),
                            valueColor: !assignment.isCompleted && assignment.dueDate < .now ? Palette.danger : nil
                        )
                        InfoTile(
                            label: "Priority",
                            value: assignment.priority.label,
                            detail: nil,
                            valueColor: assignment.priority.color
                        )
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                StepsCard(assignment: assignment, isAddFieldFocused: $isAddingStep)

                if !assignment.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(assignment.notes)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .glassCard(cornerRadius: 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientBackground(variant: .detail) }
        .navigationBarTitleDisplayMode(.inline)
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
                    .padding(.bottom, 8)
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
        VStack(alignment: .leading, spacing: 12) {
            if let course = assignment.course {
                HStack(spacing: 8) {
                    Circle()
                        .fill(course.color)
                        .frame(width: 8, height: 8)
                    Text(course.name)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
            }

            Text(assignment.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var completeButton: some View {
        if assignment.isCompleted {
            Button(action: assignment.toggleCompleted) {
                Label("Completed · Undo", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        } else {
            Button(action: assignment.toggleCompleted) {
                Text("Mark as complete")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

private struct InfoTile: View {
    let label: String
    let value: String
    let detail: String?
    var valueColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(valueColor ?? .primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .glassCard()
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

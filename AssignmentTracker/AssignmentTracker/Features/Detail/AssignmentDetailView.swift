import SwiftData
import SwiftUI

struct AssignmentDetailView: View {
    @Bindable var assignment: Assignment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentTime) private var now
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
                            .foregroundStyle(Palette.tertiaryText)
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
        // Room for the pinned button (58pt + its padding), so nothing can rest behind it.
        .contentMargins(.bottom, isAddingStep ? 0 : Self.buttonArea, for: .scrollContent)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .background { DuskBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .duskBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Edit and delete have no glyph in the app's icon set; SF Symbol fallbacks.
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More options", appIcon: .more)
                }
            }
        }
        .overlay(alignment: .bottom) {
            // Hidden while typing a step so it doesn't ride up over the card on the keyboard.
            if !isAddingStep {
                completeButton
                    .padding(.horizontal, 20)
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

    private static let buttonArea: CGFloat = 58 + 4 + 16

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
                Tag(text: dueText, icon: .clock, color: isOverdue ? Palette.danger : nil)
                    .accessibilityLabel("Due \(dueText)")
                Tag(text: "\(assignment.priority.label) priority", icon: .priority, color: assignment.priority.color)
                if let weight = assignment.weight {
                    Tag(text: weight.hasSuffix("%") ? "\(weight) of grade" : weight, icon: .badge, color: nil)
                }
                if assignment.kind != .assignment {
                    Tag(text: assignment.kind.label, icon: assignment.kind.icon, color: nil)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }

    private var isOverdue: Bool {
        !assignment.isCompleted && assignment.dueDate < now
    }

    private var dueText: String {
        "\(assignment.dueDate.dueDayLabel()), \(assignment.dueDate.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var completeButton: some View {
        if assignment.isCompleted {
            Button(action: assignment.toggleCompleted) {
                HStack(spacing: 10) {
                    AppIcon(.check, size: 20, weight: 2.4)
                    Text("Completed · Undo")
                }
                .font(.headline)
                .foregroundStyle(Palette.accentText)
                .frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .duskGlass(in: Capsule(), interactive: true)
        } else {
            Button(action: assignment.toggleCompleted) {
                HStack(spacing: 10) {
                    AppIcon(.check, size: 20, weight: 2.4)
                    Text("Mark as complete")
                }
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accentFill(in: Capsule())
        }
    }
}

/// A small glass capsule with an icon, for the due date, priority, weight and type.
private struct Tag: View {
    let text: String
    let icon: AppIcon.Name
    /// Colors icon and text; nil uses the text color with a secondary icon.
    let color: Color?

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(icon, size: 16)
                .foregroundStyle(color ?? Palette.secondaryText)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color ?? Palette.text)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(minHeight: 36)
        .duskGlass(in: Capsule())
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

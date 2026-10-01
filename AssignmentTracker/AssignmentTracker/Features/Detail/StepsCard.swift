import SwiftData
import SwiftUI

struct StepsCard: View {
    let assignment: Assignment
    /// Owned by the detail screen so it can hide its bottom button while the keyboard is up.
    var isAddFieldFocused: FocusState<Bool>.Binding

    @Environment(\.modelContext) private var modelContext
    @State private var newStepTitle = ""

    private var steps: [Step] { assignment.sortedSteps }

    var body: some View {
        let done = steps.filter(\.isDone).count
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Steps")
                        .font(.body.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if !steps.isEmpty {
                        Text("\(done) of \(steps.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.secondaryText)
                            .contentTransition(.numericText())
                    }
                }
                if !steps.isEmpty {
                    ThinProgressBar(fraction: Double(done) / Double(steps.count))
                        .animation(.snappy, value: done)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(steps) { step in
                Button {
                    withAnimation(.snappy) { step.isDone.toggle() }
                } label: {
                    HStack(spacing: 14) {
                        CheckCircle(isOn: step.isDone, tint: step.isDone ? Palette.accent : Palette.mutedNumber)
                        Text(step.title)
                            .font(.body)
                            .strikethrough(step.isDone)
                            .foregroundStyle(step.isDone ? Palette.completedText : Palette.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(step.isDone ? .isSelected : [])
                .contextMenu {
                    Button("Delete Step", systemImage: "trash", role: .destructive) {
                        delete(step)
                    }
                }
            }

            HStack(spacing: 14) {
                AppIcon(.add, size: 22)
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                TextField(
                    "Add step", text: $newStepTitle,
                    prompt: Text("Add step").foregroundStyle(Palette.accentText).fontWeight(.medium)
                )
                .focused(isAddFieldFocused)
                .submitLabel(.done)
                .onSubmit(addStep)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
        }
        .padding(6)
        .glassCard(cornerRadius: 26)
    }

    private func addStep() {
        let title = newStepTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let nextIndex = (steps.map(\.sortIndex).max() ?? -1) + 1
        withAnimation(.snappy) {
            assignment.steps.append(Step(title: title, sortIndex: nextIndex))
        }
        newStepTitle = ""
        isAddFieldFocused.wrappedValue = true
    }

    private func delete(_ step: Step) {
        withAnimation(.snappy) {
            assignment.steps.removeAll { $0 == step }
            modelContext.delete(step)
        }
    }
}

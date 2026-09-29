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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Steps")
                    .font(.headline)
                Spacer()
                if !steps.isEmpty {
                    Text("\(steps.filter(\.isDone).count) of \(steps.count)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(steps) { step in
                Button {
                    withAnimation(.snappy) { step.isDone.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        CheckCircle(isOn: step.isDone, tint: step.isDone ? .accentColor : Palette.openStep)
                        Text(step.title)
                            .strikethrough(step.isDone)
                            .foregroundStyle(step.isDone ? Palette.completedText : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
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

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
                TextField("Add step", text: $newStepTitle)
                    .focused(isAddFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(addStep)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
        }
        .padding(8)
        .glassCard(cornerRadius: 24)
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

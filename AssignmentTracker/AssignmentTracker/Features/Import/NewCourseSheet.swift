import SwiftData
import SwiftUI

/// Adds a class, for importing a syllabus from a course that isn't in the app yet.
struct NewCourseSheet: View {
    let onCreate: (Course) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @State private var name = ""
    @State private var color: CourseColor = .blue
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDuplicateName: Bool {
        courses.contains { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.secondaryText)
                    TextField("e.g. Financial Accounting", text: $name)
                        .font(.title3.weight(.semibold))
                        .focused($isNameFocused)
                        .submitLabel(.done)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if isDuplicateName {
                    Text("You already have a class with this name.")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Color")
                    HStack(spacing: 14) {
                        ForEach(CourseColor.allCases, id: \.self) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if option == color {
                                            Image(systemName: "checkmark")
                                                .font(.footnote.weight(.bold))
                                                .foregroundStyle(Palette.onFill)
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.rawValue.capitalized)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassCard(cornerRadius: 28)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("New Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", systemImage: "checkmark", role: .confirm, action: create)
                        .disabled(trimmedName.isEmpty || isDuplicateName)
                }
            }
            .onAppear {
                isNameFocused = true
                // Suggest the least-used color.
                let used = Dictionary(grouping: courses, by: \.colorToken).mapValues(\.count)
                color = CourseColor.allCases.min { used[$0, default: 0] < used[$1, default: 0] } ?? .blue
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        let course = Course(name: trimmedName, color: color, sortIndex: (courses.map(\.sortIndex).max() ?? -1) + 1)
        modelContext.insert(course)
        onCreate(course)
        dismiss()
    }
}

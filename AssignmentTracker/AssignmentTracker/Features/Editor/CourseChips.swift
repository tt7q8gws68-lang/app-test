import SwiftUI

struct CourseChips: View {
    let courses: [Course]
    @Binding var selection: Course?
    /// When set, a trailing "New Class" chip calls this.
    var onAddCourse: (() -> Void)?

    var body: some View {
        GlassEffectContainer {
            FlowLayout(spacing: 8) {
                ForEach(courses) { course in
                    chip(for: course)
                }
                if let onAddCourse {
                    Button(action: onAddCourse) {
                        HStack(spacing: 6) {
                            AppIcon(.add, size: 16)
                            Text("New Class")
                        }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.accentText)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .duskGlass(in: Capsule(), interactive: true)
                }
            }
        }
    }

    private func chip(for course: Course) -> some View {
        let isSelected = course == selection
        return Button {
            withAnimation(.snappy) { selection = course }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(course.color)
                    .frame(width: 8, height: 8)
                Text(course.name)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(course.color, lineWidth: 2)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected { Capsule().fill(course.color.opacity(0.14)) }
        }
        .duskGlass(in: Capsule(), interactive: true)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

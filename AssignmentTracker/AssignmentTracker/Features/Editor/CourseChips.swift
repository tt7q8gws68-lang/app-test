import SwiftUI

struct CourseChips: View {
    let courses: [Course]
    @Binding var selection: Course?

    var body: some View {
        GlassEffectContainer {
            FlowLayout(spacing: 8) {
                ForEach(courses) { course in
                    chip(for: course)
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
        .glassEffect(
            isSelected ? .regular.tint(course.color.opacity(0.18)).interactive() : .regular.interactive(),
            in: .capsule
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

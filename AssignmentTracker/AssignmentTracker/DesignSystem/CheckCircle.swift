import SwiftUI

/// Filled circle with a checkmark when on, an outlined ring when off.
struct CheckCircle: View {
    var isOn: Bool
    var tint: Color

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(tint)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.onFill)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .padding(1)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}

#Preview {
    HStack(spacing: 20) {
        CheckCircle(isOn: false, tint: CourseColor.blue.color)
        CheckCircle(isOn: true, tint: CourseColor.orange.color)
    }
    .padding()
}

import SwiftUI

/// A course-colored check: an open 20pt ring (2pt stroke) when off, a filled 24pt circle with
/// a check when on.
struct CheckCircle: View {
    var isOn: Bool
    var tint: Color

    var body: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(tint)
                    .frame(width: 24, height: 24)
                AppIcon(.check, size: 14, weight: 3)
                    .foregroundStyle(Palette.onAccent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}

#Preview {
    HStack(spacing: 20) {
        CheckCircle(isOn: false, tint: CourseColor.blue.color)
        CheckCircle(isOn: true, tint: CourseColor.pink.color)
    }
    .padding()
}

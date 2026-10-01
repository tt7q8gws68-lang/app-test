import SwiftUI

/// A 44pt circular icon button: Dusk glass, or a solid accent fill for the primary action.
/// Icon-only, so it always needs an accessibility label.
struct GlassCircleButton: View {
    let icon: AppIcon.Name
    let label: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppIcon(icon, size: isProminent ? 22 : 20, weight: isProminent ? 2.2 : nil)
                .foregroundStyle(isProminent ? Color.white : Palette.text)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .modifier(CircleSurface(isProminent: isProminent))
        .accessibilityLabel(label)
    }
}

private struct CircleSurface: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            content.accentFill(in: Circle())
        } else {
            content.duskGlass(in: Circle(), interactive: true)
        }
    }
}

/// A glass capsule button with a short text label (e.g. "Today"), at least 44pt tall.
struct GlassCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .duskGlass(in: Capsule(), interactive: true)
    }
}

/// A segmented control for filters and modes: the system one, so the selection is the real
/// Liquid Glass thumb that lifts, stretches and can be dragged between segments.
struct GlassSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        Picker(selection: $selection.animation(.snappy)) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}

/// A progress ring: a track with an accent-to-pink gradient arc and content in the middle.
struct ProgressRing<Center: View>: View {
    let fraction: Double
    var diameter: CGFloat = 76
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Group {
                Circle()
                    .stroke(Palette.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [Palette.accent, Palette.ringEnd],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(max(360 * fraction, 1))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            // Inset by half the stroke so the ring's outer edge is exactly `diameter`.
            .padding(lineWidth / 2)
            center
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy, value: fraction)
    }
}

/// One glass panel holding rows that are separated by thin inset dividers.
struct GlassGroup<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: cornerRadius)
    }
}

/// A thin divider that starts after a leading tile, as in the grouped panels.
struct InsetDivider: View {
    var leading: CGFloat = 70

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
            .padding(.trailing, 12)
            .accessibilityHidden(true)
    }
}

/// A rounded-square tile showing text or a symbol in a color on a ~14% tint of that color.
struct TintTile: View {
    enum Content {
        case text(String)
        case icon(AppIcon.Name)
    }

    let content: Content
    let color: Color
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                switch content {
                case .text(let text):
                    Text(text)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(color)
                case .icon(let name):
                    AppIcon(name, size: size * 0.5)
                        .foregroundStyle(color)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A thin capsule progress bar.
struct ThinProgressBar: View {
    let fraction: Double
    var tint: Color = Palette.accent

    var body: some View {
        Capsule()
            .fill(Palette.track)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .clipShape(.capsule)
            .accessibilityHidden(true)
    }
}

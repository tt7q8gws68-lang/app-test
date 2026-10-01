import SwiftUI

/// A 44pt circular icon button. Icon-only, so it always needs an accessibility label.
/// Drawn with `glassEffect` directly: the system glass button styles add their own padding,
/// which makes them larger than the 44pt in the designs.
struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: isProminent ? .bold : .semibold))
                .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isProminent ? .regular.tint(Palette.accentButton).interactive() : .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel(label)
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
            .fill(Palette.divider)
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
        case symbol(String)
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
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(color)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A thin capsule progress bar.
struct ThinProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor

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

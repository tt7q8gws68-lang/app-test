import SwiftUI

extension View {
    /// A rounded Dusk glass surface: Liquid Glass with a violet-tinted fill, a thin bright border
    /// and a soft shadow (violet in light, deep black in dark).
    func glassCard(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        modifier(DuskGlass(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive))
    }

    func duskGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(DuskGlass(shape: shape, interactive: interactive))
    }

    /// A solid accent surface (the + and Mark as complete buttons): accent at 92%, a thin white
    /// border and an accent glow.
    func accentFill<S: Shape>(in shape: S) -> some View {
        background {
            shape.fill(Palette.accentFill.opacity(0.92))
                .overlay { shape.stroke(Color.white.opacity(0.4), lineWidth: 1) }
                .shadow(color: Palette.accentFill.opacity(0.35), radius: 10, y: 8)
        }
    }
}

private struct DuskGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(interactive ? .regular.tint(Palette.glassTint).interactive() : .regular.tint(Palette.glassTint), in: shape)
            .overlay { shape.stroke(Palette.glassBorder, lineWidth: 1).allowsHitTesting(false) }
            .shadow(color: Palette.glassShadow, radius: 15, y: 10)
    }
}

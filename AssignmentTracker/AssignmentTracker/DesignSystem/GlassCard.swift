import SwiftUI

extension View {
    /// A rounded Liquid Glass surface. It stays untinted: the Dusk look comes from the glows behind
    /// it, which the glass refracts. Tints, strokes and shadows on top flatten it into a plain card.
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
                .overlay { shape.stroke(Palette.onAccentFill.opacity(0.4), lineWidth: 1) }
                .shadow(color: Palette.accentFill.opacity(0.35), radius: 10, y: 8)
        }
    }
}

private struct DuskGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        content
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}

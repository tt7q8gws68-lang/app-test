import SwiftUI

/// The Dusk backdrop: the background color with three soft glows for the glass to refract.
/// Used behind every screen and sheet.
struct DuskBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct Glow: Identifiable {
        let id: Int
        let color: Color
        let diameter: CGFloat
        let center: UnitPoint
        let lightOpacity: Double
        let darkOpacity: Double
    }

    private static let glows = [
        Glow(id: 0, color: Palette.glowTopLeft, diameter: 320, center: UnitPoint(x: 0.18, y: 0.11), lightOpacity: 0.70, darkOpacity: 0.42),
        Glow(id: 1, color: Palette.glowRight, diameter: 300, center: UnitPoint(x: 0.90, y: 0.47), lightOpacity: 0.50, darkOpacity: 0.28),
        Glow(id: 2, color: Palette.glowBottomLeft, diameter: 280, center: UnitPoint(x: 0.26, y: 0.89), lightOpacity: 0.50, darkOpacity: 0.22),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Palette.background
                ForEach(Self.glows) { glow in
                    Circle()
                        .fill(glow.color)
                        .frame(width: glow.diameter, height: glow.diameter)
                        .position(x: proxy.size.width * glow.center.x, y: proxy.size.height * glow.center.y)
                        .opacity(colorScheme == .dark ? glow.darkOpacity : glow.lightOpacity)
                }
                .blur(radius: colorScheme == .dark ? 80 : 70)
            }
            // Rasterize the blurred glows once rather than re-blurring them on every composite;
            // the glass above samples this layer constantly.
            .drawingGroup()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    DuskBackground()
}

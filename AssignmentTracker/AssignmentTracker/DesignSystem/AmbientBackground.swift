import SwiftUI

/// Soft blurred color fields that give the Liquid Glass surfaces something to refract.
struct AmbientBackground: View {
    enum Variant { case list, detail }

    var variant: Variant = .list

    @Environment(\.colorScheme) private var colorScheme

    private struct Blob: Identifiable {
        let id: Int
        let color: Color
        let diameter: CGFloat
        let center: UnitPoint
        let lightOpacity: Double
        let darkOpacity: Double
    }

    private var blobs: [Blob] {
        switch variant {
        case .list:
            [
                Blob(id: 0, color: Palette.blobBlue, diameter: 320, center: UnitPoint(x: 0.18, y: 0.11), lightOpacity: 0.75, darkOpacity: 0.5),
                Blob(id: 1, color: Palette.blobPeach, diameter: 300, center: UnitPoint(x: 0.9, y: 0.47), lightOpacity: 0.6, darkOpacity: 0.32),
                Blob(id: 2, color: Palette.blobMint, diameter: 280, center: UnitPoint(x: 0.26, y: 0.89), lightOpacity: 0.65, darkOpacity: 0.35),
            ]
        case .detail:
            [
                Blob(id: 0, color: Palette.blobBlue, diameter: 340, center: UnitPoint(x: 0.82, y: 0.13), lightOpacity: 0.8, darkOpacity: 0.5),
                Blob(id: 1, color: Palette.blobLilac, diameter: 300, center: UnitPoint(x: 0.08, y: 0.63), lightOpacity: 0.5, darkOpacity: 0.35),
                Blob(id: 2, color: Palette.blobMint, diameter: 260, center: UnitPoint(x: 0.82, y: 0.94), lightOpacity: 0.6, darkOpacity: 0.35),
            ]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Palette.canvas
                ForEach(blobs) { blob in
                    Circle()
                        .fill(blob.color)
                        .frame(width: blob.diameter, height: blob.diameter)
                        .position(
                            x: proxy.size.width * blob.center.x,
                            y: proxy.size.height * blob.center.y
                        )
                        .opacity(colorScheme == .dark ? blob.darkOpacity : blob.lightOpacity)
                }
                .blur(radius: 70)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview {
    AmbientBackground()
}

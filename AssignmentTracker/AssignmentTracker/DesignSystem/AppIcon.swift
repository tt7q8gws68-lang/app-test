import SwiftUI
import UIKit

/// The app's one icon set: outline glyphs on a 24pt grid, 1.75 stroke, round caps and joins,
/// no fills. Draw with `AppIcon(.calendar, size: 22)`; it takes `foregroundStyle` like text.
struct AppIcon: View {
    nonisolated enum Name: String, CaseIterable, Sendable {
        case assignments, calendar, courses, streaks, add, search, scan, back, forward, more, info
        case check, close, clock, priority, plan, notes, reminder, badge, locked, settings, upcoming

        /// The design's SVG fragments, verbatim.
        var elements: [SVGPath.Element] {
            switch self {
            case .assignments: [.rect(x: 4, y: 4, width: 16, height: 16, radius: 4.5), .path("M8.5 12.2l2.4 2.4 4.6-4.8")]
            case .calendar: [.rect(x: 4, y: 5.5, width: 16, height: 14.5, radius: 4), .path("M4 10.5h16M9 3.5v3M15 3.5v3")]
            case .courses: [.path("M5.5 6A2 2 0 0 1 7.5 4H18.5v12.5H7.5a2 2 0 0 0-2 2z"), .path("M5.5 18.5a1.5 1.5 0 0 0 1.5 1.5h11.5")]
            case .streaks: [.path("M12 3.5c.8 3 4.5 4.8 4.5 9a4.5 4.5 0 0 1-9 0c0-1.9.8-3.2 1.8-4.1.3 1.4.9 2.2 1.8 2.6 0-2.8.2-5.1.9-7.5z")]
            case .add: [.path("M12 5.5v13M5.5 12h13")]
            case .search: [.circle(cx: 11, cy: 11, r: 6), .path("M19.5 19.5l-4-4")]
            case .scan: [.path("M4.5 9V7.5a3 3 0 0 1 3-3H9M15 4.5h1.5a3 3 0 0 1 3 3V9M19.5 15v1.5a3 3 0 0 1-3 3H15M9 19.5H7.5a3 3 0 0 1-3-3V15M8.5 12h7")]
            case .back: [.path("M14.5 6l-6 6 6 6")]
            case .forward: [.path("M9.5 6l6 6-6 6")]
            case .more: [.path("M6 12h.01M12 12h.01M18 12h.01")]
            case .info: [.circle(cx: 12, cy: 12, r: 8), .path("M12 11.2v4.8M12 8.2h.01")]
            case .check: [.path("M5.5 12.5l4 4 9-9")]
            case .close: [.path("M7 7l10 10M17 7L7 17")]
            case .clock: [.circle(cx: 12, cy: 12, r: 8), .path("M12 8v4l2.5 1.5")]
            case .priority: [.path("M6.5 20V4.5M6.5 5h10l-2 3.75 2 3.75h-10")]
            case .plan: [.rect(x: 4, y: 5.5, width: 16, height: 14.5, radius: 4), .path("M4 10.5h16M9 3.5v3M15 3.5v3M12 13v4M10 15h4")]
            case .notes: [.rect(x: 5, y: 4, width: 14, height: 16, radius: 3.5), .path("M9 9h6M9 12.5h6M9 16h3")]
            case .reminder: [.path("M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.5 1.5h-14z"), .path("M10.5 20.5h3")]
            case .badge: [.circle(cx: 12, cy: 9.5, r: 5), .path("M9.2 13.8L8.5 20l3.5-1.8 3.5 1.8-.7-6.2")]
            case .locked: [.rect(x: 5.5, y: 10.5, width: 13, height: 9.5, radius: 3), .path("M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5")]
            case .settings: [.path("M5 8h8M17 8h2M5 16h2M11 16h8"), .circle(cx: 15, cy: 8, r: 2), .circle(cx: 9, cy: 16, r: 2)]
            case .upcoming: [.path("M4 12h12M12 7l5 5-5 5"), .path("M20 5v14")]
            }
        }

        /// Stroke width on the 24pt grid. The "more" dots are drawn as thick round caps.
        var strokeWidth: CGFloat { self == .more ? 3 : 1.75 }

        /// The glyph in grid units (0…24), parsed once.
        var gridPath: Path { Self.cache[self] ?? Path() }

        private static let cache: [Name: Path] = Dictionary(
            uniqueKeysWithValues: allCases.map { ($0, SVGPath.path(for: $0.elements)) }
        )
    }

    let name: Name
    var size: CGFloat = 22
    /// Overrides the grid stroke width, e.g. a heavier check inside a small filled circle.
    var weight: CGFloat?

    init(_ name: Name, size: CGFloat = 22, weight: CGFloat? = nil) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    var body: some View {
        IconShape(name: name)
            .stroke(style: StrokeStyle(
                lineWidth: (weight ?? name.strokeWidth) * size / 24,
                lineCap: .round, lineJoin: .round
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An icon glyph scaled from the 24pt grid to any frame.
struct IconShape: Shape {
    let name: AppIcon.Name

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return name.gridPath.applying(
            CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale).scaledBy(x: scale, y: scale)
        )
    }
}

extension AppIcon {
    /// The icon as a template image, for places SwiftUI only accepts an `Image`
    /// (context menus, system menus).
    static func image(_ name: Name, pointSize: CGFloat = 22) -> Image {
        Image(uiImage: uiImage(name, pointSize: pointSize))
    }

    private static var imageCache: [String: UIImage] = [:]

    static func uiImage(_ name: Name, pointSize: CGFloat = 22) -> UIImage {
        let key = "\(name.rawValue)@\(pointSize)"
        if let cached = imageCache[key] { return cached }
        let size = CGSize(width: pointSize, height: pointSize)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cgPath = IconShape(name: name).path(in: CGRect(origin: .zero, size: size)).cgPath
            let g = context.cgContext
            g.addPath(cgPath)
            g.setLineWidth(name.strokeWidth * pointSize / 24)
            g.setLineCap(.round)
            g.setLineJoin(.round)
            g.setStrokeColor(UIColor.black.cgColor)
            g.strokePath()
        }.withRenderingMode(.alwaysTemplate)
        imageCache[key] = image
        return image
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label with an app icon, usable in menus.
    init(_ title: String, appIcon: AppIcon.Name) {
        self.init { Text(title) } icon: { AppIcon.image(appIcon) }
    }
}

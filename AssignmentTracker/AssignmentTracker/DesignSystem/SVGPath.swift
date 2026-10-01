import CoreGraphics
import SwiftUI

/// Turns SVG outline-icon markup into a SwiftUI `Path`, so the icon set can be drawn from the
/// exact fragments in the design (24×24 grid). Supports `path` data (M L H V C S Q T A Z, in
/// absolute and relative forms), `circle` and `rect` with corner radius.
nonisolated enum SVGPath {
    enum Element: Sendable {
        case path(String)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
        case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat)
    }

    static func path(for elements: [Element]) -> Path {
        var result = Path()
        for element in elements {
            switch element {
            case .path(let data):
                result.addPath(path(data))
            case .circle(let cx, let cy, let r):
                result.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            case .rect(let x, let y, let width, let height, let radius):
                result.addRoundedRect(
                    in: CGRect(x: x, y: y, width: width, height: height),
                    cornerSize: CGSize(width: radius, height: radius),
                    style: .circular
                )
            }
        }
        return result
    }

    /// Parses SVG path data.
    static func path(_ data: String) -> Path {
        var tokens = Tokenizer(data)
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "

        while let command = tokens.nextCommand(after: lastCommand) {
            let relative = command.isLowercase
            let upper = Character(command.uppercased())
            func point() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch upper {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                lastControl = nil
                // Further pairs after a move are implicit line-tos.
                lastCommand = relative ? "l" : "L"
                continue
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H":
                guard let x = tokens.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = tokens.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "S":
                let c1 = reflect(lastControl, around: current, if: "CS".contains(Character(lastCommand.uppercased())))
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            case "T":
                let c = reflect(lastControl, around: current, if: "QT".contains(Character(lastCommand.uppercased())))
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = c
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rotation = tokens.number(),
                      let largeArc = tokens.flag(), let sweep = tokens.flag(), let p = point()
                else { return path }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
                current = p
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
            default:
                return path
            }
            lastCommand = command
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, around point: CGPoint, if condition: Bool) -> CGPoint {
        guard condition, let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// SVG endpoint arc → center parameterization → cubic Béziers (at most 90° each).
    private static func addArc(
        to path: inout Path, from p0: CGPoint, to p1: CGPoint,
        rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Scale radii up if they can't span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = (ux * vy - uy * vx) < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        func onEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta1
        for index in 0..<segments {
            let t2 = t + step
            let start = onEllipse(t), end = index == segments - 1 ? p1 : onEllipse(t2)
            let d1 = derivative(t), d2 = derivative(t2)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + k * d1.x, y: start.y + k * d1.y),
                control2: CGPoint(x: end.x - k * d2.x, y: end.y - k * d2.y)
            )
            t = t2
        }
    }

    /// Splits path data into commands, numbers and arc flags. Handles compact forms such as
    /// "1.4.9" (two numbers) and "2-2" (a sign starting a new number).
    private struct Tokenizer {
        private let chars: [Character]
        private var index = 0

        init(_ string: String) {
            chars = Array(string)
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline {
                index += 1
            }
        }

        /// The next command letter, or the previous command repeated when numbers follow.
        mutating func nextCommand(after previous: Character) -> Character? {
            skipSeparators()
            guard index < chars.count else { return nil }
            if chars[index].isLetter {
                defer { index += 1 }
                return chars[index]
            }
            return previous == " " ? nil : previous
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = index
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            var sawDot = false
            var sawDigit = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    sawDigit = true
                } else if c == ".", !sawDot {
                    sawDot = true
                } else if (c == "e" || c == "E"), sawDigit {
                    index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                    continue
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return Double(String(chars[start..<index])).map { CGFloat($0) }
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
            defer { index += 1 }
            return chars[index] == "1"
        }
    }
}

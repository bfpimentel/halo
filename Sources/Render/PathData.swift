import CoreGraphics
import Foundation

/// SVG path data (`d` attribute) → CGPath: M L H V C S Q T A Z, absolute and relative, with implicit repeats
/// (extra pairs after M are line-tos). Stops at the first malformed command, keeping what it parsed.
public enum PathData {
    public static func parse(_ data: String) -> CGPath {
        var scanner = Tokens(data)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuadratic: CGPoint?
        var command: Character?

        while let next = scanner.command() ?? command.flatMap({ scanner.hasNumber ? implicit(after: $0) : nil }) {
            command = next
            let relative = next.isLowercase
            let origin = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }
            var control: CGPoint?
            var quadratic: CGPoint?

            switch next.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                start = p
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: origin.x + x, y: current.y)
                path.addLine(to: current)
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: origin.y + y)
                path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                control = c2
                current = p
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = lastControl.map { reflect($0, around: current) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                control = c2
                current = p
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                quadratic = c
                current = p
            case "T":
                guard let p = point() else { return path }
                let c = lastQuadratic.map { reflect($0, around: current) } ?? current
                path.addQuadCurve(to: p, control: c)
                quadratic = c
                current = p
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = point()
                else { return path }
                addArc(to: path, from: current, to: p, radii: CGSize(width: rx, height: ry), rotation: rotation, large: large, sweep: sweep)
                current = p
            case "Z":
                path.closeSubpath()
                current = start
            default:
                return path
            }
            lastControl = control
            lastQuadratic = quadratic
        }
        return path
    }

    /// Numbers right after a command repeat it; after M/m they are line-tos.
    private static func implicit(after command: Character) -> Character? {
        switch command {
        case "M": "L"
        case "m": "l"
        case "Z", "z": nil
        default: command
        }
    }

    private static func reflect(_ point: CGPoint, around center: CGPoint) -> CGPoint {
        CGPoint(x: 2 * center.x - point.x, y: 2 * center.y - point.y)
    }

    /// SVG's endpoint arc as cubic curves (spec F.6.5 / F.6.6: center parameterization, radii scaled up if too small).
    static func addArc(
        to path: CGMutablePath, from p1: CGPoint, to p2: CGPoint, radii: CGSize, rotation degrees: CGFloat, large: Bool, sweep: Bool
    ) {
        var rx = abs(radii.width)
        var ry = abs(radii.height)
        guard p1 != p2 else { return }
        guard rx > 0, ry > 0 else { return path.addLine(to: p2) }
        let phi = degrees * .pi / 180
        let (cosPhi, sinPhi) = (cos(phi), sin(phi))
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if large == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(
            x: cosPhi * cx1 - sinPhi * cy1 + (p1.x + p2.x) / 2,
            y: sinPhi * cx1 + cosPhi * cy1 + (p1.y + p2.y) / 2
        )
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))
            return sign * acos(min(1, max(-1, dot)))
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let k = 4 / 3 * tan(step / 4)
        func onEllipse(_ theta: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            let (c, s) = (cos(theta), sin(theta))
            let point = CGPoint(x: center.x + rx * c * cosPhi - ry * s * sinPhi, y: center.y + rx * c * sinPhi + ry * s * cosPhi)
            let tangent = CGPoint(x: -rx * s * cosPhi - ry * c * sinPhi, y: -rx * s * sinPhi + ry * c * cosPhi)
            return (point, tangent)
        }
        var theta = theta1
        for index in 0..<segments {
            let a = onEllipse(theta)
            let b = onEllipse(theta + step)
            let end = index == segments - 1 ? p2 : b.point
            path.addCurve(
                to: end,
                control1: CGPoint(x: a.point.x + k * a.tangent.x, y: a.point.y + k * a.tangent.y),
                control2: CGPoint(x: b.point.x - k * b.tangent.x, y: b.point.y - k * b.tangent.y)
            )
            theta += step
        }
    }

    /// Commands, numbers (`-1.5e2`, `.5.5` = two numbers) and arc flags, skipping whitespace and commas.
    private struct Tokens {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) { chars = Array(text) }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index].isWhitespace || chars[index] == "," { index += 1 }
        }

        var hasNumber: Bool {
            var copy = self
            copy.skipSeparators()
            guard copy.index < chars.count else { return false }
            let c = chars[copy.index]
            return c.isNumber || c == "-" || c == "+" || c == "."
        }

        mutating func command() -> Character? {
            skipSeparators()
            guard index < chars.count, chars[index].isLetter, chars[index] != "e", chars[index] != "E" else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < chars.count, chars[index] == "0" || chars[index] == "1" else { return nil }
            defer { index += 1 }
            return chars[index] == "1"
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false
            var seenExponent = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" {
                text.append(chars[index])
                index += 1
            }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    text.append(c)
                } else if c == ".", !seenDot, !seenExponent {
                    seenDot = true
                    text.append(c)
                } else if c == "e" || c == "E", !seenExponent, !text.isEmpty {
                    seenExponent = true
                    text.append(c)
                    if index + 1 < chars.count, chars[index + 1] == "-" || chars[index + 1] == "+" {
                        index += 1
                        text.append(chars[index])
                    }
                } else {
                    break
                }
                index += 1
            }
            return Double(text).map { CGFloat($0) }
        }
    }
}

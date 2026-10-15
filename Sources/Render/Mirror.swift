import AppKit

extension Timing {
    /// Seconds until the curve settles: `duration`, or a spring's own settling time.
    var length: Double {
        guard case .spring = curve else { return duration }
        let spring = basic("opacity")
        return spring.duration
    }

    /// Eased progress at `time` seconds into the animation (0 before it starts, 1 once settled; springs overshoot).
    func progress(at elapsed: Double) -> Double {
        let time = elapsed - startOffset
        if time <= 0 { return 0 }
        switch curve {
        case .spring(let stiffness, let damping, let mass):
            return Self.spring(time, stiffness: Double(stiffness), damping: Double(damping), mass: Double(mass))
        default:
            return time >= duration ? 1 : Self.bezier(timingFunction, Double(time / duration))
        }
    }

    /// A damped spring released from 0 toward 1 with no initial velocity.
    static func spring(_ t: Double, stiffness k: Double, damping c: Double, mass m: Double) -> Double {
        let omega = (k / m).squareRoot()
        let zeta = c / (2 * (k * m).squareRoot())
        if zeta < 1 {
            let damped = omega * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        }
        if zeta == 1 { return 1 - exp(-omega * t) * (1 + omega * t) }
        let root = (zeta * zeta - 1).squareRoot()
        let r1 = -omega * (zeta - root)
        let r2 = -omega * (zeta + root)
        return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
    }

    static func bezier(_ function: CAMediaTimingFunction, _ x: Double) -> Double {
        var p1: [Float] = [0, 0]
        var p2: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &p1)
        function.getControlPoint(at: 2, values: &p2)
        let (x1, y1, x2, y2) = (Double(p1[0]), Double(p1[1]), Double(p2[0]), Double(p2[1]))
        func sample(_ a: Double, _ b: Double, _ t: Double) -> Double { ((1 - 3 * b + 3 * a) * t + (3 * b - 6 * a)) * t * t + 3 * a * t }
        var low = 0.0
        var high = 1.0
        var t = x
        for _ in 0..<40 {
            if sample(x1, x2, t) < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(y1, y2, t)
    }
}

/// A node animation described as values over time, so it can be replayed on native views outside the layer tree.
struct MirroredAnimation {
    /// Value of each animated property (opacity 0…1, scale, rotate in degrees, translations) at `t` seconds.
    var curves: [AnimatedProperty: (Double) -> CGFloat]
    var length: Double
    var delay: Double = 0
    var repeatCount: Float = 1
    var autoreverses = false
    /// Keep the last frame once finished (exits, filled keyframes).
    var holds = false
}

extension Node {
    /// Replays `animation` on every text field in this subtree. Fields sit above the layer tree, so they don't inherit
    /// this node's animations; each gets the same opacity, plus a transform that moves it the way this node's
    /// transform moves the point under it: `t' = t + (I − R·S)(P − A)` for pivot `P` and field anchor `A`.
    func mirror(_ animation: MirroredAnimation, key: String) {
        let inputs = inputsInSubtree()
        guard !inputs.isEmpty, !animation.curves.isEmpty else { return }
        let transforms: Set<AnimatedProperty> = [.scale, .rotate, .translateX, .translateY]
        let animatesTransform = !transforms.isDisjoint(with: animation.curves.keys)
        let animatesOpacity = animation.curves[.opacity] != nil
        guard animatesTransform || animatesOpacity else { return }

        let steps = min(240, max(2, Int(animation.length * 60)))
        let times = (0...steps).map { Double($0) / Double(steps) * animation.length }
        func value(_ property: AnimatedProperty, _ t: Double, _ rest: CGFloat) -> CGFloat {
            animation.curves[property]?(t) ?? rest
        }
        let frame = frameInRoot
        let pivot = CGPoint(x: frame.minX + frame.width * style.originX, y: frame.minY + frame.height * style.originY)

        for input in inputs {
            guard input.field.superview != nil, let fieldLayer = input.field.layer else { continue }
            let field = input.field.frame
            let anchor = CGPoint(x: field.minX + field.width * fieldLayer.anchorPoint.x, y: field.minY + field.height * fieldLayer.anchorPoint.y)
            let offset = CGPoint(x: pivot.x - anchor.x, y: pivot.y - anchor.y)
            var tracks: [(String, [Any])] = []
            if animatesOpacity {
                tracks.append(("opacity", times.map { value(.opacity, $0, CGFloat(style.opacity)) }))
            }
            if animatesTransform {
                tracks.append(("transform", times.map { t -> NSValue in
                    let scale = value(.scale, t, style.scale)
                    let radians = value(.rotate, t, style.rotate) * .pi / 180
                    let (sine, cosine) = (sin(radians), cos(radians))
                    let moved = CGPoint(
                        x: scale * (cosine * offset.x - sine * offset.y),
                        y: scale * (sine * offset.x + cosine * offset.y)
                    )
                    let tx = value(.translateX, t, style.translateX) + offset.x - moved.x
                    let ty = value(.translateY, t, style.translateY) + offset.y - moved.y
                    var transform = CATransform3DMakeScale(scale, scale, 1)
                    transform = CATransform3DConcat(transform, CATransform3DMakeRotation(radians, 0, 0, 1))
                    transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(tx, ty, 0))
                    return NSValue(caTransform3D: transform)
                }))
            }
            for (keyPath, values) in tracks {
                let track = CAKeyframeAnimation(keyPath: keyPath)
                track.values = values
                track.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
                track.calculationMode = .linear
                track.duration = max(animation.length, 0.001)
                track.repeatCount = animation.repeatCount
                track.autoreverses = animation.autoreverses
                if animation.delay > 0 {
                    track.beginTime = CACurrentMediaTime() + animation.delay
                    track.fillMode = .backwards
                }
                if animation.holds {
                    track.fillMode = animation.delay > 0 ? .both : .forwards
                    track.isRemovedOnCompletion = false
                }
                fieldLayer.add(track, forKey: "\(key).\(keyPath)")
            }
        }
    }

    func removeMirror(_ key: String) {
        for input in inputsInSubtree() {
            input.field.layer?.removeAnimation(forKey: "\(key).opacity")
            input.field.layer?.removeAnimation(forKey: "\(key).transform")
        }
    }

    func inputsInSubtree() -> [Input] {
        ((self as? Input).map { [$0] } ?? []) + children.flatMap { $0.inputsInSubtree() }
    }

    /// A straight from → to curve per property, eased by `timing`.
    static func curves(_ endpoints: [AnimatedProperty: (from: CGFloat, to: CGFloat)], timing: Timing) -> [AnimatedProperty: (Double) -> CGFloat] {
        endpoints.mapValues { from, to in { t in from + (to - from) * CGFloat(timing.progress(at: t)) } }
    }

    func number(_ property: AnimatedProperty, in style: Style) -> CGFloat? {
        if case .number(let value) = property.value(in: style) { return value }
        return nil
    }

    func presented(_ property: AnimatedProperty) -> CGFloat? {
        guard let value = layer.presentation()?.value(forKeyPath: property.keyPath) as? NSNumber else { return nil }
        let number = CGFloat(value.doubleValue)
        return property == .rotate ? number * 180 / .pi : number
    }
}

extension Timing {
    /// The same timing with its delay folded into the curve (progress stays 0 until the delay passes).
    func delayed() -> Timing {
        var copy = self
        copy.delay = 0
        copy.startOffset = delay
        return copy
    }
}

extension Keyframes {
    /// These keyframes as value curves: the overall timing function maps time to a position along evenly spaced
    /// (or `keyTimes`-spaced) keyframes, interpolated linearly, like Core Animation does.
    func mirrored() -> MirroredAnimation {
        var curves: [AnimatedProperty: (Double) -> CGFloat] = [:]
        for (property, values) in tracks {
            let numbers = values.compactMap { value -> CGFloat? in
                if case .number(let number) = value { return number }
                return nil
            }
            guard numbers.count == values.count, numbers.count > 1 else { continue }
            let offsets = keyTimes ?? (0..<numbers.count).map { Double($0) / Double(numbers.count - 1) }
            let timing = Timing(duration: timing.duration, curve: timing.curve)
            curves[property] = { t in
                let u = timing.progress(at: t)
                guard let upper = offsets.firstIndex(where: { $0 >= u }) else { return numbers[numbers.count - 1] }
                guard upper > 0 else { return numbers[0] }
                let span = offsets[upper] - offsets[upper - 1]
                let fraction = span > 0 ? CGFloat((u - offsets[upper - 1]) / span) : 1
                return numbers[upper - 1] + (numbers[upper] - numbers[upper - 1]) * fraction
            }
        }
        return MirroredAnimation(
            curves: curves, length: timing.duration, delay: timing.delay,
            repeatCount: repeatCount, autoreverses: autoreverses, holds: fill
        )
    }
}

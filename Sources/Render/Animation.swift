import QuartzCore

public enum Curve: Equatable, Sendable {
    case linear, easeIn, easeOut, easeInOut
    case cubic(Float, Float, Float, Float)
    case spring(stiffness: CGFloat, damping: CGFloat, mass: CGFloat)

    public static let defaultSpring = Curve.spring(stiffness: 300, damping: 26, mass: 1)
}

public struct Timing: Equatable, Sendable {
    /// Seconds. Ignored by springs, which settle on their own schedule.
    public var duration: TimeInterval
    public var curve: Curve
    public var delay: TimeInterval
    /// Only for sampled curves (`Timing.progress`): time before the curve starts moving.
    var startOffset: TimeInterval = 0

    public init(duration: TimeInterval = 0.2, curve: Curve = .easeOut, delay: TimeInterval = 0) {
        self.duration = duration
        self.curve = curve
        self.delay = delay
    }

    func basic(_ keyPath: String) -> CABasicAnimation {
        let animation: CABasicAnimation
        if case .spring(let stiffness, let damping, let mass) = curve {
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.stiffness = stiffness
            spring.damping = damping
            spring.mass = mass
            spring.duration = spring.settlingDuration
            animation = spring
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = duration
            animation.timingFunction = timingFunction
        }
        apply(to: animation)
        return animation
    }

    func apply(to animation: CAAnimation) {
        guard delay > 0 else { return }
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
    }

    var timingFunction: CAMediaTimingFunction {
        switch curve {
        case .linear: CAMediaTimingFunction(name: .linear)
        case .easeIn: CAMediaTimingFunction(name: .easeIn)
        case .easeOut: CAMediaTimingFunction(name: .easeOut)
        case .easeInOut, .spring: CAMediaTimingFunction(name: .easeInEaseOut)
        case .cubic(let x1, let y1, let x2, let y2): CAMediaTimingFunction(controlPoints: x1, y1, x2, y2)
        }
    }
}

/// Paint properties that can be animated, with the Core Animation key path each one drives.
public enum AnimatedProperty: String, CaseIterable, Sendable {
    case opacity, background, borderColor, borderWidth, radius, scale, rotate, translateX, translateY

    var keyPath: String {
        switch self {
        case .opacity: "opacity"
        case .background: "backgroundColor"
        case .borderColor: "borderColor"
        case .borderWidth: "borderWidth"
        case .radius: "cornerRadius"
        case .scale: "transform.scale"
        case .rotate: "transform.rotation.z"
        case .translateX: "transform.translation.x"
        case .translateY: "transform.translation.y"
        }
    }

    func value(in style: Style) -> AnimatedValue {
        switch self {
        case .opacity: .number(CGFloat(style.opacity))
        case .background: .color(style.background)
        case .borderColor: .color(style.borderColor)
        case .borderWidth: .number(style.borderWidth)
        case .radius: .number(style.radius)
        case .scale: .number(style.scale)
        case .rotate: .number(style.rotate)
        case .translateX: .number(style.translateX)
        case .translateY: .number(style.translateY)
        }
    }
}

public enum AnimatedValue: Equatable, @unchecked Sendable {
    case number(CGFloat)
    case color(CGColor?)

    /// What Core Animation expects for `property` (rotation in radians, colors as CGColor, transparent for nil).
    func layerValue(for property: AnimatedProperty) -> Any {
        switch self {
        case .number(let value): property == .rotate ? value * .pi / 180 : value
        case .color(let color): color ?? CGColor(gray: 0, alpha: 0)
        }
    }
}

/// `from`/`to` values for enter and exit animations, and per-property keyframe values for `animate`.
public struct Keyframes: Sendable {
    public var tracks: [AnimatedProperty: [AnimatedValue]]
    public var keyTimes: [Double]?
    public var timing: Timing
    public var repeatCount: Float
    public var autoreverses: Bool
    /// Keep the last frame's values in the model once done (otherwise the layer returns to its style).
    public var fill: Bool

    public init(
        tracks: [AnimatedProperty: [AnimatedValue]], keyTimes: [Double]? = nil, timing: Timing = Timing(),
        repeatCount: Float = 1, autoreverses: Bool = false, fill: Bool = false
    ) {
        self.tracks = tracks
        self.keyTimes = keyTimes
        self.timing = timing
        self.repeatCount = repeatCount
        self.autoreverses = autoreverses
        self.fill = fill
    }

    func animation() -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = tracks.map { property, values in
            let track = CAKeyframeAnimation(keyPath: property.keyPath)
            track.values = values.map { $0.layerValue(for: property) }
            track.keyTimes = keyTimes?.map { NSNumber(value: $0) }
            track.timingFunction = timing.timingFunction
            track.duration = timing.duration
            return track
        }
        group.duration = timing.duration
        group.repeatCount = repeatCount
        group.autoreverses = autoreverses
        timing.apply(to: group)
        if fill {
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
        }
        return group
    }
}

/// An enter (`from` → style) or exit (style → `to`) animation.
public struct Transition: Sendable {
    public var values: [AnimatedProperty: AnimatedValue]
    public var timing: Timing

    public init(values: [AnimatedProperty: AnimatedValue], timing: Timing) {
        self.values = values
        self.timing = timing
    }
}

final class AnimationCompletion: NSObject, CAAnimationDelegate, @unchecked Sendable {
    private let done: @MainActor (Bool) -> Void

    init(_ done: @escaping @MainActor (Bool) -> Void) {
        self.done = done
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        MainActor.assumeIsolated { done(finished) }
    }
}

import JavaScriptCore
import Render

/// JS animation specs → `Render` animation types. Durations and delays arrive in milliseconds.
@MainActor
enum AnimationConversions {
    static func timing(_ value: JSValue?) -> Timing? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isNumber { return Timing(duration: value.toDouble() / 1000) }
        guard value.isObject else { return nil }
        var timing = Timing()
        if let duration = value.forProperty("duration"), duration.isNumber { timing.duration = duration.toDouble() / 1000 }
        if let delay = value.forProperty("delay"), delay.isNumber { timing.delay = delay.toDouble() / 1000 }
        if let curve = curve(value.forProperty("curve")) { timing.curve = curve }
        return timing
    }

    /// "linear" | "ease-in" | "ease-out" | "ease-in-out" | "spring" | [x1, y1, x2, y2] | { stiffness, damping, mass }
    static func curve(_ value: JSValue?) -> Curve? {
        guard let value, !value.isUndefined, !value.isNull else { return nil }
        if value.isString {
            switch value.toString() {
            case "linear": return .linear
            case "ease-in": return .easeIn
            case "ease-out": return .easeOut
            case "ease-in-out", "ease": return .easeInOut
            case "spring": return .defaultSpring
            default:
                Log.warn("unknown curve \"\(value.toString() ?? "")\"")
                return nil
            }
        }
        if value.isArray {
            let points = value.toArray().compactMap { ($0 as? NSNumber)?.floatValue }
            guard points.count == 4 else {
                Log.warn("a cubic-bezier curve needs 4 numbers")
                return nil
            }
            return .cubic(points[0], points[1], points[2], points[3])
        }
        guard value.isObject, case .spring(let stiffness, let damping, let mass) = Curve.defaultSpring else { return nil }
        return .spring(
            stiffness: number(value.forProperty("stiffness")) ?? stiffness,
            damping: number(value.forProperty("damping")) ?? damping,
            mass: number(value.forProperty("mass")) ?? mass
        )
    }

    /// `{ opacity: 200, scale: { duration: 300, curve: "spring" }, layout: 200, all: 150 }`
    /// Animated by `Shape` itself rather than through `AnimatedProperty`.
    static let shapeKeys: Set<String> = ["fill", "stroke", "track", "strokeWidth", "strokeStart", "strokeEnd", "path"]

    static func transitions(_ value: JSValue) -> [String: Timing] {
        guard value.isObject, let keys = value.toDictionary()?.keys else { return [:] }
        var result: [String: Timing] = [:]
        for case let key as String in keys {
            guard key == "all" || key == "layout" || shapeKeys.contains(key) || AnimatedProperty(rawValue: key) != nil else {
                Log.warn("transition: \"\(key)\" isn't animatable")
                continue
            }
            result[key] = timing(value.forProperty(key))
        }
        return result
    }

    static func animatedValue(_ value: JSValue, for property: AnimatedProperty) -> AnimatedValue? {
        switch property {
        case .background, .borderColor:
            return .color(Conversions.color(value))
        default:
            return number(value).map(AnimatedValue.number)
        }
    }

    /// `{ from: { opacity: 0, scale: 0.95 }, duration, curve, delay }` (enter) or `{ to: … }` (exit).
    static func transition(_ value: JSValue, key: String) -> Transition? {
        guard value.isObject, let values = value.forProperty(key), values.isObject else { return nil }
        var result: [AnimatedProperty: AnimatedValue] = [:]
        for property in AnimatedProperty.allCases {
            guard let raw = values.forProperty(property.rawValue), !raw.isUndefined,
                  let parsed = animatedValue(raw, for: property)
            else { continue }
            result[property] = parsed
        }
        return Transition(values: result, timing: timing(value) ?? Timing())
    }

    /// Tracks `{ rotate: [0, 360], opacity: [1, 0.4, 1] }` plus options
    /// `{ duration, curve, delay, repeat (number or Infinity), alternate, offsets, fill }`.
    static func keyframes(_ tracks: JSValue, _ options: JSValue) -> Keyframes {
        var parsed: [AnimatedProperty: [AnimatedValue]] = [:]
        for property in AnimatedProperty.allCases {
            guard let raw = tracks.forProperty(property.rawValue), raw.isArray else { continue }
            let count = Int(raw.forProperty("length")?.toInt32() ?? 0)
            parsed[property] = (0..<count).compactMap { raw.atIndex($0).flatMap { animatedValue($0, for: property) } }
        }
        var timing = timing(options) ?? Timing()
        if case .spring = timing.curve { timing.curve = .easeOut }
        let repeatValue = options.forProperty("repeat")
        let repeatCount: Float = repeatValue.map { $0.isNumber ? ($0.toDouble().isInfinite ? .infinity : Float($0.toDouble())) : 1 } ?? 1
        let offsets = options.forProperty("offsets").flatMap { $0.isArray ? $0.toArray().compactMap { ($0 as? NSNumber)?.doubleValue } : nil }
        return Keyframes(
            tracks: parsed, keyTimes: offsets, timing: timing, repeatCount: max(repeatCount, 1),
            autoreverses: options.forProperty("alternate")?.toBool() ?? false,
            fill: options.forProperty("fill")?.toBool() ?? false
        )
    }

    private static func number(_ value: JSValue?) -> CGFloat? {
        guard let value, value.isNumber else { return nil }
        return CGFloat(value.toDouble())
    }
}

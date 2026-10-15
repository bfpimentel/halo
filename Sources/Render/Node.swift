import AppKit
import yoga

@MainActor
public class Node {
    public let layer: CALayer
    let yoga: YGNodeRef
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?
    weak var owner: RenderRoot?

    /// The frame Yoga computed, relative to the parent and ignoring transforms (what hit-testing uses).
    public private(set) var layoutFrame: CGRect = .zero
    private var hasLaidOut = false

    /// Per-property timing (`AnimatedProperty` raw values, "all" as the fallback, "layout" for frame changes).
    public var transitions: [String: Timing] = [:]
    /// Played once, the first time the node is laid out.
    public var enter: Transition?
    /// Played when the node is removed through `remove(completion:)`; it leaves the layout at once.
    public var exit: Transition?

    public var style: Style {
        didSet {
            guard style != oldValue else { return }
            applyPaint(from: oldValue)
            applyLayout()
            if YGNodeIsDirty(yoga) { invalidate() }
        }
    }

    var contentsScale: CGFloat = 1 {
        didSet {
            guard contentsScale != oldValue else { return }
            layer.contentsScale = contentsScale
            contentsScaleDidChange()
            for child in children { child.contentsScale = contentsScale }
        }
    }

    var needsLayout: Bool { YGNodeIsDirty(yoga) }

    init(layer: CALayer, style: Style) {
        self.layer = layer
        self.style = style
        yoga = YGNodeNew()
        layer.delegate = NoImplicitActions.shared
        applyPaint(from: nil)
        applyLayout()
    }

    isolated deinit {
        YGNodeFree(yoga)
    }

    public func append(_ child: Node) {
        insert(child, at: children.count)
    }

    public func insert(_ child: Node, at index: Int) {
        child.removeFromParent()
        let index = min(max(index, 0), children.count)
        children.insert(child, at: index)
        child.parent = self
        child.contentsScale = contentsScale
        YGNodeInsertChild(yoga, child.yoga, index)
        layer.insertSublayer(child.layer, at: UInt32(index))
        invalidate()
    }

    public func removeFromParent() {
        guard let parent, let index = parent.children.firstIndex(where: { $0 === self }) else { return }
        parent.children.remove(at: index)
        YGNodeRemoveChild(parent.yoga, yoga)
        layer.removeFromSuperlayer()
        self.parent = nil
        parent.invalidate()
        detachNativeViews()
    }

    /// Native views (text fields) live above the layer tree, so they leave with their node explicitly.
    func detachNativeViews() {
        for child in children { child.detachNativeViews() }
    }

    /// Removes the node, playing `exit` first if it has one. The node leaves the layout immediately;
    /// its layer stays where it was until the animation ends.
    public func remove(completion: @escaping @MainActor () -> Void = {}) {
        guard let exit, let parent, layer.superlayer != nil,
              let index = parent.children.firstIndex(where: { $0 === self })
        else {
            removeFromParent()
            return completion()
        }
        parent.children.remove(at: index)
        YGNodeRemoveChild(parent.yoga, yoga)
        self.parent = nil
        parent.invalidate()
        play(exit: exit) { [weak self, layer] in
            layer.removeFromSuperlayer()
            self?.detachNativeViews()
            completion()
        }
    }

    /// This node's frame relative to the top of its tree (surface-local coordinates once mounted).
    public var frameInRoot: CGRect {
        var frame = layoutFrame
        var ancestor = parent
        while let current = ancestor {
            frame.origin.x += current.layoutFrame.minX
            frame.origin.y += current.layoutFrame.minY
            ancestor = current.parent
        }
        return frame
    }

    /// Nodes under `point` (in this node's own coordinates), deepest first. Later siblings are on top.
    public func hitPath(at point: CGPoint) -> [Node] {
        guard layer.opacity > 0, CGRect(origin: .zero, size: layoutFrame.size).contains(point) else { return [] }
        for child in children.reversed() {
            let local = CGPoint(x: point.x - child.layoutFrame.minX, y: point.y - child.layoutFrame.minY)
            let path = child.hitPath(at: local)
            if !path.isEmpty { return path + [self] }
        }
        return [self]
    }

    public var rootOwner: RenderRoot? {
        var top = self
        while let parent = top.parent { top = parent }
        return top.owner
    }

    func invalidate() {
        var top = self
        while let parent = top.parent { top = parent }
        top.owner?.setNeedsLayout()
    }

    func contentsScaleDidChange() {}

    func applyFrames() {
        if YGNodeGetHasNewLayout(yoga) {
            let previous = hasLaidOut ? layoutFrame : nil
            layoutFrame = CGRect(
                x: CGFloat(YGNodeLayoutGetLeft(yoga)),
                y: CGFloat(YGNodeLayoutGetTop(yoga)),
                width: CGFloat(YGNodeLayoutGetWidth(yoga)),
                height: CGFloat(YGNodeLayoutGetHeight(yoga))
            )
            YGNodeSetHasNewLayout(yoga, false)
            updateGeometry(animatingFrom: previous)
            if !hasLaidOut {
                hasLaidOut = true
                if let enter { play(enter: enter) }
            }
        }
        for child in children { child.applyFrames() }
    }

    /// Bounds and position rather than `frame`, which is undefined once the layer has a transform.
    private func updateGeometry(animatingFrom previous: CGRect?) {
        let oldBounds = layer.presentation()?.bounds ?? layer.bounds
        let oldPosition = layer.presentation()?.position ?? layer.position
        layer.anchorPoint = CGPoint(x: style.originX, y: style.originY)
        layer.bounds = CGRect(origin: .zero, size: layoutFrame.size)
        layer.position = CGPoint(
            x: layoutFrame.minX + layoutFrame.width * style.originX,
            y: layoutFrame.minY + layoutFrame.height * style.originY
        )
        guard let timing = transitions["layout"], let previous, previous != layoutFrame else { return }
        for (keyPath, from, to) in [
            ("position", NSValue(point: oldPosition), NSValue(point: layer.position)),
            ("bounds", NSValue(rect: oldBounds), NSValue(rect: layer.bounds)),
        ] {
            let animation = timing.basic(keyPath)
            animation.fromValue = from
            animation.toValue = to
            layer.add(animation, forKey: "layout.\(keyPath)")
        }
    }

    private func applyPaint(from old: Style?) {
        layer.backgroundColor = style.background
        layer.borderColor = style.borderColor
        layer.borderWidth = style.borderWidth
        layer.cornerRadius = style.radius
        layer.cornerCurve = .continuous
        layer.opacity = style.opacity
        layer.transform = style.transform
        if let old, old.originX != style.originX || old.originY != style.originY { updateGeometry(animatingFrom: nil) }

        guard let old, !transitions.isEmpty else { return }
        for property in AnimatedProperty.allCases {
            guard let timing = transitions[property.rawValue] ?? transitions["all"] else { continue }
            let from = property.value(in: old)
            let to = property.value(in: style)
            guard from != to else { continue }
            let animation = timing.basic(property.keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: property.keyPath) ?? from.layerValue(for: property)
            animation.toValue = to.layerValue(for: property)
            layer.add(animation, forKey: property.rawValue)
        }
    }

    /// Animates from `enter.values` to the current style.
    public func play(enter: Transition) {
        for (property, from) in enter.values {
            let animation = enter.timing.basic(property.keyPath)
            animation.fromValue = from.layerValue(for: property)
            animation.toValue = property.value(in: style).layerValue(for: property)
            layer.add(animation, forKey: "enter.\(property.rawValue)")
        }
        mirror(enter.values, timing: enter.timing, entering: true)
    }

    /// Animates from the current presentation to `exit.values` and holds there until `completion`.
    public func play(exit: Transition, completion: @escaping @MainActor () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        for (property, to) in exit.values {
            let animation = exit.timing.basic(property.keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: property.keyPath)
                ?? property.value(in: style).layerValue(for: property)
            animation.toValue = to.layerValue(for: property)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "exit.\(property.rawValue)")
        }
        mirror(exit.values, timing: exit.timing, entering: false)
        CATransaction.commit()
    }

    /// Drops held exit frames so the layer shows its style again (e.g. a surface shown after hiding).
    public func clearExit() {
        for property in AnimatedProperty.allCases { layer.removeAnimation(forKey: "exit.\(property.rawValue)") }
        for input in inputsInSubtree() { input.clearMirroredExit() }
    }

    private func inputsInSubtree() -> [Input] {
        ((self as? Input).map { [$0] } ?? []) + children.flatMap { $0.inputsInSubtree() }
    }

    /// Text fields sit above the layer tree, so they don't inherit this node's enter/exit. Give each one the same
    /// opacity and translation, and scale it around this node's pivot instead of its own corner: CA applies
    /// `p' = anchor + t + s·(p − anchor)`, so pivoting around P needs an extra `t = (1 − s)·(P − anchor)`.
    /// That term is linear in `s`, so with the same timing (springs included) the field tracks the node exactly.
    private func mirror(_ values: [AnimatedProperty: AnimatedValue], timing: Timing, entering: Bool) {
        let inputs = inputsInSubtree()
        guard !inputs.isEmpty else { return }
        func number(_ property: AnimatedProperty, _ fallback: CGFloat) -> CGFloat {
            if case .number(let value)? = values[property] { return value }
            return fallback
        }
        let rest = (s: style.scale, tx: style.translateX, ty: style.translateY, o: CGFloat(style.opacity))
        let moved = (s: number(.scale, rest.s), tx: number(.translateX, rest.tx), ty: number(.translateY, rest.ty), o: number(.opacity, rest.o))
        let (from, to) = entering ? (moved, rest) : (rest, moved)
        let frame = frameInRoot
        let pivot = CGPoint(x: frame.minX + frame.width * style.originX, y: frame.minY + frame.height * style.originY)
        let scales = values[.scale] != nil

        for input in inputs {
            guard input.field.superview != nil, let fieldLayer = input.field.layer else { continue }
            let field = input.field.frame
            let anchor = CGPoint(x: field.minX + field.width * fieldLayer.anchorPoint.x, y: field.minY + field.height * fieldLayer.anchorPoint.y)
            var tracks: [(String, CGFloat, CGFloat)] = []
            if values[.opacity] != nil { tracks.append(("opacity", from.o, to.o)) }
            if scales { tracks.append(("transform.scale", from.s, to.s)) }
            if scales || values[.translateX] != nil {
                tracks.append(("transform.translation.x", from.tx + (1 - from.s) * (pivot.x - anchor.x), to.tx + (1 - to.s) * (pivot.x - anchor.x)))
            }
            if scales || values[.translateY] != nil {
                tracks.append(("transform.translation.y", from.ty + (1 - from.s) * (pivot.y - anchor.y), to.ty + (1 - to.s) * (pivot.y - anchor.y)))
            }
            for (keyPath, start, end) in tracks {
                let animation = timing.basic(keyPath)
                animation.fromValue = start
                animation.toValue = end
                if !entering {
                    animation.fillMode = .forwards
                    animation.isRemovedOnCompletion = false
                }
                fieldLayer.add(animation, forKey: "\(entering ? Input.mirroredEnter : Input.mirroredExit).\(keyPath)")
            }
        }
    }

    /// Plays keyframes on top of the style; returns a key for `cancelAnimation`.
    @discardableResult
    public func animate(_ keyframes: Keyframes, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> String {
        let key = "keyframes.\(UUID().uuidString)"
        let group = keyframes.animation()
        group.delegate = AnimationCompletion(completion)
        layer.add(group, forKey: key)
        return key
    }

    public func cancelAnimation(_ key: String) {
        layer.removeAnimation(forKey: key)
    }

    /// Yoga only marks the node dirty for values that actually changed.
    private func applyLayout() {
        YGNodeStyleSetFlexDirection(yoga, style.flexDirection == .row ? .row : .column)
        YGNodeStyleSetJustifyContent(yoga, style.justify.yoga)
        YGNodeStyleSetAlignItems(yoga, style.align.yoga)
        YGNodeStyleSetPadding(yoga, .top, Float(style.padding.top))
        YGNodeStyleSetPadding(yoga, .right, Float(style.padding.right))
        YGNodeStyleSetPadding(yoga, .bottom, Float(style.padding.bottom))
        YGNodeStyleSetPadding(yoga, .left, Float(style.padding.left))
        YGNodeStyleSetGap(yoga, .all, Float(style.gap))
        YGNodeStyleSetFlexGrow(yoga, Float(style.grow))
        YGNodeStyleSetFlexShrink(yoga, Float(style.shrink))

        switch style.width {
        case .auto: YGNodeStyleSetWidthAuto(yoga)
        case .points(let value): YGNodeStyleSetWidth(yoga, Float(value))
        case .percent(let value): YGNodeStyleSetWidthPercent(yoga, Float(value))
        }
        switch style.height {
        case .auto: YGNodeStyleSetHeightAuto(yoga)
        case .points(let value): YGNodeStyleSetHeight(yoga, Float(value))
        case .percent(let value): YGNodeStyleSetHeightPercent(yoga, Float(value))
        }
    }
}

@MainActor
public final class Box: Node {
    public init(style: Style = Style(), children: [Node] = []) {
        super.init(layer: CALayer(), style: style)
        for child in children { append(child) }
    }
}

/// Property changes apply instantly; animation will only ever be explicit.
private final class NoImplicitActions: NSObject, CALayerDelegate {
    nonisolated(unsafe) static let shared = NoImplicitActions()

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        NSNull()
    }
}

private extension Justify {
    var yoga: YGJustify {
        switch self {
        case .start: .flexStart
        case .center: .center
        case .end: .flexEnd
        case .spaceBetween: .spaceBetween
        case .spaceAround: .spaceAround
        case .spaceEvenly: .spaceEvenly
        }
    }
}

private extension Align {
    var yoga: YGAlign {
        switch self {
        case .start: .flexStart
        case .center: .center
        case .end: .flexEnd
        case .stretch: .stretch
        }
    }
}

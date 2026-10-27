import AppKit
import yoga

@MainActor
public class Node {
    public let layer: CALayer
    /// With `clip`, children live in this layer instead: it masks them to the node's shape, while `layer` keeps
    /// drawing the background, border and a shadow the mask would cut off.
    private var clipLayer: CALayer?
    private var childHost: CALayer { clipLayer ?? layer }
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
        childHost.insertSublayer(child.layer, at: UInt32(index))
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
    /// Children are hit where they're drawn: their scale, rotation and translation count, and so do parts outside
    /// the parent (an absolutely positioned badge hanging over an icon's corner).
    public func hitPath(at point: CGPoint) -> [Node] {
        guard layer.opacity > 0 else { return [] }
        if style.clip, !outline.contains(point) { return [] }
        for child in children.reversed() {
            let local = child.layer.convert(point, from: layer)
            let path = child.hitPath(at: local)
            if !path.isEmpty { return path + [self] }
        }
        return layer.bounds.contains(point) ? [self] : []
    }

    /// The node's rounded shape in its own coordinates.
    var outline: CGPath {
        let b = layer.bounds
        let r = min(style.radius, b.width / 2, b.height / 2)
        let corners = style.corners
        let radius = { (corner: Corners) in corners.contains(corner) ? r : 0 }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: b.minX + radius(.topLeft), y: b.minY))
        path.addArc(tangent1End: CGPoint(x: b.maxX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.maxY), radius: radius(.topRight))
        path.addArc(tangent1End: CGPoint(x: b.maxX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.maxY), radius: radius(.bottomRight))
        path.addArc(tangent1End: CGPoint(x: b.minX, y: b.maxY), tangent2End: CGPoint(x: b.minX, y: b.minY), radius: radius(.bottomLeft))
        path.addArc(tangent1End: CGPoint(x: b.minX, y: b.minY), tangent2End: CGPoint(x: b.maxX, y: b.minY), radius: radius(.topLeft))
        path.closeSubpath()
        return path
    }

    /// Whether the node draws anything at its frame (empty layout containers don't, so they let clicks through).
    public var paintsContent: Bool {
        style.background != nil || style.borderWidth > 0
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

    /// After layout gave the layer new bounds (shapes refit their path here).
    func boundsDidChange() {}

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
        clipLayer?.bounds = layer.bounds
        let oldShadowPath = layer.presentation()?.shadowPath ?? layer.shadowPath
        updateShadowPath()
        if oldBounds.size != layer.bounds.size { boundsDidChange() }
        guard let timing = transitions["layout"], let previous, previous != layoutFrame else { return }
        mirrorLayout(from: previous, timing: timing)
        for (keyPath, from, to) in [
            ("position", NSValue(point: oldPosition), NSValue(point: layer.position)),
            ("bounds", NSValue(rect: oldBounds), NSValue(rect: layer.bounds)),
        ] {
            let animation = timing.basic(keyPath)
            animation.fromValue = from
            animation.toValue = to
            add(animation, forKey: "layout.\(keyPath)")
        }
        animateShadowPath(from: oldShadowPath, timing: timing, key: "layout.shadowPath")
    }

    private func applyPaint(from old: Style?) {
        layer.backgroundColor = style.background
        layer.borderColor = style.borderColor
        layer.borderWidth = style.borderWidth
        layer.cornerRadius = style.radius
        layer.maskedCorners = style.corners.layerMask
        layer.cornerCurve = .continuous
        updateClip()
        if let shadow = style.shadow {
            layer.shadowColor = shadow.color
            layer.shadowOpacity = 1
            layer.shadowRadius = shadow.blur
            layer.shadowOffset = CGSize(width: shadow.x, height: shadow.y)
        } else {
            layer.shadowOpacity = 0
        }
        let oldShadowPath = layer.presentation()?.shadowPath ?? layer.shadowPath
        updateShadowPath()
        layer.opacity = style.opacity
        layer.transform = style.transform
        if let old, old.originX != style.originX || old.originY != style.originY { updateGeometry(animatingFrom: nil) }

        guard let old, !transitions.isEmpty else { return }
        var curves: [AnimatedProperty: (Double) -> CGFloat] = [:]
        var length = 0.0
        for property in AnimatedProperty.allCases {
            guard let timing = transitions[property.rawValue] ?? transitions["all"] else { continue }
            let from = property.value(in: old)
            let to = property.value(in: style)
            guard from != to else { continue }
            let animation = timing.basic(property.keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: property.keyPath) ?? from.layerValue(for: property)
            animation.toValue = to.layerValue(for: property)
            add(animation, forKey: property.rawValue)
            if property == .radius { animateShadowPath(from: oldShadowPath, timing: timing, key: "radius.shadowPath") }

            if let start = presented(property) ?? number(property, in: old), let end = number(property, in: style) {
                curves[property] = Self.curves([property: (start, end)], timing: timing.delayed())[property]
                length = max(length, timing.delay + timing.length)
            }
        }
        mirror(MirroredAnimation(curves: curves, length: length), key: "mirror.transition")
    }

    /// Animates from `enter.values` to the current style.
    public func play(enter: Transition) {
        var endpoints: [AnimatedProperty: (from: CGFloat, to: CGFloat)] = [:]
        for (property, from) in enter.values {
            let animation = enter.timing.basic(property.keyPath)
            animation.fromValue = from.layerValue(for: property)
            animation.toValue = property.value(in: style).layerValue(for: property)
            add(animation, forKey: "enter.\(property.rawValue)")
            if case .number(let start) = from, let end = number(property, in: style) { endpoints[property] = (start, end) }
        }
        let length = enter.timing.delay + enter.timing.length
        mirror(MirroredAnimation(curves: Self.curves(endpoints, timing: enter.timing.delayed()), length: length), key: "mirror.enter")
    }

    /// Animates from the current presentation to `exit.values` and holds there until `completion`.
    public func play(exit: Transition, completion: @escaping @MainActor () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        var endpoints: [AnimatedProperty: (from: CGFloat, to: CGFloat)] = [:]
        for (property, to) in exit.values {
            let animation = exit.timing.basic(property.keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: property.keyPath)
                ?? property.value(in: style).layerValue(for: property)
            animation.toValue = to.layerValue(for: property)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            add(animation, forKey: "exit.\(property.rawValue)")
            if case .number(let end) = to, let start = presented(property) ?? number(property, in: style) {
                endpoints[property] = (start, end)
            }
        }
        let length = exit.timing.delay + exit.timing.length
        mirror(
            MirroredAnimation(curves: Self.curves(endpoints, timing: exit.timing.delayed()), length: length, holds: true),
            key: "mirror.exit"
        )
        CATransaction.commit()
    }

    /// Drops held exit frames so the layer shows its style again (e.g. a surface shown after hiding).
    public func clearExit() {
        for property in AnimatedProperty.allCases { removeAnimation(forKey: "exit.\(property.rawValue)") }
        removeMirror("mirror.exit")
    }

    /// Plays keyframes on top of the style; returns a key for `cancelAnimation`.
    @discardableResult
    public func animate(_ keyframes: Keyframes, completion: @escaping @MainActor (Bool) -> Void = { _ in }) -> String {
        let key = "keyframes.\(UUID().uuidString)"
        let group = keyframes.animation()
        group.delegate = AnimationCompletion(completion)
        add(group, forKey: key)
        mirror(keyframes.mirrored(), key: "mirror.\(key)")
        return key
    }

    public func cancelAnimation(_ key: String) {
        removeAnimation(forKey: key)
        removeMirror("mirror.\(key)")
    }

    /// The clip layer follows the node's size and corners, animations included.
    private func add(_ animation: CAAnimation, forKey key: String) {
        layer.add(animation, forKey: key)
        if let clipLayer, let shared = animation.sharedWithClip() { clipLayer.add(shared, forKey: key) }
    }

    private func removeAnimation(forKey key: String) {
        layer.removeAnimation(forKey: key)
        clipLayer?.removeAnimation(forKey: key)
    }

    private func updateClip() {
        if style.clip, clipLayer == nil {
            let clip = CALayer()
            clip.delegate = NoImplicitActions.shared
            clip.masksToBounds = true
            clip.anchorPoint = .zero
            clip.position = .zero
            clip.contentsScale = contentsScale
            for child in children { clip.addSublayer(child.layer) }
            layer.addSublayer(clip)
            clipLayer = clip
        } else if !style.clip, let clip = clipLayer {
            for child in children { layer.addSublayer(child.layer) }
            clip.removeFromSuperlayer()
            clipLayer = nil
        }
        clipLayer?.bounds = layer.bounds
        clipLayer?.cornerRadius = style.radius
        clipLayer?.maskedCorners = style.corners.layerMask
        clipLayer?.cornerCurve = .continuous
    }

    /// A shadow path keeps the shadow to the node's shape (its children cast none) and spares Core Animation an
    /// offscreen pass.
    private func updateShadowPath() {
        layer.shadowPath = style.shadow == nil ? nil : outline
    }

    private func animateShadowPath(from old: CGPath?, timing: Timing, key: String) {
        guard let old, let new = layer.shadowPath, old != new else { return }
        let animation = timing.basic("shadowPath")
        animation.fromValue = old
        animation.toValue = new
        layer.add(animation, forKey: key)
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
        YGNodeStyleSetPositionType(yoga, style.position == .absolute ? .absolute : .relative)
        for (edge, length) in [(YGEdge.top, style.top), (.right, style.right), (.bottom, style.bottom), (.left, style.left)] {
            switch length {
            case .auto: YGNodeStyleSetPositionAuto(yoga, edge)
            case .points(let value): YGNodeStyleSetPosition(yoga, edge, Float(value))
            case .percent(let value): YGNodeStyleSetPositionPercent(yoga, edge, Float(value))
            }
        }

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

private extension CAAnimation {
    /// The part of a node animation its clip layer plays too (size and corners), without the completion delegate.
    func sharedWithClip() -> CAAnimation? {
        if let property = self as? CAPropertyAnimation {
            guard ["bounds", "cornerRadius"].contains(property.keyPath) else { return nil }
            let copy = property.copy() as? CAAnimation
            copy?.delegate = nil
            return copy
        }
        guard let group = self as? CAAnimationGroup,
              let shared = group.animations?.compactMap({ $0.sharedWithClip() }), !shared.isEmpty,
              let copy = group.copy() as? CAAnimationGroup
        else { return nil }
        copy.animations = shared
        copy.delegate = nil
        return copy
    }
}

/// Property changes apply instantly; animation will only ever be explicit.
final class NoImplicitActions: NSObject, CALayerDelegate {
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

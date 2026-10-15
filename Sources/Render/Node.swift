import QuartzCore
import yoga

@MainActor
public class Node {
    public let layer: CALayer
    let yoga: YGNodeRef
    public private(set) var children: [Node] = []
    public private(set) weak var parent: Node?
    weak var owner: RenderRoot?

    public var style: Style {
        didSet {
            guard style != oldValue else { return }
            applyPaint()
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
        layer.anchorPoint = .zero
        applyPaint()
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
    }

    /// This node's frame relative to the top of its tree (surface-local coordinates once mounted).
    public var frameInRoot: CGRect {
        var frame = layer.frame
        var ancestor = parent
        while let current = ancestor {
            frame.origin.x += current.layer.frame.minX
            frame.origin.y += current.layer.frame.minY
            ancestor = current.parent
        }
        return frame
    }

    /// Nodes under `point` (in this node's own coordinates), deepest first. Later siblings are on top.
    public func hitPath(at point: CGPoint) -> [Node] {
        guard layer.opacity > 0, CGRect(origin: .zero, size: layer.frame.size).contains(point) else { return [] }
        for child in children.reversed() {
            let local = CGPoint(x: point.x - child.layer.frame.minX, y: point.y - child.layer.frame.minY)
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
            layer.frame = CGRect(
                x: CGFloat(YGNodeLayoutGetLeft(yoga)),
                y: CGFloat(YGNodeLayoutGetTop(yoga)),
                width: CGFloat(YGNodeLayoutGetWidth(yoga)),
                height: CGFloat(YGNodeLayoutGetHeight(yoga))
            )
            YGNodeSetHasNewLayout(yoga, false)
        }
        for child in children { child.applyFrames() }
    }

    private func applyPaint() {
        layer.backgroundColor = style.background
        layer.borderColor = style.borderColor
        layer.borderWidth = style.borderWidth
        layer.cornerRadius = style.radius
        layer.cornerCurve = .continuous
        layer.opacity = style.opacity
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

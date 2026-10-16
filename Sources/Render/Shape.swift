import QuartzCore

public enum ShapeFit: Sendable {
    /// Uniform scale, centered (rings, icons).
    case contain
    /// Each axis fills the node (graphs).
    case stretch
}

/// An SVG path fitted into the node's bounds. The path is transformed, not the layer, so strokes keep their width in
/// points; with a stroke, the path is inset by half its width so it isn't clipped at the edges.
/// Paint changes animate through the node's `transitions` (keys: fill, stroke, track, strokeWidth, strokeStart,
/// strokeEnd, path; "all" covers them too).
/// The node's own layer draws the fill and the `track` (the whole path, under the stroke); the stroke is a sublayer
/// so it can be partial (`strokeStart`/`strokeEnd`) on top of the track.
@MainActor
public final class Shape: Node {
    private let baseLayer: CAShapeLayer
    private let strokeLayer = CAShapeLayer()
    private var source: CGPath = CGMutablePath()

    public var path = "" {
        didSet {
            guard path != oldValue else { return }
            source = PathData.parse(path)
            updatePath(animated: true)
        }
    }

    /// The coordinate space `path` is written in.
    public var viewBox = CGSize(width: 100, height: 100) {
        didSet { if viewBox != oldValue { updatePath(animated: false) } }
    }

    public var fit = ShapeFit.contain {
        didSet { if fit != oldValue { updatePath(animated: false) } }
    }

    public var fill: CGColor? = .white {
        didSet { set("fill", baseLayer, "fillColor", from: oldValue, to: fill) { $0.fillColor = self.fill } }
    }

    public var stroke: CGColor? {
        didSet {
            set("stroke", strokeLayer, "strokeColor", from: oldValue, to: stroke) { $0.strokeColor = self.stroke }
            if (oldValue == nil) != (stroke == nil) { updatePath(animated: false) }
        }
    }

    /// The whole path stroked under `stroke`: the empty part of a progress ring or bar.
    public var track: CGColor? {
        didSet {
            set("track", baseLayer, "strokeColor", from: oldValue, to: track) { $0.strokeColor = self.track }
            if (oldValue == nil) != (track == nil) { updatePath(animated: false) }
        }
    }

    public var strokeWidth: CGFloat = 1 {
        didSet {
            set("strokeWidth", strokeLayer, "lineWidth", from: oldValue, to: strokeWidth) { $0.lineWidth = self.strokeWidth }
            set("strokeWidth", baseLayer, "lineWidth", from: oldValue, to: strokeWidth) { $0.lineWidth = self.strokeWidth }
            updatePath(animated: true)
        }
    }

    /// The drawn part of the stroke, as fractions of its length (0–1). `strokeEnd` makes progress rings.
    public var strokeStart: CGFloat = 0 {
        didSet {
            set("strokeStart", strokeLayer, "strokeStart", from: oldValue, to: strokeStart) { $0.strokeStart = self.strokeStart }
        }
    }

    public var strokeEnd: CGFloat = 1 {
        didSet { set("strokeEnd", strokeLayer, "strokeEnd", from: oldValue, to: strokeEnd) { $0.strokeEnd = self.strokeEnd } }
    }

    public var lineCap: CAShapeLayerLineCap = .butt {
        didSet { strokeLayer.lineCap = lineCap }
    }

    public var lineJoin: CAShapeLayerLineJoin = .miter {
        didSet {
            strokeLayer.lineJoin = lineJoin
            baseLayer.lineJoin = lineJoin
        }
    }

    public init(style: Style = Style()) {
        baseLayer = CAShapeLayer()
        baseLayer.fillColor = fill
        baseLayer.strokeColor = nil
        baseLayer.lineWidth = strokeWidth
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = nil
        strokeLayer.lineWidth = strokeWidth
        strokeLayer.delegate = NoImplicitActions.shared
        super.init(layer: baseLayer, style: style)
        baseLayer.addSublayer(strokeLayer)
    }

    public override var paintsContent: Bool { !source.isEmpty || super.paintsContent }

    override func boundsDidChange() {
        strokeLayer.frame = layer.bounds
        updatePath(animated: false)
    }

    /// `path` mapped into `size` (the node's bounds) per `viewBox`, `fit` and the stroke inset.
    public static func transform(viewBox: CGSize, into size: CGSize, fit: ShapeFit, inset: CGFloat) -> CGAffineTransform {
        let area = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        guard viewBox.width > 0, viewBox.height > 0, area.width > 0, area.height > 0 else { return .identity }
        var sx = area.width / viewBox.width
        var sy = area.height / viewBox.height
        if fit == .contain {
            sx = min(sx, sy)
            sy = sx
        }
        let x = area.minX + (area.width - viewBox.width * sx) / 2
        let y = area.minY + (area.height - viewBox.height * sy) / 2
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: sx, y: sy)
    }

    private func updatePath(animated: Bool) {
        let stroked = stroke != nil || track != nil
        var transform = Self.transform(viewBox: viewBox, into: layer.bounds.size, fit: fit, inset: stroked ? strokeWidth / 2 : 0)
        let fitted = source.copy(using: &transform) ?? source
        for target in [baseLayer, strokeLayer] {
            let old = target.presentation()?.path ?? target.path
            target.path = fitted
            guard animated, let timing = transitions["path"] ?? transitions["all"], let old else { continue }
            let animation = timing.basic("path")
            animation.fromValue = old
            animation.toValue = fitted
            target.add(animation, forKey: "path")
        }
    }

    private func set<Value: Equatable>(
        _ key: String, _ target: CAShapeLayer, _ keyPath: String, from old: Value, to new: Value, apply: (CAShapeLayer) -> Void
    ) {
        guard old != new else { return }
        let from = target.presentation()?.value(forKeyPath: keyPath) ?? target.value(forKeyPath: keyPath)
        apply(target)
        guard let timing = transitions[key] ?? transitions["all"] else { return }
        let animation = timing.basic(keyPath)
        animation.fromValue = from
        animation.toValue = target.value(forKeyPath: keyPath)
        target.add(animation, forKey: key)
    }
}

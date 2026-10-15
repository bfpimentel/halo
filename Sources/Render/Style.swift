import QuartzCore

public enum FlexDirection: Hashable, Sendable {
    case row, column
}

public enum Justify: Hashable, Sendable {
    case start, center, end, spaceBetween, spaceAround, spaceEvenly
}

public enum Align: Hashable, Sendable {
    case start, center, end, stretch
}

public enum Length: Hashable, Sendable {
    case auto
    case points(CGFloat)
    case percent(CGFloat)
}

public struct Spacing: Hashable, Sendable {
    public var top: CGFloat
    public var right: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat

    public init(top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(_ all: CGFloat) {
        self.init(top: all, right: all, bottom: all, left: all)
    }

    public init(vertical: CGFloat, horizontal: CGFloat) {
        self.init(top: vertical, right: horizontal, bottom: vertical, left: horizontal)
    }

    public static let zero = Spacing()
}

/// Layout fields go to Yoga; paint fields go straight to the layer and never trigger layout.
public struct Style: Equatable {
    public var flexDirection: FlexDirection
    public var justify: Justify
    public var align: Align
    public var padding: Spacing
    public var gap: CGFloat
    public var width: Length
    public var height: Length
    public var grow: CGFloat
    public var shrink: CGFloat

    public var background: CGColor?
    public var borderColor: CGColor?
    public var borderWidth: CGFloat
    public var radius: CGFloat
    public var opacity: Float
    public var scale: CGFloat
    /// Degrees, clockwise.
    public var rotate: CGFloat
    public var translateX: CGFloat
    public var translateY: CGFloat
    /// The point transforms pivot around, as fractions of the node's size (0.5, 0.5 is the center).
    public var originX: CGFloat
    public var originY: CGFloat

    public init(
        flexDirection: FlexDirection = .column,
        justify: Justify = .start,
        align: Align = .stretch,
        padding: Spacing = .zero,
        gap: CGFloat = 0,
        width: Length = .auto,
        height: Length = .auto,
        grow: CGFloat = 0,
        shrink: CGFloat = 0,
        background: CGColor? = nil,
        borderColor: CGColor? = nil,
        borderWidth: CGFloat = 0,
        radius: CGFloat = 0,
        opacity: Float = 1,
        scale: CGFloat = 1,
        rotate: CGFloat = 0,
        translateX: CGFloat = 0,
        translateY: CGFloat = 0,
        originX: CGFloat = 0.5,
        originY: CGFloat = 0.5
    ) {
        self.flexDirection = flexDirection
        self.justify = justify
        self.align = align
        self.padding = padding
        self.gap = gap
        self.width = width
        self.height = height
        self.grow = grow
        self.shrink = shrink
        self.background = background
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.radius = radius
        self.opacity = opacity
        self.scale = scale
        self.rotate = rotate
        self.translateX = translateX
        self.translateY = translateY
        self.originX = originX
        self.originY = originY
    }

    var transform: CATransform3D {
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(rotate * .pi / 180, 0, 0, 1))
        return CATransform3DConcat(transform, CATransform3DMakeTranslation(translateX, translateY, 0))
    }
}

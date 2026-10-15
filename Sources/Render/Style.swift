import CoreGraphics

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
        opacity: Float = 1
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
    }
}

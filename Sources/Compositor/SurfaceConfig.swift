import CoreGraphics

public typealias ScreenID = CGDirectDisplayID

public struct Edges: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let top = Edges(rawValue: 1 << 0)
    public static let bottom = Edges(rawValue: 1 << 1)
    public static let left = Edges(rawValue: 1 << 2)
    public static let right = Edges(rawValue: 1 << 3)
}

public struct Insets: Sendable, Hashable {
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

    public static let zero = Insets()
}

public enum Dimension: Sendable, Hashable {
    case fixed(CGFloat)
    case fill
}

/// `nil` means fill when the surface is anchored to both edges of that axis, and zero (content-sized) otherwise.
public struct SurfaceSize: Sendable, Hashable {
    public var width: Dimension?
    public var height: Dimension?

    public init(width: Dimension? = nil, height: Dimension? = nil) {
        self.width = width
        self.height = height
    }
}

public enum SurfaceLayer: Sendable, Hashable {
    case desktop, belowMenu, aboveMenu, overlay
}

public enum InputPolicy: Sendable, Hashable {
    case passthrough, hover, interactive
}

public struct Avoid: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let notch = Avoid(rawValue: 1 << 0)
    public static let menuBar = Avoid(rawValue: 1 << 1)
}

public struct SurfaceConfig: Sendable, Hashable {
    public var screen: ScreenID
    public var anchor: Edges
    public var margins: Insets
    public var size: SurfaceSize
    public var layer: SurfaceLayer
    public var input: InputPolicy
    public var avoid: Avoid
    public var visible: Bool

    public init(
        screen: ScreenID,
        anchor: Edges = [],
        margins: Insets = .zero,
        size: SurfaceSize = SurfaceSize(),
        layer: SurfaceLayer = .belowMenu,
        input: InputPolicy = .passthrough,
        avoid: Avoid = [],
        visible: Bool = true
    ) {
        self.screen = screen
        self.anchor = anchor
        self.margins = margins
        self.size = size
        self.layer = layer
        self.input = input
        self.avoid = avoid
        self.visible = visible
    }
}

/// A display, in top-left global coordinates.
public struct ScreenInfo: Sendable, Hashable {
    public var id: ScreenID
    public var name: String
    public var frame: CGRect
    /// Height reserved by the menu bar at the top of this screen; 0 when it auto-hides.
    public var menuBarHeight: CGFloat
    public var notch: CGRect?
    public var scale: CGFloat

    public init(id: ScreenID, name: String, frame: CGRect, menuBarHeight: CGFloat = 0, notch: CGRect? = nil, scale: CGFloat = 1) {
        self.id = id
        self.name = name
        self.frame = frame
        self.menuBarHeight = menuBarHeight
        self.notch = notch
        self.scale = scale
    }
}

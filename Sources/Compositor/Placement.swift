import CoreGraphics

public enum Placement {
    /// Returns the surface frame in top-left global coordinates.
    ///
    /// Avoiding the notch shrinks a surface anchored to one horizontal side so it ends at the notch,
    /// and moves any other overlapping surface below it.
    public static func frame(for config: SurfaceConfig, on screen: ScreenInfo) -> CGRect {
        var area = screen.frame
        if config.avoid.contains(.menuBar), screen.menuBarHeight > 0 {
            area.origin.y += screen.menuBarHeight
            area.size.height -= screen.menuBarHeight
        }

        let (x, width) = axis(
            start: area.minX, length: area.width,
            marginStart: config.margins.left, marginEnd: config.margins.right,
            anchoredStart: config.anchor.contains(.left), anchoredEnd: config.anchor.contains(.right),
            dimension: config.size.width
        )
        let (y, height) = axis(
            start: area.minY, length: area.height,
            marginStart: config.margins.top, marginEnd: config.margins.bottom,
            anchoredStart: config.anchor.contains(.top), anchoredEnd: config.anchor.contains(.bottom),
            dimension: config.size.height
        )
        let rect = CGRect(x: x, y: y, width: width, height: height)

        guard config.avoid.contains(.notch), let notch = screen.notch, rect.intersects(notch) else {
            return rect
        }
        return avoiding(notch: notch, rect: rect, anchor: config.anchor)
    }

    public enum Side: Sendable, Hashable {
        case above, below, left, right
    }

    public enum Alignment: Sendable, Hashable {
        case start, center, end
    }

    /// A popup of `size` next to `anchor` (both top-left global). Flips to the opposite side when the preferred one
    /// doesn't fit inside `bounds` and the other does, then slides along the edge to stay inside `bounds`.
    public static func frame(
        size: CGSize, attachedTo anchor: CGRect, side: Side, align: Alignment, offset: CGFloat, within bounds: CGRect
    ) -> CGRect {
        let vertical = side == .above || side == .below
        func origin(on side: Side) -> CGFloat {
            switch side {
            case .below: anchor.maxY + offset
            case .above: anchor.minY - offset - size.height
            case .right: anchor.maxX + offset
            case .left: anchor.minX - offset - size.width
            }
        }
        func fits(_ value: CGFloat) -> Bool {
            vertical
                ? value >= bounds.minY && value + size.height <= bounds.maxY
                : value >= bounds.minX && value + size.width <= bounds.maxX
        }
        let opposite: Side = switch side {
        case .above: .below
        case .below: .above
        case .left: .right
        case .right: .left
        }
        var main = origin(on: side)
        if !fits(main), fits(origin(on: opposite)) { main = origin(on: opposite) }

        let length = vertical ? size.width : size.height
        let (start, extent) = vertical ? (anchor.minX, anchor.width) : (anchor.minY, anchor.height)
        var cross: CGFloat = switch align {
        case .start: start
        case .center: start + (extent - length) / 2
        case .end: start + extent - length
        }
        let (low, high) = vertical ? (bounds.minX, bounds.maxX) : (bounds.minY, bounds.maxY)
        cross = max(low, min(cross, high - length))

        return vertical
            ? CGRect(x: cross, y: main, width: size.width, height: size.height)
            : CGRect(x: main, y: cross, width: size.width, height: size.height)
    }

    private static func axis(
        start: CGFloat, length: CGFloat,
        marginStart: CGFloat, marginEnd: CGFloat,
        anchoredStart: Bool, anchoredEnd: Bool,
        dimension: Dimension?
    ) -> (origin: CGFloat, size: CGFloat) {
        let available = max(0, length - marginStart - marginEnd)
        let size: CGFloat = switch dimension {
        case .fixed(let value): min(value, available)
        case .fill: available
        case .auto: 0
        case nil: anchoredStart && anchoredEnd ? available : 0
        }

        let origin: CGFloat = switch (anchoredStart, anchoredEnd) {
        case (true, false): start + marginStart
        case (false, true): start + length - marginEnd - size
        default: start + marginStart + (available - size) / 2
        }
        return (origin, size)
    }

    private static func avoiding(notch: CGRect, rect: CGRect, anchor: Edges) -> CGRect {
        var result = rect
        switch (anchor.contains(.left), anchor.contains(.right)) {
        case (true, false) where rect.minX < notch.minX:
            result.size.width = notch.minX - rect.minX
        case (false, true) where rect.maxX > notch.maxX:
            result.size.width = rect.maxX - notch.maxX
            result.origin.x = notch.maxX
        default:
            result.origin.y = notch.maxY
        }
        return result
    }
}

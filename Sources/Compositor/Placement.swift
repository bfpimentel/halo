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

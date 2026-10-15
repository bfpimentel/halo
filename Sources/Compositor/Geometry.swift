import CoreGraphics

/// The only place where AppKit's bottom-left global space meets halo's top-left global space.
/// Everything outside this file uses top-left coordinates.
public enum Geometry {
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitToTopLeft(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipped(rect, primaryHeight: primaryHeight)
    }

    public static func topLeftToAppKit(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flipped(rect, primaryHeight: primaryHeight)
    }
}

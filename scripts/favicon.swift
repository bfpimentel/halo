// Renders the PNG fallbacks of docs/assets/favicon.svg (browsers that skip SVG icons): favicon.png and
// apple-touch-icon.png. Usage: swift scripts/favicon.swift
import AppKit

func render(_ size: Int, to path: String) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.current = context
    let side = CGFloat(size)
    NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), xRadius: side * 15 / 64, yRadius: side * 15 / 64).fill()
    let text = NSAttributedString(string: "h", attributes: [
        .font: NSFont.systemFont(ofSize: side * 50 / 64, weight: .bold), .foregroundColor: NSColor.white,
    ])
    let bounds = text.boundingRect(with: CGSize(width: side, height: side), options: .usesLineFragmentOrigin)
    // The SVG puts the baseline 49/64 down; AppKit measures from the bottom.
    let font = NSFont.systemFont(ofSize: side * 50 / 64, weight: .bold)
    text.draw(at: CGPoint(x: (side - bounds.width) / 2, y: side - side * 49 / 64 + font.descender))
    NSGraphicsContext.current = nil
    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

try render(32, to: "docs/assets/favicon.png")
try render(180, to: "docs/assets/apple-touch-icon.png")

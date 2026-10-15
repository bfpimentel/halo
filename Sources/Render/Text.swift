import AppKit
import yoga

public struct Font: Hashable, Sendable {
    public var family: String?
    public var size: CGFloat
    public var weight: NSFont.Weight

    public init(family: String? = nil, size: CGFloat = 13, weight: NSFont.Weight = .regular) {
        self.family = family
        self.size = size
        self.weight = weight
    }

    var nsFont: NSFont {
        guard let family else { return .systemFont(ofSize: size, weight: weight) }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

/// Single-line text, truncated at the end when its box is narrower than the string.
@MainActor
public final class Text: Node {
    private let textLayer: CATextLayer

    public var text: String {
        didSet { if text != oldValue { contentDidChange() } }
    }

    public var font: Font {
        didSet { if font != oldValue { contentDidChange() } }
    }

    public var color: CGColor {
        didSet { textLayer.foregroundColor = color }
    }

    public init(_ text: String, font: Font = Font(), color: CGColor = .white, style: Style = Style()) {
        self.text = text
        self.font = font
        self.color = color
        textLayer = CATextLayer()
        textLayer.isWrapped = false
        textLayer.truncationMode = .end
        textLayer.foregroundColor = color
        super.init(layer: textLayer, style: style)
        applyContent()
        YGNodeSetContext(yoga, Unmanaged.passUnretained(self).toOpaque())
        YGNodeSetMeasureFunc(yoga, measureText)
    }

    override func contentsScaleDidChange() {
        textLayer.setNeedsDisplay()
    }

    private func contentDidChange() {
        applyContent()
        YGNodeMarkDirty(yoga)
        invalidate()
    }

    private func applyContent() {
        let nsFont = font.nsFont
        textLayer.font = nsFont
        textLayer.fontSize = nsFont.pointSize
        textLayer.string = text
    }

    fileprivate func naturalSize() -> CGSize {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font.nsFont]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return CGSize(width: ceil(width), height: ceil(ascent + descent + leading))
    }
}

private let measureText: YGMeasureFunc = { node, width, widthMode, _, _ in
    guard let node, let context = YGNodeGetContext(node) else { return YGSize(width: 0, height: 0) }
    nonisolated(unsafe) let text = context
    return MainActor.assumeIsolated {
        let size = Unmanaged<Text>.fromOpaque(text).takeUnretainedValue().naturalSize()
        let measuredWidth = widthMode == .undefined ? size.width : min(size.width, CGFloat(width))
        return YGSize(width: Float(measuredWidth), height: Float(size.height))
    }
}

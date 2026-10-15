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

public enum TextAlignment: Sendable {
    case left, center, right
}

/// Text truncated at the end when it doesn't fit. One line by default; `maxLines` > 1 (or 0 for no limit) wraps.
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

    public var maxLines = 1 {
        didSet {
            guard maxLines != oldValue else { return }
            textLayer.isWrapped = maxLines != 1
            contentDidChange()
        }
    }

    public var alignment = TextAlignment.left {
        didSet {
            textLayer.alignmentMode = switch alignment {
            case .left: .left
            case .center: .center
            case .right: .right
            }
        }
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

    public override var paintsContent: Bool { true }

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

    /// The text's size when laid out within `width` (nil = unbounded), wrapping only if `maxLines` allows.
    fileprivate func size(fitting width: CGFloat?) -> CGSize {
        let attributed = NSAttributedString(string: text, attributes: [.font: font.nsFont])
        guard maxLines != 1 else { return Self.measure(CTLineCreateWithAttributedString(attributed)) }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let bounds = CGRect(x: 0, y: 0, width: width ?? 10_000_000, height: 10_000_000)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: bounds, transform: nil), nil)
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        let shown = maxLines == 0 ? lines : Array(lines.prefix(maxLines))
        return shown.map(Self.measure).reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: $0.height + $1.height) }
    }

    private static func measure(_ line: CTLine) -> CGSize {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading) - CTLineGetTrailingWhitespaceWidth(line)
        return CGSize(width: ceil(width), height: ceil(ascent + descent + leading))
    }
}

private let measureText: YGMeasureFunc = { node, width, widthMode, _, _ in
    guard let node, let context = YGNodeGetContext(node) else { return YGSize(width: 0, height: 0) }
    nonisolated(unsafe) let text = context
    return MainActor.assumeIsolated {
        let size = Unmanaged<Text>.fromOpaque(text).takeUnretainedValue().size(fitting: widthMode == .undefined ? nil : CGFloat(width))
        let measuredWidth = widthMode == .undefined ? size.width : min(size.width, CGFloat(width))
        return YGSize(width: Float(measuredWidth), height: Float(size.height))
    }
}

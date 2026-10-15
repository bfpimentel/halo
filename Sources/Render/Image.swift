import AppKit

public enum ImageSource: Hashable, Sendable {
    case file(String)
    case symbol(String)
    case appIcon(bundleID: String)
}

/// A square of `size` points unless the style sets width/height. `color` tints SF Symbols only.
@MainActor
public final class Image: Node {
    public var source: ImageSource? {
        didSet { if source != oldValue { reload() } }
    }

    public var color: CGColor? {
        didSet { if color != oldValue { reload() } }
    }

    public var size: CGFloat {
        didSet {
            guard size != oldValue else { return }
            style.width = .points(size)
            style.height = .points(size)
            reload()
        }
    }

    public init(_ source: ImageSource? = nil, size: CGFloat = 16, color: CGColor? = nil, style: Style = Style()) {
        self.source = source
        self.color = color
        self.size = size
        var style = style
        if style.width == .auto { style.width = .points(size) }
        if style.height == .auto { style.height = .points(size) }
        super.init(layer: CALayer(), style: style)
        layer.contentsGravity = .resizeAspect
        reload()
    }

    override func contentsScaleDidChange() {
        reload()
    }

    public override var paintsContent: Bool { source != nil || super.paintsContent }

    private func reload() {
        layer.contents = load()?.layerContents(forContentsScale: contentsScale)
    }

    private func load() -> NSImage? {
        switch source {
        case nil:
            return nil
        case .file(let path):
            return NSImage(contentsOfFile: (path as NSString).expandingTildeInPath)
        case .appIcon(let app) where app.hasPrefix("/"):
            return NSWorkspace.shared.icon(forFile: app)
        case .appIcon(let bundleID):
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        case .symbol(let name):
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            else { return nil }
            guard let color, let tint = NSColor(cgColor: color) else { return symbol }
            return NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                tint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
    }
}

import AppKit
import yoga

/// A single-line text field. Editing, IME, selection and clipboard come from a real `NSTextField`
/// mounted over the node's frame on every layout pass.
@MainActor
public final class Input: Node {
    public let field = NSTextField()
    private let delegate = FieldDelegate()

    public var onChange: ((String) -> Void)?
    public var onSubmit: ((String) -> Void)?
    /// Gets "Enter", "Escape", "ArrowUp", "ArrowDown" and "Tab"; returning true stops the default behavior.
    public var onKey: ((String) -> Bool)?
    public var autofocus = false

    public var value: String {
        get { field.stringValue }
        set { if field.stringValue != newValue { field.stringValue = newValue } }
    }

    public var placeholder = "" {
        didSet { applyPlaceholder() }
    }

    public var font = Font() {
        didSet {
            guard font != oldValue else { return }
            field.font = font.nsFont
            applyPlaceholder()
            YGNodeMarkDirty(yoga)
            invalidate()
        }
    }

    public var color: CGColor = .white {
        didSet {
            field.textColor = NSColor(cgColor: color)
            applyPlaceholder()
        }
    }

    public init(style: Style = Style()) {
        super.init(layer: CALayer(), style: style)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = font.nsFont
        field.textColor = NSColor(cgColor: color)
        field.delegate = delegate
        delegate.input = self
        YGNodeSetContext(yoga, Unmanaged.passUnretained(self).toOpaque())
        YGNodeSetMeasureFunc(yoga, measureInput)
    }

    public func focus() {
        field.window?.makeFirstResponder(field)
    }

    public override func removeFromParent() {
        super.removeFromParent()
        field.removeFromSuperview()
    }

    override func applyFrames() {
        super.applyFrames()
        guard let root = rootOwner else { return }
        root.attachView?(field)
        let frame = frameInRoot
        let height = lineHeight
        field.frame = CGRect(x: frame.minX, y: frame.minY + (frame.height - height) / 2, width: frame.width, height: height)
    }

    fileprivate var lineHeight: CGFloat {
        let font = self.font.nsFont
        return ceil(font.ascender - font.descender + font.leading) + 2
    }

    private func applyPlaceholder() {
        let muted = (NSColor(cgColor: color) ?? .white).withAlphaComponent(0.45)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: muted, .font: font.nsFont]
        )
    }

    fileprivate func command(_ name: String) -> Bool {
        if onKey?(name) == true { return true }
        guard name == "Enter" else { return false }
        onSubmit?(value)
        return true
    }
}

private final class FieldDelegate: NSObject, NSTextFieldDelegate {
    weak var input: Input?

    private static let commands: [Selector: String] = [
        #selector(NSResponder.insertNewline(_:)): "Enter",
        #selector(NSResponder.cancelOperation(_:)): "Escape",
        #selector(NSResponder.moveUp(_:)): "ArrowUp",
        #selector(NSResponder.moveDown(_:)): "ArrowDown",
        #selector(NSResponder.insertTab(_:)): "Tab",
    ]

    func controlTextDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let input else { return }
            input.onChange?(input.value)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let name = Self.commands[selector] else { return false }
        return MainActor.assumeIsolated { input?.command(name) ?? false }
    }
}

private let measureInput: YGMeasureFunc = { node, width, widthMode, _, _ in
    guard let node, let context = YGNodeGetContext(node) else { return YGSize(width: 0, height: 0) }
    nonisolated(unsafe) let input = context
    return MainActor.assumeIsolated {
        let height = Unmanaged<Input>.fromOpaque(input).takeUnretainedValue().lineHeight
        return YGSize(width: widthMode == .undefined ? 120 : width, height: Float(height))
    }
}

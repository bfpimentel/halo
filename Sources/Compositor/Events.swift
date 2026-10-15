import CoreGraphics

/// `key` uses web-style names for special keys ("Enter", "Escape", "ArrowUp", "Backspace", "Tab", "Space")
/// and the typed character otherwise.
public struct KeyEvent: Equatable, Sendable {
    public var key: String
    public var shift = false
    public var control = false
    public var option = false
    public var command = false
    public var isRepeat = false

    public init(key: String, shift: Bool = false, control: Bool = false, option: Bool = false, command: Bool = false, isRepeat: Bool = false) {
        self.key = key
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
        self.isRepeat = isRepeat
    }
}

/// Points are surface-local, top-left origin.
public enum SurfaceEvent: Sendable {
    case mouseDown(CGPoint, button: Int)
    case mouseUp(CGPoint, button: Int, clickCount: Int)
    case mouseMoved(CGPoint)
    case mouseExited
    case scroll(CGPoint, dx: CGFloat, dy: CGFloat)
    case focusChanged(Bool)
}

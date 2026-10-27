import AppKit

@MainActor
public protocol BackendSurface: AnyObject {
    var rootLayer: CALayer { get }
    var onEvent: ((SurfaceEvent) -> Void)? { get set }
    /// Returns whether the key was handled; unhandled keys go to the system.
    var onKey: ((KeyEvent) -> Bool)? { get set }
    /// File drags over the surface; returns whether a drop would be accepted at that point.
    var onDrag: ((DragEvent) -> Bool)? { get set }
    /// Top-left global coordinates.
    func setFrame(_ frame: CGRect)
    func setLayer(_ layer: SurfaceLayer)
    func setInput(_ input: InputPolicy)
    /// Lets clicks through to whatever is behind (for the empty parts of an interactive surface).
    func setMouseTransparent(_ transparent: Bool)
    func setVisible(_ visible: Bool)
    /// Takes keyboard focus without activating the app. Only `.keyboard` surfaces accept it.
    func focus()
    /// Hosts a native view (e.g. a text field) above the layer tree, in surface-local top-left coordinates.
    func attach(_ view: NSView)
    /// Starts a native drag of `files` from the mouse-down that's in progress (call it on `.mouseDragged`).
    func beginDrag(files: [String])
    /// Whether another window is in front of this surface at `point` (top-left global coordinates).
    func isCovered(at point: CGPoint) -> Bool
    func destroy()
}

extension BackendSurface {
    public var onDrag: ((DragEvent) -> Bool)? {
        get { nil }
        set {}
    }

    public func beginDrag(files: [String]) {}

    public func isCovered(at point: CGPoint) -> Bool { false }
}

@MainActor
public protocol CompositorBackend {
    func makeSurface() -> BackendSurface
    func transaction(_ body: () -> Void)
}

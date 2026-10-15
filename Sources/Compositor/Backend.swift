import AppKit

@MainActor
public protocol BackendSurface: AnyObject {
    var rootLayer: CALayer { get }
    var onEvent: ((SurfaceEvent) -> Void)? { get set }
    /// Returns whether the key was handled; unhandled keys go to the system.
    var onKey: ((KeyEvent) -> Bool)? { get set }
    /// Top-left global coordinates.
    func setFrame(_ frame: CGRect)
    func setLayer(_ layer: SurfaceLayer)
    func setInput(_ input: InputPolicy)
    func setVisible(_ visible: Bool)
    /// Takes keyboard focus without activating the app. Only `.keyboard` surfaces accept it.
    func focus()
    /// Hosts a native view (e.g. a text field) above the layer tree, in surface-local top-left coordinates.
    func attach(_ view: NSView)
    func destroy()
}

@MainActor
public protocol CompositorBackend {
    func makeSurface() -> BackendSurface
    func transaction(_ body: () -> Void)
}

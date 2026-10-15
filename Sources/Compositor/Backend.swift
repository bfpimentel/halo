import QuartzCore

@MainActor
public protocol BackendSurface: AnyObject {
    var rootLayer: CALayer { get }
    /// Top-left global coordinates.
    func setFrame(_ frame: CGRect)
    func setLayer(_ layer: SurfaceLayer)
    func setInput(_ input: InputPolicy)
    func setVisible(_ visible: Bool)
    func destroy()
}

@MainActor
public protocol CompositorBackend {
    func makeSurface() -> BackendSurface
    func transaction(_ body: () -> Void)
}

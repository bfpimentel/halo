import AppKit

@MainActor
public final class Surface {
    public private(set) var config: SurfaceConfig
    public private(set) var frame: CGRect = .zero
    private let backing: BackendSurface

    public var rootLayer: CALayer { backing.rootLayer }

    public var onEvent: ((SurfaceEvent) -> Void)? {
        get { backing.onEvent }
        set { backing.onEvent = newValue }
    }

    public var onKey: ((KeyEvent) -> Bool)? {
        get { backing.onKey }
        set { backing.onKey = newValue }
    }

    public init(config: SurfaceConfig, screen: ScreenInfo, backend: CompositorBackend) {
        self.config = config
        backing = backend.makeSurface()
        backing.setLayer(config.layer)
        backing.setInput(config.input)
        place(on: screen)
        backing.setVisible(config.visible)
    }

    /// `frame` overrides anchor-based placement (used for popups attached to a node).
    public func update(_ newConfig: SurfaceConfig, screen: ScreenInfo, frame explicitFrame: CGRect? = nil) {
        let old = config
        config = newConfig
        if newConfig.layer != old.layer { backing.setLayer(newConfig.layer) }
        if newConfig.input != old.input { backing.setInput(newConfig.input) }
        setFrame(explicitFrame ?? Placement.frame(for: newConfig, on: screen))
        if newConfig.visible != old.visible { backing.setVisible(newConfig.visible) }
    }

    public func place(on screen: ScreenInfo) {
        setFrame(Placement.frame(for: config, on: screen))
    }

    public func setMouseTransparent(_ transparent: Bool) {
        guard config.input != .passthrough else { return }
        backing.setMouseTransparent(transparent)
    }

    public func focus() {
        backing.focus()
    }

    public func attach(_ view: NSView) {
        backing.attach(view)
    }

    public func destroy() {
        backing.destroy()
    }

    private func setFrame(_ newFrame: CGRect) {
        guard newFrame != frame else { return }
        frame = newFrame
        backing.setFrame(newFrame)
    }
}

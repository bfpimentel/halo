import QuartzCore

@MainActor
public final class Surface {
    public private(set) var config: SurfaceConfig
    public private(set) var frame: CGRect = .zero
    private let backing: BackendSurface

    public var rootLayer: CALayer { backing.rootLayer }

    public init(config: SurfaceConfig, screen: ScreenInfo, backend: CompositorBackend) {
        self.config = config
        backing = backend.makeSurface()
        backing.setLayer(config.layer)
        backing.setSpaces(config.spaces)
        backing.setInput(config.input)
        place(on: screen)
        backing.setVisible(config.visible)
    }

    public func update(_ newConfig: SurfaceConfig, screen: ScreenInfo) {
        let old = config
        config = newConfig
        if newConfig.layer != old.layer { backing.setLayer(newConfig.layer) }
        if newConfig.spaces != old.spaces { backing.setSpaces(newConfig.spaces) }
        if newConfig.input != old.input { backing.setInput(newConfig.input) }
        place(on: screen)
        if newConfig.visible != old.visible { backing.setVisible(newConfig.visible) }
    }

    public func place(on screen: ScreenInfo) {
        let newFrame = Placement.frame(for: config, on: screen)
        guard newFrame != frame else { return }
        frame = newFrame
        backing.setFrame(newFrame)
    }

    public func destroy() {
        backing.destroy()
    }
}

import AppKit

@MainActor
public final class PublicBackend: CompositorBackend {
    public init() {}

    public func makeSurface() -> BackendSurface {
        PanelSurface()
    }

    public func transaction(_ body: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }
}

private final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelSurface: BackendSurface {
    private let panel: Panel
    let rootLayer = CALayer()

    init() {
        panel = Panel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let view = NSView()
        view.wantsLayer = true
        view.layer = rootLayer
        rootLayer.isGeometryFlipped = true
        panel.contentView = view
    }

    func setFrame(_ frame: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrame(Geometry.topLeftToAppKit(frame, primaryHeight: primaryHeight), display: false)
    }

    func setLayer(_ layer: SurfaceLayer) {
        panel.level = switch layer {
        case .desktop: NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .belowMenu: NSWindow.Level(Int(CGWindowLevelForKey(.backstopMenu)))
        case .aboveMenu: NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        case .overlay: NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)))
        }
    }

    func setSpaces(_ spaces: SpacePolicy) {
        panel.collectionBehavior = switch spaces {
        case .all: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        case .current: [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        }
    }

    func setInput(_ input: InputPolicy) {
        panel.ignoresMouseEvents = input == .passthrough
        panel.acceptsMouseMovedEvents = input != .passthrough
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func destroy() {
        panel.orderOut(nil)
        panel.close()
    }
}

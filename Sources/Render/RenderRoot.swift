import AppKit
import yoga

/// Attaches a node tree to a host layer and lays it out at most once per run-loop pass.
@MainActor
public final class RenderRoot {
    public let node: Node

    public var size: CGSize {
        didSet { if size != oldValue { setNeedsLayout() } }
    }

    /// Where native views (text fields) get mounted; set by whoever owns the surface.
    public var attachView: ((NSView) -> Void)?

    public var contentsScale: CGFloat {
        get { node.contentsScale }
        set { node.contentsScale = newValue }
    }

    public init(node: Node, hostLayer: CALayer, size: CGSize, contentsScale: CGFloat) {
        self.node = node
        self.size = size
        node.owner = self
        node.contentsScale = contentsScale
        hostLayer.addSublayer(node.layer)
        setNeedsLayout()
    }

    public func detach() {
        node.layer.removeFromSuperlayer()
        node.owner = nil
    }

    func setNeedsLayout() {
        LayoutScheduler.shared.schedule(self)
    }

    public func hitPath(at point: CGPoint) -> [Node] {
        node.hitPath(at: point)
    }

    public func layoutNow() {
        YGNodeCalculateLayout(node.yoga, Float(size.width), Float(size.height), .LTR)
        node.applyFrames()
    }
}

@MainActor
final class LayoutScheduler {
    static let shared = LayoutScheduler()

    private var pending: [ObjectIdentifier: RenderRoot] = [:]
    private var observer: CFRunLoopObserver?

    func schedule(_ root: RenderRoot) {
        pending[ObjectIdentifier(root)] = root
        installObserver()
    }

    private func installObserver() {
        guard observer == nil else { return }
        // Runs just before Core Animation's own commit observer (order 2_000_000).
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 1_999_000) { _, _ in
            MainActor.assumeIsolated { LayoutScheduler.shared.flush() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let roots = pending.values
        pending.removeAll()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for root in roots { root.layoutNow() }
        CATransaction.commit()
    }
}

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
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// AppKit owns the flip state of a view's backing layer; a flipped view is the supported way to get top-left sublayers.
private final class ContentView: NSView, NSDraggingSource {
    weak var surface: PanelSurface?
    private var tracking: NSTrackingArea?
    /// The latest mouse-down or drag event: a drag session has to start from one.
    private(set) var lastMouseEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    private func local(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseEvent = event
        surface?.emit(.mouseDown(local(event), button: 0))
    }

    override func mouseDragged(with event: NSEvent) {
        lastMouseEvent = event
        surface?.emit(.mouseDragged(local(event)))
    }
    override func rightMouseDown(with event: NSEvent) { surface?.emit(.mouseDown(local(event), button: 1)) }
    override func mouseUp(with event: NSEvent) { surface?.emit(.mouseUp(local(event), button: 0, clickCount: event.clickCount)) }
    override func rightMouseUp(with event: NSEvent) { surface?.emit(.mouseUp(local(event), button: 1, clickCount: event.clickCount)) }
    override func mouseMoved(with event: NSEvent) { surface?.emit(.mouseMoved(local(event))) }
    override func mouseEntered(with event: NSEvent) { surface?.emit(.mouseMoved(local(event))) }
    override func mouseExited(with event: NSEvent) { surface?.emit(.mouseExited) }
    override func scrollWheel(with event: NSEvent) {
        surface?.emit(.scroll(local(event), dx: event.scrollingDeltaX, dy: event.scrollingDeltaY))
    }

    override func keyDown(with event: NSEvent) {
        guard surface?.onKey?(KeyEvent(event)) == true else { return super.keyDown(with: event) }
    }

    // MARK: Drop destination (file URLs only; paths are handed over, nothing is read or copied)

    private func files(_ info: NSDraggingInfo) -> [String] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.map(\.path)
    }

    private func over(_ info: NSDraggingInfo) -> NSDragOperation {
        let point = convert(info.draggingLocation, from: nil)
        return surface?.onDrag?(.over(point, files: files(info))) == true ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { over(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { over(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { _ = surface?.onDrag?(.exited) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        return surface?.onDrag?(.drop(point, files: files(sender))) == true
    }

    // MARK: Drag source

    /// Files leave as real file URLs: the receiver (usually Finder) moves or copies them as it would its own.
    func beginDrag(files: [String]) {
        guard let event = lastMouseEvent, !files.isEmpty else { return }
        let start = convert(event.locationInWindow, from: nil)
        let items = files.enumerated().map { index, path in
            let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: path)
            let offset = CGFloat(index) * 6
            item.setDraggingFrame(CGRect(x: start.x - 24 + offset, y: start.y - 24 - offset, width: 48, height: 48), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }
}

@MainActor
final class PanelSurface: BackendSurface {
    private let panel: Panel
    private let view = ContentView()
    private var keyObservers: [NSObjectProtocol] = []
    let rootLayer = CALayer()
    var onEvent: ((SurfaceEvent) -> Void)?
    var onKey: ((KeyEvent) -> Bool)?
    var onDrag: ((DragEvent) -> Bool)?

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
        // One Space only (tiling WMs like AeroSpace keep everything in one): macOS then keeps the panel out of
        // fullscreen Spaces by itself, and `.stationary` holds it in place during Mission Control.
        panel.collectionBehavior = [.stationary, .ignoresCycle]

        view.surface = self
        view.wantsLayer = true
        panel.contentView = view
        rootLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(rootLayer)

        keyObservers = [
            (NSWindow.didBecomeKeyNotification, true),
            (NSWindow.didResignKeyNotification, false),
        ].map { name, focused in
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit(.focusChanged(focused)) }
            }
        }
    }

    isolated deinit {
        for observer in keyObservers { NotificationCenter.default.removeObserver(observer) }
    }

    func emit(_ event: SurfaceEvent) {
        onEvent?(event)
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

    func setInput(_ input: InputPolicy) {
        panel.ignoresMouseEvents = input == .passthrough
        panel.acceptsMouseMovedEvents = input != .passthrough
        panel.acceptsKey = input == .keyboard
        if input != .keyboard, panel.isKeyWindow { panel.resignKey() }
    }

    func setMouseTransparent(_ transparent: Bool) {
        guard panel.ignoresMouseEvents != transparent else { return }
        panel.ignoresMouseEvents = transparent
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func focus() {
        guard panel.acceptsKey, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        if panel.firstResponder == nil || panel.firstResponder === panel { panel.makeFirstResponder(view) }
    }

    func beginDrag(files: [String]) {
        view.beginDrag(files: files)
    }

    func attach(_ view: NSView) {
        guard view.superview !== self.view else { return }
        self.view.addSubview(view)
    }

    func destroy() {
        onEvent = nil
        onKey = nil
        panel.orderOut(nil)
        panel.close()
    }
}

extension KeyEvent {
    public init(_ event: NSEvent) {
        let flags = event.modifierFlags
        self.init(
            key: Self.name(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? ""),
            shift: flags.contains(.shift),
            control: flags.contains(.control),
            option: flags.contains(.option),
            command: flags.contains(.command),
            isRepeat: event.isARepeat
        )
    }

    private static let named: [UInt16: String] = [
        36: "Enter", 76: "Enter", 53: "Escape", 48: "Tab", 49: "Space", 51: "Backspace", 117: "Delete",
        123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
    ]

    static func name(keyCode: UInt16, characters: String) -> String {
        named[keyCode] ?? characters
    }
}

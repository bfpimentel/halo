import AppKit
import Compositor
import JavaScriptCore
import Render

/// Mouse, keyboard and focus events: hit-tested natively, delivered to `__halo.dispatch(id, kind, payload)`.
/// Node handlers bubble from the deepest node under the pointer to the first one listening for that kind.
extension Runtime {
    func listen(_ id: Int, _ kind: String, _ enabled: Bool) {
        var kinds = listeners[id] ?? []
        if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
        listeners[id] = kinds.isEmpty ? nil : kinds
        if kind == "clickOutside" { updateMouseMonitors() }
    }

    func setVisibility(_ action: String, _ name: String) {
        host?.requestVisibility(action, name: name)
    }

    func focusNode(_ id: Int) {
        (nodes[id] as? Input)?.focus()
    }

    func makeInput(_ id: Int) -> Input {
        let input = Input()
        input.onChange = { [weak self] value in self?.dispatch(id, "input", value) }
        input.onSubmit = { [weak self] value in self?.dispatch(id, "submit", value) }
        input.onKey = { [weak self] event, name in
            self?.dispatch(id, "key", event.map { Self.payload(KeyEvent($0)) } ?? ["key": name]) ?? false
        }
        return input
    }

    func wireEvents(of entry: SurfaceEntry) {
        entry.surface.onEvent = { [weak self, weak entry] event in
            guard let self, let entry else { return }
            self.handle(event, on: entry)
        }
        entry.surface.onDrag = { [weak self, weak entry] event in
            guard let self, let entry else { return false }
            return self.handleDrag(event, on: entry)
        }
        entry.surface.onKey = { [weak self, weak entry] key in
            guard let self, let entry else { return false }
            return self.dispatch(entry.id, "key", Self.payload(key))
        }
    }

    private func handle(_ event: SurfaceEvent, on entry: SurfaceEntry) {
        let receivesClicks = entry.config.input == .interactive || entry.config.input == .keyboard
        switch event {
        case .mouseDown(let point, let button):
            entry.pressed = receivesClicks ? firstListener("click", at: point, in: entry) : nil
            if receivesClicks, button == 0 { armDrag(at: point, in: entry) }
        case .mouseDragged(let point):
            continueDrag(at: point, in: entry)
        case .mouseUp(let point, let button, let clicks):
            defer {
                entry.pressed = nil
                entry.dragOrigin = nil
            }
            guard let target = firstListener("click", at: point, in: entry), target == entry.pressed else { return }
            dispatch(target, "click", ["x": point.x, "y": point.y, "button": button == 1 ? "right" : "left", "clicks": clicks])
        case .mouseMoved, .mouseExited:
            pointerMoved()
        case .scroll(let point, let dx, let dy):
            guard let target = firstListener("scroll", at: point, in: entry) else { return }
            dispatch(target, "scroll", ["dx": dx, "dy": dy])
        case .focusChanged(let focused):
            if focused { autofocus(in: entry.root.node) }
            dispatch(entry.id, focused ? "focus" : "blur", NSNull())
        }
    }

    private func firstListener(_ kind: String, at point: CGPoint, in entry: SurfaceEntry) -> Int? {
        entry.root.hitPath(at: point)
            .compactMap { nodeIDs[ObjectIdentifier($0)] }
            .first { listeners[$0]?.contains(kind) == true }
    }

    func updateHover(_ hovered: Set<Int>, in entry: SurfaceEntry) {
        let left = entry.hovered.subtracting(hovered)
        let entered = hovered.subtracting(entry.hovered)
        entry.hovered = hovered
        for id in left { dispatch(id, "hover", false) }
        for id in entered { dispatch(id, "hover", true) }
    }

    private func autofocus(in node: Node) {
        if let input = node as? Input, input.autofocus { return input.focus() }
        for child in node.children { autofocus(in: child) }
    }

    @discardableResult
    func dispatch(_ id: Int, _ kind: String, _ payload: Any) -> Bool {
        guard !disposed else { return false }
        let hook = context.objectForKeyedSubscript("__halo")?.objectForKeyedSubscript("dispatch")
        guard let hook, !hook.isUndefined else { return false }
        return hook.call(withArguments: [id, kind, payload])?.toBool() ?? false
    }

    static func payload(_ key: KeyEvent) -> [String: Any] {
        ["key": key.key, "shift": key.shift, "ctrl": key.control, "alt": key.option, "meta": key.command, "repeat": key.isRepeat]
    }

    // MARK: Clicks outside a surface (for popups and launchers)

    /// Monitors exist only while some surface listens for `clickOutside`. Global monitors see other apps' clicks;
    /// the local one sees clicks on halo's own surfaces. Neither needs a permission for mouse events.
    func updateMouseMonitors() {
        let wanted = !disposed && surfaces.keys.contains { listeners[$0]?.contains("clickOutside") == true }
        if wanted == !mouseMonitors.isEmpty { return }
        guard wanted else { return stopMouseMonitors() }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedAt(NSEvent.mouseLocation) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.clickedAt(NSEvent.mouseLocation) }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }

    func stopMouseMonitors() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
    }

    private func clickedAt(_ appKitPoint: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = Geometry.appKitToTopLeft(CGRect(origin: appKitPoint, size: .zero), primaryHeight: primaryHeight).origin
        let outside = surfaces.values.filter {
            $0.shown && listeners[$0.id]?.contains("clickOutside") == true && !$0.surface.frame.contains(point)
        }
        for entry in outside { dispatch(entry.id, "clickOutside", NSNull()) }
    }
}

// MARK: Animation

extension Runtime {
    func animate(_ id: Int, _ tracks: JSValue, _ options: JSValue, _ done: JSValue) -> String {
        guard let node = nodes[id] else { return "" }
        return node.animate(AnimationConversions.keyframes(tracks, options)) { [weak self] finished in
            guard let self, !self.disposed else { return }
            done.call(withArguments: [finished])
        }
    }

    func cancelAnimation(_ id: Int, _ key: String) {
        nodes[id]?.cancelAnimation(key)
    }

    /// One display link per runtime, running only while some `onFrame` callback is subscribed.
    func setFrames(_ id: Int, _ enabled: Bool) {
        if enabled { frameSubscribers.insert(id) } else { frameSubscribers.remove(id) }
        updateFrameLink()
    }

    func updateFrameLink() {
        let wanted = !disposed && !frameSubscribers.isEmpty
        if wanted == (frameLink != nil) { return }
        guard wanted, let screen = NSScreen.main else {
            frameLink?.invalidate()
            frameLink = nil
            return
        }
        let ticker = FrameTicker { [weak self] timestamp in self?.tick(timestamp) }
        let link = screen.displayLink(target: ticker, selector: #selector(FrameTicker.step(_:)))
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    private func tick(_ timestamp: CFTimeInterval) {
        for id in frameSubscribers { dispatch(id, "frame", timestamp * 1000) }
    }
}

/// Display links retain their target; this keeps the runtime out of that cycle.
private final class FrameTicker: NSObject, @unchecked Sendable {
    private let onFrame: @MainActor (CFTimeInterval) -> Void

    init(_ onFrame: @escaping @MainActor (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
    }

    @objc func step(_ link: CADisplayLink) {
        let timestamp = link.targetTimestamp
        MainActor.assumeIsolated { onFrame(timestamp) }
    }
}

// MARK: Inspection

extension Runtime {
    /// A JSON-friendly snapshot of every surface and its node tree, for `halo inspect`.
    public func inspect() -> [String: Any] {
        let list = surfaces.values.sorted { $0.id < $1.id }.map { entry -> [String: Any] in
            [
                "id": entry.id,
                "name": entry.options.name ?? NSNull(),
                "screen": Int(entry.config.screen),
                "frame": Self.json(entry.surface.frame),
                "shown": entry.shown,
                "input": "\(entry.config.input)",
                "layer": "\(entry.config.layer)",
                "listens": Array(listeners[entry.id] ?? []).sorted(),
                "root": describe(entry.root.node),
            ]
        }
        return ["surfaces": list, "counts": [
            "nodes": counts.nodes, "surfaces": counts.surfaces, "timers": counts.timers, "services": counts.services,
            "watchers": counts.watchers, "processes": counts.processes,
        ]]
    }

    private func describe(_ node: Node) -> [String: Any] {
        var info: [String: Any] = [
            "type": String(describing: type(of: node)),
            "frame": Self.json(node.layoutFrame),
        ]
        if let id = nodeIDs[ObjectIdentifier(node)] {
            info["id"] = id
            if let kinds = listeners[id] { info["listens"] = Array(kinds).sorted() }
        }
        if let text = node as? Text { info["text"] = text.text }
        if let input = node as? Input { info["value"] = input.value }
        if let image = node as? Image, let source = image.source { info["source"] = "\(source)" }
        if !node.children.isEmpty { info["children"] = node.children.map(describe) }
        return info
    }

    private static func json(_ rect: CGRect) -> [String: Any] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }
}

// MARK: Clicks through empty areas

extension Runtime {
    /// While an interactive surface is on screen, follow the pointer and make each surface mouse-transparent wherever
    /// nothing painted or listening is under it, so empty parts of a widget don't swallow clicks.
    func updatePointerMonitors() {
        let wanted = !disposed && surfaces.values.contains { $0.shown && $0.config.input != .passthrough }
        if wanted == !pointerMonitors.isEmpty { return }
        guard wanted else { return stopPointerMonitors() }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        pointerMonitors = [global, local].compactMap { $0 }
        checkPointerSoon()
    }

    /// Placing and destroying surfaces happens inside JS effects: hover handlers run after them, not in the middle.
    /// Several requests in one main-queue turn (layouts, placements) share one check.
    func checkPointerSoon() {
        guard !pointerCheckQueued else { return }
        pointerCheckQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.pointerCheckQueued = false
                self?.pointerMoved()
            }
        }
    }

    func stopPointerMonitors() {
        for monitor in pointerMonitors { NSEvent.removeMonitor(monitor) }
        pointerMonitors.removeAll()
        coverCheck?.invalidate()
        coverCheck = nil
    }

    /// Hover follows these monitors too: halo is never the active app, so its panels see only a few of the
    /// pointer's moves (and none at the screen's top edge, where the menu bar takes them).
    /// Whether another window covers the surface is asked only when the hovered set would change (each call lists
    /// every window), and once more after the pointer settles on an unchanged one.
    func pointerMoved(recheckCovered: Bool = false) {
        let point = pointerLocation()
        var settling = false
        for entry in surfaces.values {
            let frame = entry.surface.frame
            guard entry.shown, entry.config.input != .passthrough, frame.contains(point) else {
                if !entry.hovered.isEmpty { updateHover([], in: entry) }
                continue
            }
            let path = entry.root.hitPath(at: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
            let transparent = !isSolid(path)
            if transparent != entry.mouseTransparent {
                entry.mouseTransparent = transparent
                entry.surface.setMouseTransparent(transparent)
            }
            let ids = transparent ? [] : path.compactMap { nodeIDs[ObjectIdentifier($0)] }
            let hovered = Set(ids.filter { listeners[$0]?.contains("hover") == true })
            if !hovered.isEmpty, hovered == entry.hovered, !recheckCovered {
                settling = true
                continue
            }
            updateHover(hovered.isEmpty || entry.surface.isCovered(at: point) ? [] : hovered, in: entry)
        }
        coverCheck?.invalidate()
        coverCheck = settling ? Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved(recheckCovered: true) }
        } : nil
    }

    /// Painted nodes, draggable ones and ones with listeners (drop zones included) catch the pointer.
    func isSolid(_ path: [Node]) -> Bool {
        path.contains { node in
            node.paintsContent || nodeIDs[ObjectIdentifier(node)].map { listeners[$0] != nil || draggables[$0] != nil } == true
        }
    }
}

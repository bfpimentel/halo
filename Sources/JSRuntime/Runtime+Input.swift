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
        input.onKey = { [weak self] key in self?.dispatch(id, "key", ["key": key]) ?? false }
        return input
    }

    func wireEvents(of entry: SurfaceEntry) {
        entry.surface.onEvent = { [weak self, weak entry] event in
            guard let self, let entry else { return }
            self.handle(event, on: entry)
        }
        entry.surface.onKey = { [weak self, weak entry] key in
            guard let self, let entry else { return false }
            return self.dispatch(entry.id, "key", Self.payload(key))
        }
    }

    private func handle(_ event: SurfaceEvent, on entry: SurfaceEntry) {
        let receivesClicks = entry.config.input == .interactive || entry.config.input == .keyboard
        switch event {
        case .mouseDown(let point, _):
            entry.pressed = receivesClicks ? firstListener("click", at: point, in: entry) : nil
        case .mouseUp(let point, let button, let clicks):
            defer { entry.pressed = nil }
            guard let target = firstListener("click", at: point, in: entry), target == entry.pressed else { return }
            dispatch(target, "click", ["x": point.x, "y": point.y, "button": button == 1 ? "right" : "left", "clicks": clicks])
        case .mouseMoved(let point):
            let ids = entry.root.hitPath(at: point).compactMap { nodeIDs[ObjectIdentifier($0)] }
            updateHover(Set(ids.filter { listeners[$0]?.contains("hover") == true }), in: entry)
        case .mouseExited:
            updateHover([], in: entry)
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

    private func updateHover(_ hovered: Set<Int>, in entry: SurfaceEntry) {
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

    private static func payload(_ key: KeyEvent) -> [String: Any] {
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

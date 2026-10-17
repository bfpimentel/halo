import AppKit

/// Whether files are being dragged anywhere (from Finder, any app, or halo itself). A drag is a mouse-down followed by
/// a new drag pasteboard holding file URLs. Mouse-downs come from global and local monitors (no permission needed for
/// mouse events); while the button stays down, a 0.1 s timer checks the pasteboard, since a drag session swallows the
/// drag events of the app it starts in. Only the pasteboard's change count and types are read, never its contents.
/// Idle (no button held) it costs nothing.
@MainActor
final class DragService: Service {
    private var monitors: [Any] = []
    private var timer: Timer?
    private var active = false
    private var baseline = 0
    private var publish: (@MainActor ([String: Any]) -> Void)?
    private let pasteboard = NSPasteboard(name: .drag)

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        self.publish = publish
        baseline = pasteboard.changeCount
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }
        monitors = [global, local].compactMap { $0 }
        publish(["active": false])
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
        publish = nil
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            baseline = pasteboard.changeCount
            set(false)
            watchWhilePressed()
        case .leftMouseDragged:
            check()
        default:
            set(false)
        }
    }

    private func watchWhilePressed() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            timer?.invalidate()
            timer = nil
            return set(false)
        }
        guard !active, pasteboard.changeCount != baseline, pasteboard.types?.contains(.fileURL) == true else { return }
        set(true)
    }

    private func set(_ value: Bool) {
        guard value != active else { return }
        active = value
        publish?(["active": value])
    }
}

import AppKit

/// The frontmost app, from workspace activation notifications.
@MainActor
final class FrontAppService: Service {
    private var observer: NSObjectProtocol?

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        let send: @MainActor () -> Void = { publish(Self.read()) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { send() } }
        send()
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    static func read() -> [String: Any] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [:] }
        return [
            "name": app.localizedName ?? NSNull(),
            "bundleId": app.bundleIdentifier ?? NSNull(),
            "pid": Int(app.processIdentifier),
        ]
    }
}

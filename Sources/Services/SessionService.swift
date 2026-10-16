import AppKit
import CoreGraphics

/// Screen lock, display sleep and wake from system sleep. Lock state comes from the undocumented
/// `com.apple.screenIsLocked`/`Unlocked` distributed notifications and the session's `CGSSessionScreenIsLocked` key
/// (present only while locked), so it may be missing on future macOS versions; the rest is public API.
@MainActor
final class SessionService: Service {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var locked: Bool?
    private var displaysAsleep = false
    private var lastWake: Double?

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        locked = Self.sessionLocked()
        let send: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            publish([
                "locked": locked.map { $0 as Any } ?? NSNull(),
                "displaysAsleep": displaysAsleep,
                "lastWake": lastWake.map { $0 as Any } ?? NSNull(),
            ])
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let watch: [(NSNotification.Name, @MainActor (SessionService) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.displaysAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.displaysAsleep = false }),
            (NSWorkspace.didWakeNotification, { $0.lastWake = Date().timeIntervalSince1970 * 1000 }),
        ]
        for (name, apply) in watch {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    apply(self)
                    send()
                }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.locked = value
                    send()
                }
            })
        }
        send()
    }

    func stop() {
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        workspaceObservers.removeAll()
        distributedObservers.removeAll()
    }

    private static func sessionLocked() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}

import Foundation

/// Low Power Mode and the thermal state, from ProcessInfo notifications (posted on any thread; hopped to main).
@MainActor
final class PowerService: Service {
    private var observers: [NSObjectProtocol] = []

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        let send: @MainActor @Sendable () -> Void = { publish(Self.read()) }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { send() }
            })
        }
        send()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    static func read() -> [String: Any] {
        let thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
        return ["lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled, "thermal": thermal]
    }
}

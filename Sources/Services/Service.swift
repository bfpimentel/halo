import Foundation

/// A native data source. It observes only between `start` and `stop`, and publishes its whole state (JSON-like
/// values) on start and on every change.
@MainActor
public protocol Service: AnyObject {
    func start(publish: @escaping @MainActor ([String: Any]) -> Void)
    func stop()
    /// Commands from JS (e.g. `setVolume`); returns whether the action exists and succeeded.
    func perform(_ action: String, _ value: Any?) -> Bool
}

extension Service {
    public func perform(_ action: String, _ value: Any?) -> Bool { false }
}

public enum Services {
    /// `name` is `battery`, `audio`, `network`, `frontApp`, `power`, `session` or `system`; `system` takes `intervalMs`.
    @MainActor
    public static func make(_ name: String, options: [String: Any] = [:]) -> Service? {
        switch name {
        case "battery": BatteryService()
        case "audio": AudioService()
        case "network": NetworkService()
        case "frontApp": FrontAppService()
        case "power": PowerService()
        case "session": SessionService()
        case "system": SystemService(interval: (options["intervalMs"] as? Double).map { $0 / 1000 } ?? 2)
        default: nil
        }
    }
}

import Foundation
import Network

/// Connectivity and interface type from `NWPathMonitor`. No Wi-Fi name: that needs Location permission.
@MainActor
final class NetworkService: Service {
    private var monitor: NWPathMonitor?

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let state = Self.describe(path)
            nonisolated(unsafe) let sendable = state
            DispatchQueue.main.async { MainActor.assumeIsolated { publish(sendable) } }
        }
        monitor.start(queue: DispatchQueue(label: "halo.network"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    nonisolated static func describe(_ path: NWPath) -> [String: Any] {
        let type: String = if path.status != .satisfied {
            "none"
        } else if path.usesInterfaceType(.wifi) {
            "wifi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            "ethernet"
        } else if path.usesInterfaceType(.cellular) {
            "cellular"
        } else {
            "other"
        }
        return [
            "connected": path.status == .satisfied,
            "type": type,
            "expensive": path.isExpensive,
            "constrained": path.isConstrained,
        ]
    }
}

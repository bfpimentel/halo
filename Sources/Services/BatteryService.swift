import Foundation
import IOKit.ps

/// Internal battery state from IOKit power-source notifications (no polling).
@MainActor
final class BatteryService: Service {
    private var source: CFRunLoopSource?
    private var publish: (@MainActor ([String: Any]) -> Void)?

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        self.publish = publish
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            nonisolated(unsafe) let service = context
            MainActor.assumeIsolated { Unmanaged<BatteryService>.fromOpaque(service).takeUnretainedValue().refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
            source = loop
        }
        refresh()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        publish = nil
    }

    private func refresh() {
        publish?(Self.read())
    }

    static func read() -> [String: Any] {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let battery = sources
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }

        var state: [String: Any] = ["present": battery != nil, "source": providing == kIOPMACPowerKey ? "ac" : "battery"]
        guard let battery else { return state }
        let current = battery[kIOPSCurrentCapacityKey] as? Double ?? 0
        let maximum = max(battery[kIOPSMaxCapacityKey] as? Double ?? 100, 1)
        state["percent"] = (current / maximum * 100).rounded()
        state["charging"] = battery[kIOPSIsChargingKey] as? Bool ?? false
        let charging = state["charging"] as? Bool ?? false
        let minutes = battery[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
        state["minutesRemaining"] = minutes >= 0 ? minutes : NSNull()
        return state
    }
}

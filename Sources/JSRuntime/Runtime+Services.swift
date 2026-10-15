import JavaScriptCore
import Services

/// Native services shared by every reader in the config: the first subscriber starts one, the last stops it.
/// `system` runs one instance per sampling interval.
extension Runtime {
    final class ServiceEntry {
        let service: Service
        var subscribers: [Int: JSValue] = [:]
        var state: [String: Any]?

        init(service: Service) {
            self.service = service
        }
    }

    func subscribeService(_ name: String, _ optionsValue: JSValue, _ callback: JSValue) -> Int {
        guard !disposed else { return 0 }
        let options = optionsValue.isObject ? (optionsValue.toDictionary() as? [String: Any] ?? [:]) : [:]
        let key = (options["intervalMs"] as? Double).map { "\(name)@\(Int($0))" } ?? name
        let entry: ServiceEntry
        if let existing = serviceEntries[key] {
            entry = existing
        } else {
            guard let service = serviceFactory(name, options) else {
                Log.warn("unknown service \"\(name)\"")
                return 0
            }
            entry = ServiceEntry(service: service)
            serviceEntries[key] = entry
            service.start { [weak self, weak entry] state in
                guard let self, let entry, !self.disposed else { return }
                entry.state = state
                for subscriber in entry.subscribers.values { subscriber.call(withArguments: [state]) }
            }
        }
        let id = makeID()
        entry.subscribers[id] = callback
        serviceSubscriptions[id] = key
        if let state = entry.state { callback.call(withArguments: [state]) }
        return id
    }

    func unsubscribeService(_ id: Int) {
        guard let key = serviceSubscriptions.removeValue(forKey: id), let entry = serviceEntries[key] else { return }
        entry.subscribers[id] = nil
        guard entry.subscribers.isEmpty else { return }
        entry.service.stop()
        serviceEntries[key] = nil
    }

    /// Runs an action on a running instance, or on a short-lived one when nothing reads that service.
    func serviceAction(_ name: String, _ action: String, _ value: JSValue) -> Bool {
        guard !disposed else { return false }
        let argument = value.toObject()
        if let entry = serviceEntries.first(where: { $0.key == name || $0.key.hasPrefix("\(name)@") })?.value {
            return entry.service.perform(action, argument)
        }
        guard let service = serviceFactory(name, [:]) else { return false }
        service.start { _ in }
        defer { service.stop() }
        return service.perform(action, argument)
    }

    func stopServices() {
        for entry in serviceEntries.values { entry.service.stop() }
        serviceEntries.removeAll()
        serviceSubscriptions.removeAll()
    }
}

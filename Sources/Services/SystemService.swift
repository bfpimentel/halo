import Darwin
import Foundation

/// CPU and memory usage, sampled on the interval the config asked for (there's no notification for these).
@MainActor
final class SystemService: Service {
    private let interval: TimeInterval
    private var timer: Timer?
    private var previous: CPUTicks?

    init(interval: TimeInterval) {
        self.interval = max(0.25, interval)
    }

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        previous = CPUTicks.now()
        let sample: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            let ticks = CPUTicks.now()
            var state: [String: Any] = Self.memory()
            if let ticks, let previous = self.previous { state["cpu"] = ticks.usage(since: previous) }
            self.previous = ticks
            publish(state)
        }
        sample()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { sample() } }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func memory() -> [String: Any] {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return ["memoryTotal": total] }
        let page = Double(getpagesize())
        let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return ["memoryUsed": used, "memoryTotal": total, "memory": used / total]
    }
}

/// Cumulative CPU ticks across all cores.
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var nice: UInt64
    var idle: UInt64

    /// Share of time spent busy between `previous` and now, 0…1.
    func usage(since previous: CPUTicks) -> Double {
        let busy = Double((user &- previous.user) + (system &- previous.system) + (nice &- previous.nice))
        let total = busy + Double(idle &- previous.idle)
        return total > 0 ? busy / total : 0
    }

    static func now() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = load.cpu_ticks
        return CPUTicks(user: UInt64(ticks.0), system: UInt64(ticks.1), nice: UInt64(ticks.3), idle: UInt64(ticks.2))
    }
}

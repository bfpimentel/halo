import CoreServices
import Foundation

/// Calls `onChange` (debounced, on main) when anything under `directory` changes, ignoring dependencies and VCS.
@MainActor
final class ConfigWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init(directory: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let changed = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []).prefix(count)
            guard changed.contains(where: { !$0.contains("/node_modules/") && !$0.contains("/.git/") }) else { return }
            nonisolated(unsafe) let watcher = info
            MainActor.assumeIsolated {
                Unmanaged<ConfigWatcher>.fromOpaque(watcher).takeUnretainedValue().scheduleChange()
            }
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}

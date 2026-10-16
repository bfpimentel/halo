import CoreServices
import Foundation
import JavaScriptCore

/// Runs `work` on a background queue, then `done` with its result on main. A free function, so neither closure
/// inherits the caller's main-actor isolation (which would trap when `work` runs off the main thread).
func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T, then done: @escaping @MainActor @Sendable (T) -> Void) {
    DispatchQueue.global(qos: .utility).async {
        let value = work()
        DispatchQueue.main.async { MainActor.assumeIsolated { done(value) } }
    }
}

/// `readFile`, `writeFile` and `watchFile` (see `runtime/src/host.ts`). I/O runs off the main thread; callbacks run on main.
extension Runtime {
    /// `~` is the home folder; relative paths start at the config folder.
    func resolvePath(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        let base = configDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return base.appendingPathComponent(expanded).standardizedFileURL
    }

    func readFile(_ path: String, _ callback: JSValue) {
        guard !disposed else { return }
        let url = resolvePath(path)
        let id = makeID()
        pendingFileCallbacks[id] = callback
        offMain({
            Result { try String(contentsOf: url, encoding: .utf8) }.mapError { Self.describe($0, url) }
        }, then: { [weak self] result in
            guard let self, let callback = self.pendingFileCallbacks.removeValue(forKey: id) else { return }
            switch result {
            case .success(let text): callback.call(withArguments: [text, NSNull()])
            case .failure(let error): callback.call(withArguments: [NSNull(), error.message])
            }
        })
    }

    func writeFile(_ path: String, _ text: String, _ callback: JSValue) {
        guard !disposed else { return }
        let url = resolvePath(path)
        let id = makeID()
        pendingFileCallbacks[id] = callback
        offMain({ () -> String? in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                return nil
            } catch {
                return Self.describe(error, url).message
            }
        }, then: { [weak self] error in
            guard let self, let callback = self.pendingFileCallbacks.removeValue(forKey: id) else { return }
            callback.call(withArguments: [error.map { $0 as Any } ?? NSNull()])
        })
    }

    /// Calls `callback(text | null)` now and whenever the file's contents change (null while it doesn't exist).
    func watchFile(_ path: String, _ callback: JSValue) -> Int {
        guard !disposed else { return 0 }
        let id = makeID()
        fileWatchers[id] = FileWatcher(url: resolvePath(path)) { [weak self] text in
            guard let self, !self.disposed, self.fileWatchers[id] != nil else { return }
            callback.call(withArguments: [text.map { $0 as Any } ?? NSNull()])
        }
        return id
    }

    func unwatchFile(_ id: Int) {
        fileWatchers.removeValue(forKey: id)?.stop()
    }

    func stopFileWatchers() {
        for watcher in fileWatchers.values { watcher.stop() }
        fileWatchers.removeAll()
        pendingFileCallbacks.removeAll()
    }

    struct FileError: Error {
        let message: String
    }

    nonisolated static func describe(_ error: Error, _ url: URL) -> FileError {
        let reason = (error as NSError).localizedFailureReason ?? error.localizedDescription
        return FileError(message: "\(url.path): \(reason)")
    }
}

/// Watches one file through FSEvents on its nearest existing folder, so atomic saves (write + rename), deletes and
/// folders created later are all seen. Delivers the contents only when they change.
@MainActor
final class FileWatcher {
    private let url: URL
    private let target: String
    private let onChange: @MainActor (String?) -> Void
    private var stream: FSEventStreamRef?
    private var last: String??
    private var reading = false
    private var dirty = false

    init(url: URL, onChange: @escaping @MainActor (String?) -> Void) {
        self.url = url
        self.onChange = onChange
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder.deleteLastPathComponent()
        }
        // FSEvents reports real paths (/private/var/…). realpath, not resolvingSymlinksInPath, which strips /private.
        let real = realpath(folder.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        } ?? folder.path
        let rest = url.path.dropFirst(folder.path.count)
        target = real == "/" ? String(rest) : real + rest
        start(watching: real)
        read()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    isolated deinit { stop() }

    private func start(watching folder: String) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let changed = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []).prefix(count)
            nonisolated(unsafe) let watcher = info
            let paths = Array(changed)
            MainActor.assumeIsolated {
                Unmanaged<FileWatcher>.fromOpaque(watcher).takeUnretainedValue().changed(paths)
            }
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, [folder] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    /// The file itself, or a folder on its path (created, renamed, deleted).
    private func changed(_ paths: [String]) {
        guard stream != nil, paths.contains(where: { $0 == target || target.hasPrefix($0 + "/") }) else { return }
        read()
    }

    private func read() {
        guard !reading else {
            dirty = true
            return
        }
        reading = true
        let url = url
        offMain({ try? String(contentsOf: url, encoding: .utf8) }, then: { [weak self] text in
            guard let self, self.stream != nil else { return }
            self.reading = false
            if case .some(let previous) = self.last, previous == text {} else {
                self.last = .some(text)
                self.onChange(text)
            }
            if self.dirty {
                self.dirty = false
                self.read()
            }
        })
    }
}

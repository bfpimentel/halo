import AppKit
import Compositor
import JSRuntime

/// Owns the current config's `Runtime` and swaps it on every rebuild.
@MainActor
final class Host {
    private let configDirectory: URL
    private let bundler: Bundler
    private let backend = PublicBackend()
    private var screens: Screens?
    private var watcher: ConfigWatcher?
    private var runtime: Runtime?

    init(configDirectory: URL, bundler: Bundler) {
        self.configDirectory = configDirectory
        self.bundler = bundler
    }

    func start() {
        screens = Screens { [weak self] in self?.runtime?.screensChanged($0) }
        watcher = ConfigWatcher(directory: configDirectory) { [weak self] in self?.reload() }
        reload()
    }

    /// A failed build keeps the previous config running.
    func reload() {
        let started = Date()
        let script: String
        do {
            script = try bundler.build(configDirectory: configDirectory)
        } catch {
            Log.error("build failed, keeping the previous config:\n\(error)")
            return
        }

        if let previous = runtime {
            let leaked = previous.dispose()
            if leaked != .zero { Log.warn("previous config left \(leaked) alive after its cleanups; released them") }
        }
        let next = Runtime(backend: backend, screens: screens?.all ?? Screens.snapshot())
        next.evaluate(script, sourceURL: configDirectory.appendingPathComponent("main.tsx"))
        runtime = next
        Log.info("loaded \(configDirectory.path) in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(next.counts))")
    }
}

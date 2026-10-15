import AppKit
import Compositor
import IPC
import JSRuntime

/// Owns the current config's `Runtime`, swaps it on every rebuild, and answers IPC requests.
@MainActor
final class Host {
    private let configDirectory: URL
    private let bundler: Bundler
    private let backend = PublicBackend()
    private var screens: Screens?
    private var watcher: ConfigWatcher?
    private var server: IPCServer?
    private var runtime: Runtime?
    private var lastEvents: [String: [String: String]] = [:]

    init(configDirectory: URL, bundler: Bundler) {
        self.configDirectory = configDirectory
        self.bundler = bundler
    }

    func start(socketPath: String) throws {
        server = try IPCServer(path: socketPath) { [weak self] request in
            self?.handle(request) ?? Response(ok: false, error: "host is shutting down")
        }
        screens = Screens { [weak self] in self?.runtime?.screensChanged($0) }
        watcher = ConfigWatcher(directory: configDirectory) { [weak self] in self?.reload() }
        reload()
    }

    /// A failed build keeps the previous config running.
    @discardableResult
    func reload() -> Bool {
        let started = Date()
        let script: String
        do {
            script = try bundler.build(configDirectory: configDirectory)
        } catch {
            Log.error("build failed, keeping the previous config:\n\(error)")
            return false
        }

        disposeRuntime()
        let next = Runtime(backend: backend, screens: screens?.all ?? Screens.snapshot(), events: lastEvents)
        next.evaluate(script, sourceURL: configDirectory.appendingPathComponent("main.tsx"))
        runtime = next
        Log.info("loaded \(configDirectory.path) in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(next.counts))")
        return true
    }

    func shutdown() {
        disposeRuntime()
        server?.stop()
        server = nil
        Log.info("stopped")
    }

    private func disposeRuntime() {
        guard let previous = runtime else { return }
        runtime = nil
        let leaked = previous.dispose()
        if leaked != .zero { Log.warn("previous config left \(leaked) alive after its cleanups; released them") }
    }

    private func handle(_ request: Request) -> Response {
        switch request {
        case .trigger(let name, let payload):
            lastEvents[name] = payload
            runtime?.deliver(event: name, payload: payload)
            return .success
        case .reload:
            return reload() ? .success : Response(ok: false, error: "build failed; see `halo log`")
        case .quit:
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.shutdown() }
                exit(0)
            }
            return .success
        }
    }
}

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
    /// `halo settings`: its own runtime, so the user config's reloads (which its edits cause) never touch it.
    private var settings: Runtime?
    private lazy var settingsHost = SettingsHost(host: self)
    /// The user config's latest widget schemas, handed to `halo settings` when it opens and on every reload.
    private var schemas = "{}"
    private var lastEvents: [String: [String: String]] = [:]
    private var visibility = Visibility()
    private lazy var errors = ErrorPanel(backend: backend)

    init(configDirectory: URL, bundler: Bundler) {
        self.configDirectory = configDirectory
        self.bundler = bundler
    }

    func start(socketPath: String) throws {
        server = try IPCServer(path: socketPath) { [weak self] request in
            self?.handle(request) ?? Response(ok: false, error: "host is shutting down")
        }
        screens = Screens { [weak self] in
            self?.runtime?.screensChanged($0)
            self?.settings?.screensChanged($0)
        }
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
            showError(title: "halo · build failed (previous config still running)", message: "\(error)")
            return false
        }

        errors.dismiss()
        disposeRuntime()
        let next = Runtime(backend: backend, screens: screens?.all ?? Screens.snapshot(), events: lastEvents, host: self, configDirectory: configDirectory)
        runtime = next
        next.evaluate(script) { [bundler, configDirectory] in bundler.displayName(forSource: $0, configDirectory: configDirectory) }
        Log.info("loaded \(configDirectory.path) in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(next.counts))")
        return true
    }

    func shutdown() {
        errors.dismiss()
        closeSettings()
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

    /// Opens the settings editor, or closes it when it's open.
    func toggleSettings() throws {
        guard settings == nil else { return closeSettings() }
        let script = try bundler.buildSettings(configDirectory: configDirectory)
        let next = Runtime(backend: backend, screens: screens?.all ?? Screens.snapshot(), host: settingsHost, configDirectory: configDirectory)
        settings = next
        next.evaluate(script) { [bundler, configDirectory] in bundler.displayName(forSource: $0, configDirectory: configDirectory) }
        next.deliverSchemas(schemas)
        Log.info("settings opened (\(next.counts))")
    }

    func closeSettings() {
        guard let previous = settings else { return }
        settings = nil
        let leaked = previous.dispose()
        if leaked != .zero { Log.warn("settings left \(leaked) alive after its cleanups; released them") }
        Log.info("settings closed")
    }

    private func changeVisibility(_ action: VisibilityAction, _ target: VisibilityTarget) throws {
        guard let runtime else { throw Visibility.UnknownNames(names: [], available: []) }
        try visibility.apply(action, to: target, mounted: runtime.surfaceNames)
        runtime.refreshVisibility()
    }

    private func handle(_ request: Request) -> Response {
        switch request {
        case .trigger(let name, let payload):
            lastEvents[name] = payload
            runtime?.deliver(event: name, payload: payload)
            return .success
        case .visibility(let action, let target):
            do {
                try changeVisibility(action, target)
                return .success
            } catch {
                return Response(ok: false, error: "\(error)")
            }
        case .inspect:
            guard let runtime else { return Response(ok: false, error: "no config loaded") }
            var tree = runtime.inspect()
            if let settings { tree["settings"] = settings.inspect() }
            let data = try? JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted, .sortedKeys])
            return Response(ok: true, output: data.map { String(decoding: $0, as: UTF8.self) })
        case .settings:
            do {
                try toggleSettings()
                return .success
            } catch {
                Log.error("settings failed to build:\n\(error)")
                return Response(ok: false, error: "settings failed to build: \(error)")
            }
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

extension Host: RuntimeHost {
    func schemasChanged(_ json: String) {
        schemas = json
        settings?.deliverSchemas(json)
    }

    func report(error: String) {
        showError(title: "halo · error in config", message: error)
    }

    fileprivate func showError(title: String, message: String) {
        guard let screen = (screens?.all ?? Screens.snapshot()).first else { return }
        errors.show(title: title, message: message, on: screen)
    }

    func isHidden(name: String?) -> Bool {
        visibility.isHidden(name: name)
    }

    func register(name: String, defaultHidden: Bool) {
        visibility.register(name: name, defaultHidden: defaultHidden)
    }

    func requestVisibility(_ action: String, name: String) {
        guard let action = VisibilityAction(rawValue: action) else { return Log.warn("unknown visibility action \(action)") }
        do {
            try changeVisibility(action, .names([name]))
        } catch {
            Log.warn("\(action.rawValue)(\"\(name)\"): \(error)")
        }
    }
}

/// The settings runtime's host: errors go to the same panel, its surfaces are never hidden by name, and its own
/// `close()` (Esc, the close button) tears it down. Closing waits a run-loop turn: the call comes from inside its JS.
@MainActor
private final class SettingsHost: RuntimeHost {
    private unowned let host: Host

    init(host: Host) { self.host = host }

    func report(error: String) { host.report(error: error) }
    func isHidden(name: String?) -> Bool { false }
    func register(name: String, defaultHidden: Bool) {}
    func requestVisibility(_ action: String, name: String) { host.requestVisibility(action, name: name) }

    func close() {
        DispatchQueue.main.async { [host] in MainActor.assumeIsolated { host.closeSettings() } }
    }
}

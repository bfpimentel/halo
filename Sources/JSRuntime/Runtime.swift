import Compositor
import Foundation
import JavaScriptCore
import Render

/// One loaded config: a JSContext plus every native object it created, all released by `dispose()`.
@MainActor
public final class Runtime {
    public struct Counts: Equatable, Sendable, CustomStringConvertible {
        public var nodes = 0
        public var surfaces = 0
        public var timers = 0

        public static let zero = Counts()

        public var description: String { "\(nodes) nodes, \(surfaces) surfaces, \(timers) timers" }
    }

    private struct SurfaceEntry {
        let surface: Surface
        let root: RenderRoot
        var config: SurfaceConfig
    }

    let context: JSContext
    private let backend: CompositorBackend
    private var screens: [ScreenInfo]
    private var nodes: [Int: Node] = [:]
    private var surfaces: [Int: SurfaceEntry] = [:]
    private var timers: [Int: (timer: Timer, callback: JSValue, repeats: Bool)] = [:]
    private var processes: [Int: (process: Process, callback: JSValue)] = [:]
    private var formatters: [String: DateFormatter] = [:]
    private var lastEvents: [String: [String: String]]
    private var nextID = 1
    private var disposed = false

    public var counts: Counts {
        Counts(nodes: nodes.count, surfaces: surfaces.count, timers: timers.count)
    }

    /// `events` holds the latest payload per external event name, so a fresh load starts from known state.
    public init(backend: CompositorBackend, screens: [ScreenInfo], events: [String: [String: String]] = [:]) {
        self.backend = backend
        self.screens = screens
        lastEvents = events
        context = JSContext()
        context.name = "halo"
        context.exceptionHandler = { _, exception in
            guard let exception else { return }
            let stack = exception.forProperty("stack")?.toString() ?? ""
            Log.error("\(exception.toString() ?? "unknown error")\n\(stack)")
        }
        context.setObject(JSValue(newObjectIn: context), forKeyedSubscript: "__halo" as NSString)
        Bridge.install(in: context, runtime: self)
    }

    public func evaluate(_ script: String, sourceURL: URL? = nil) {
        context.evaluateScript(script, withSourceURL: sourceURL)
    }

    public func screensChanged(_ infos: [ScreenInfo]) {
        guard !disposed else { return }
        screens = infos
        backend.transaction {
            for entry in surfaces.values { place(entry) }
        }
        let hook = context.objectForKeyedSubscript("__halo")?.objectForKeyedSubscript("onScreens")
        if let hook, !hook.isUndefined {
            hook.call(withArguments: [infos.map(Conversions.screen)])
        }
    }

    public func deliver(event name: String, payload: [String: String]) {
        guard !disposed else { return }
        lastEvents[name] = payload
        let hook = context.objectForKeyedSubscript("__halo")?.objectForKeyedSubscript("onEvent")
        if let hook, !hook.isUndefined {
            hook.call(withArguments: [name, payload])
        }
    }

    /// Runs the config's own cleanups, then force-releases anything they missed.
    /// Returns what was still alive after the cleanups: anything non-zero is a leak in the runtime or the config.
    @discardableResult
    public func dispose() -> Counts {
        guard !disposed else { return .zero }
        let hook = context.objectForKeyedSubscript("__halo")?.objectForKeyedSubscript("dispose")
        if let hook, !hook.isUndefined {
            hook.call(withArguments: [])
        }
        let leftover = counts
        disposed = true

        for entry in timers.values { entry.timer.invalidate() }
        timers.removeAll()
        for (process, _) in processes.values where process.isRunning { process.terminate() }
        processes.removeAll()
        backend.transaction {
            for entry in surfaces.values {
                entry.root.detach()
                entry.surface.destroy()
            }
        }
        surfaces.removeAll()
        nodes.removeAll()
        context.exceptionHandler = nil
        return leftover
    }

    private func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func place(_ entry: SurfaceEntry) {
        guard let screen = screens.first(where: { $0.id == entry.config.screen }) else {
            var hidden = entry.config
            hidden.visible = false
            if let fallback = screens.first { entry.surface.update(hidden, screen: fallback) }
            return
        }
        entry.surface.update(entry.config, screen: screen)
        entry.root.size = entry.surface.frame.size
        entry.root.contentsScale = screen.scale
    }
}

// MARK: - Bridge operations (called from JS through `Bridge`)

extension Runtime {
    func log(_ level: String, _ message: String) {
        Log.write(level == "error" ? .error : level == "warn" ? .warn : .info, "[js] \(message)")
    }

    func createNode(_ kind: String) -> Int {
        guard !disposed else { return 0 }
        let node: Node = switch kind {
        case "text": Text("")
        case "image": Image()
        default: Box()
        }
        let id = makeID()
        nodes[id] = node
        return id
    }

    func setStyle(_ id: Int, _ key: String, _ value: JSValue) {
        guard let node = nodes[id] else { return }
        Conversions.applyStyle(key, value, to: node)
    }

    func setProp(_ id: Int, _ key: String, _ value: JSValue) {
        guard let node = nodes[id] else { return }
        Conversions.applyProp(key, value, to: node)
    }

    func insert(_ parentID: Int, _ childID: Int, _ index: Int) {
        guard let parent = nodes[parentID], let child = nodes[childID] else { return }
        parent.insert(child, at: index)
    }

    func detach(_ id: Int) {
        nodes[id]?.removeFromParent()
    }

    func destroyNode(_ id: Int) {
        nodes.removeValue(forKey: id)?.removeFromParent()
    }

    func createSurface(_ rootID: Int, _ configValue: JSValue) -> Int {
        guard !disposed, let node = nodes[rootID], let fallback = screens.first else { return 0 }
        let config = Conversions.surfaceConfig(configValue)
        let screen = screens.first { $0.id == config.screen } ?? fallback
        var initial = config
        if screen.id != config.screen { initial.visible = false }
        let surface = Surface(config: initial, screen: screen, backend: backend)
        let root = RenderRoot(node: node, hostLayer: surface.rootLayer, size: surface.frame.size, contentsScale: screen.scale)
        let id = makeID()
        surfaces[id] = SurfaceEntry(surface: surface, root: root, config: config)
        return id
    }

    func updateSurface(_ id: Int, _ configValue: JSValue) {
        guard var entry = surfaces[id] else { return }
        entry.config = Conversions.surfaceConfig(configValue)
        surfaces[id] = entry
        place(entry)
    }

    func destroySurface(_ id: Int) {
        guard let entry = surfaces.removeValue(forKey: id) else { return }
        entry.root.detach()
        entry.surface.destroy()
    }

    func screenList() -> [[String: Any]] {
        screens.map(Conversions.screen)
    }

    func setTimer(_ milliseconds: Double, _ repeats: Bool, _ callback: JSValue) -> Int {
        guard !disposed else { return 0 }
        let id = makeID()
        let timer = Timer(timeInterval: max(milliseconds, 0) / 1000, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireTimer(id) }
        }
        timer.tolerance = min(0.05, max(milliseconds, 1) / 1000 * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        timers[id] = (timer, callback, repeats)
        return id
    }

    private func fireTimer(_ id: Int) {
        guard let entry = timers[id] else { return }
        if !entry.repeats { timers[id] = nil }
        entry.callback.call(withArguments: [])
    }

    func clearTimer(_ id: Int) {
        timers.removeValue(forKey: id)?.timer.invalidate()
    }

    func exec(_ command: String, _ arguments: [String], _ callback: JSValue) {
        guard !disposed else { return }
        let process = Process()
        if command.contains("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let id = makeID()
        do {
            try process.run()
        } catch {
            callback.call(withArguments: [["stdout": "", "stderr": error.localizedDescription, "code": -1]])
            return
        }
        processes[id] = (process, callback)

        let outHandle = stdout.fileHandleForReading
        let errHandle = stderr.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let group = DispatchGroup()
            nonisolated(unsafe) var errData = Data()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                errData = errHandle.readDataToEndOfFile()
                group.leave()
            }
            let outData = outHandle.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            let result: [String: Any] = [
                "stdout": String(decoding: outData, as: UTF8.self),
                "stderr": String(decoding: errData, as: UTF8.self),
                "code": Int(process.terminationStatus),
            ]
            nonisolated(unsafe) let sendable = result
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let entry = self.processes.removeValue(forKey: id) else { return }
                    entry.callback.call(withArguments: [sendable])
                }
            }
        }
    }

    func lastEvent(_ name: String) -> [String: String]? {
        lastEvents[name]
    }

    func formatDate(_ pattern: String, _ epochMilliseconds: Double) -> String {
        let formatter = formatters[pattern] ?? {
            let formatter = DateFormatter()
            formatter.dateFormat = pattern
            formatters[pattern] = formatter
            return formatter
        }()
        return formatter.string(from: Date(timeIntervalSince1970: epochMilliseconds / 1000))
    }
}

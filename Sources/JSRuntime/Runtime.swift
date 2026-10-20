import AppKit
import Compositor
import JavaScriptCore
import Render
import Services

/// What the runtime needs from whoever hosts it: the CLI-controlled visibility of named surfaces.
@MainActor
public protocol RuntimeHost: AnyObject {
    func isHidden(name: String?) -> Bool
    /// An uncaught error or `console.error` from the config, with positions mapped to its own files.
    func report(error: String)
    /// Called when a surface first appears, before it's shown.
    func register(name: String, defaultHidden: Bool)
    /// `show` / `hide` / `toggle` requested by config code.
    func requestVisibility(_ action: String, name: String)
    /// The config's `defineWidget` schemas (JSON keyed by widget name), published after every mount.
    func schemasChanged(_ json: String)
    /// Asked by a built-in app (`halo/internal`'s `close()`) to tear its runtime down.
    func close()
}

extension RuntimeHost {
    public func schemasChanged(_ json: String) {}
    public func close() {}
}

/// One loaded config: a JSContext plus every native object it created, all released by `dispose()`.
@MainActor
public final class Runtime {
    public struct Counts: Equatable, Sendable, CustomStringConvertible {
        public var nodes = 0
        public var surfaces = 0
        public var timers = 0
        public var services = 0
        public var watchers = 0
        public var processes = 0

        public static let zero = Counts()

        public var description: String {
            "\(nodes) nodes, \(surfaces) surfaces, \(timers) timers, \(services) services, \(watchers) watchers, \(processes) processes"
        }
    }

    final class SurfaceEntry {
        let id: Int
        let surface: Surface
        let root: RenderRoot
        var config: SurfaceConfig
        var options: Conversions.SurfaceOptions
        var shown = false
        var exiting = false
        var placedContentSize: CGSize?
        var mouseTransparent = false
        var pressed: Int?
        /// The draggable node under the last mouse-down and where it went down.
        var dragOrigin: (CGPoint, Int)?
        /// The node receiving dragEnter/dragLeave for a file drag over this surface.
        var dragTarget: Int?
        var hovered: Set<Int> = []

        init(id: Int, surface: Surface, root: RenderRoot, config: SurfaceConfig, options: Conversions.SurfaceOptions) {
            self.id = id
            self.surface = surface
            self.root = root
            self.config = config
            self.options = options
        }
    }

    let context: JSContext
    let backend: CompositorBackend
    weak var host: RuntimeHost?
    var screens: [ScreenInfo]
    var nodes: [Int: Node] = [:]
    var nodeIDs: [ObjectIdentifier: Int] = [:]
    var surfaces: [Int: SurfaceEntry] = [:]
    var listeners: [Int: Set<String>] = [:]
    var mouseMonitors: [Any] = []
    var pointerMonitors: [Any] = []
    var placingAttached: Set<Int> = []
    var serviceEntries: [String: ServiceEntry] = [:]
    var serviceSubscriptions: [Int: String] = [:]
    /// Builds native services by name; tests swap in fakes.
    public var serviceFactory: @MainActor (String, [String: Any]) -> Service? = { Services.make($0, options: $1) }
    var frameSubscribers: Set<Int> = []
    var frameLink: CADisplayLink?
    /// Where relative file paths start; nil in tests that load from strings.
    let configDirectory: URL?
    var fileWatchers: [Int: FileWatcher] = [:]
    var pendingFileCallbacks: [Int: JSValue] = [:]
    var spawned: [Int: Spawned] = [:]
    var draggables: [Int: [String]] = [:]
    var ownDragTimer: Timer?
    private var timers: [Int: (timer: Timer, callback: JSValue, repeats: Bool)] = [:]
    private var processes: [Int: (process: Process, callback: JSValue)] = [:]
    private var formatters: [String: DateFormatter] = [:]
    private var lastEvents: [String: [String: String]]
    private var nextID = 1
    private var sourceMap: SourceMap?
    static let bundleName = "halo-bundle.js"
    var disposed = false

    public var counts: Counts {
        Counts(
            nodes: nodes.count, surfaces: surfaces.count, timers: timers.count + frameSubscribers.count,
            services: serviceSubscriptions.count, watchers: fileWatchers.count, processes: spawned.count
        )
    }

    /// `events` holds the latest payload per external event name, so a fresh load starts from known state.
    public init(
        backend: CompositorBackend, screens: [ScreenInfo], events: [String: [String: String]] = [:], host: RuntimeHost? = nil,
        configDirectory: URL? = nil
    ) {
        self.backend = backend
        self.configDirectory = configDirectory
        self.screens = screens
        self.host = host
        lastEvents = events
        context = JSContext()
        context.name = "halo"
        context.exceptionHandler = { [weak self] _, exception in
            guard let exception else { return }
            MainActor.assumeIsolated {
                var message = exception.toString() ?? "unknown error"
                if let line = exception.forProperty("line"), line.isNumber, let column = exception.forProperty("column"), column.isNumber {
                    message += " (\(Runtime.bundleName):\(line.toInt32()):\(column.toInt32()))"
                }
                let stack = exception.forProperty("stack").flatMap { $0.isString ? $0.toString() : nil } ?? ""
                self?.reportError(stack.isEmpty ? message : "\(message)\n\(stack)")
            }
        }
        context.setObject(JSValue(newObjectIn: context), forKeyedSubscript: "__halo" as NSString)
        Bridge.install(in: context, runtime: self)
    }

    public func evaluate(_ script: String, displaySource: (String) -> String = { $0 }) {
        sourceMap = SourceMap(inlineIn: script)?.renamingSources(displaySource)
        context.evaluateScript(script, withSourceURL: URL(string: Self.bundleName))
    }

    /// Maps bundle positions to the config's files, logs, and tells the host (which may show it on screen).
    func reportError(_ text: String) {
        let mapped = sourceMap?.rewrite(text, bundleName: Self.bundleName) ?? text
        Log.error(mapped)
        host?.report(error: mapped)
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

    /// Hands `halo settings` the user config's widget schemas.
    public func deliverSchemas(_ json: String) {
        guard !disposed else { return }
        let hook = context.objectForKeyedSubscript("__halo")?.objectForKeyedSubscript("onSchemas")
        if let hook, !hook.isUndefined { hook.call(withArguments: [json]) }
    }

    /// Surface names currently mounted; `nil` stands for unnamed surfaces.
    public var surfaceNames: Set<String?> {
        Set(surfaces.values.map(\.options.name))
    }

    /// Re-applies host-controlled visibility (after `halo show/hide/toggle`).
    public func refreshVisibility() {
        guard !disposed else { return }
        backend.transaction {
            for entry in surfaces.values { place(entry) }
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
        killSpawned()
        ownDragTimer?.invalidate()
        ownDragTimer = nil
        stopFileWatchers()
        stopMouseMonitors()
        stopPointerMonitors()
        stopServices()
        frameSubscribers.removeAll()
        updateFrameLink()
        backend.transaction {
            for entry in surfaces.values {
                entry.root.detach()
                entry.surface.destroy()
            }
        }
        surfaces.removeAll()
        nodes.removeAll()
        nodeIDs.removeAll()
        listeners.removeAll()
        context.exceptionHandler = nil
        return leftover
    }

    func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Applies config, host visibility and popup attachment; focuses keyboard surfaces as they appear.
    func place(_ entry: SurfaceEntry) {
        var config = entry.config
        let edges = config.anchor
        entry.root.autoWidth = Self.isAuto(config.size.width, stretched: edges.contains(.left) && edges.contains(.right))
        entry.root.autoHeight = Self.isAuto(config.size.height, stretched: edges.contains(.top) && edges.contains(.bottom))
        if entry.root.autoWidth { config.size.width = .fixed(entry.root.contentSize.width) }
        if entry.root.autoHeight { config.size.height = .fixed(entry.root.contentSize.height) }
        entry.placedContentSize = entry.root.contentSize
        config.visible = config.visible && !(host?.isHidden(name: entry.options.name) ?? false)
        // macOS delivers a drop after the mouse-up that ends the drag; hiding the window under it first loses the drop.
        if !config.visible, entry.shown, entry.dragTarget != nil { config.visible = true }
        var frame: CGRect?
        var screen = screens.first { $0.id == config.screen }
        if let attachment = entry.options.attach {
            if let (anchorScreen, anchorFrame) = anchor(of: attachment) {
                screen = anchorScreen
                frame = Placement.frame(
                    size: CGSize(width: fixed(config.size.width), height: fixed(config.size.height)),
                    attachedTo: anchorFrame, side: attachment.side, align: attachment.align,
                    offset: attachment.offset, within: anchorScreen.frame
                )
            } else {
                config.visible = false
            }
        }
        guard let screen else {
            config.visible = false
            if let fallback = screens.first { entry.surface.update(config, screen: fallback) }
            entry.shown = false
            return
        }
        if !config.visible, entry.shown, let exit = entry.options.exit {
            guard !entry.exiting else { return }
            entry.exiting = true
            entry.root.node.play(exit: exit) { [weak self, weak entry] in
                guard let self, let entry, entry.exiting else { return }
                entry.exiting = false
                entry.shown = false
                self.place(entry)
                entry.root.node.clearExit()
            }
            return
        }
        if entry.exiting, config.visible {
            entry.exiting = false
            entry.root.node.clearExit()
        }
        let moved = entry.surface.frame
        entry.surface.update(config, screen: screen, frame: frame)
        entry.root.size = entry.surface.frame.size
        entry.root.contentsScale = screen.scale
        if entry.surface.frame != moved { placeAttached(to: entry) }
        let appeared = config.visible && !entry.shown
        let changed = config.visible != entry.shown
        entry.shown = config.visible
        if changed { updatePointerMonitors() }
        guard appeared else { return }
        // A surface that shows up catches the pointer until the next pointer check says otherwise: a stale
        // click-through state must never let a fresh drop zone pass a drop to the app underneath.
        entry.mouseTransparent = false
        entry.surface.setMouseTransparent(false)
        pointerMoved()
        if let enter = entry.options.enter {
            entry.root.layoutNow()
            entry.root.node.play(enter: enter)
        }
        if config.input == .keyboard { entry.surface.focus() }
    }

    /// Unspecified axes that aren't stretched between two anchors follow the content, like explicit `"auto"`.
    private static func isAuto(_ dimension: Compositor.Dimension?, stretched: Bool) -> Bool {
        dimension == .auto || (dimension == nil && !stretched)
    }

    /// After a layout pass: resize a content-sized surface, move popups attached to it, and refresh what's under a
    /// pointer that didn't move (rows re-rendered beneath it).
    func didLayout(_ entry: SurfaceEntry) {
        guard !disposed, surfaces[entry.id] === entry else { return }
        if (entry.root.autoWidth || entry.root.autoHeight), entry.root.contentSize != entry.placedContentSize {
            place(entry)
        }
        placeAttached(to: entry)
        guard entry.shown, entry.config.input != .passthrough else { return }
        pointerMoved()
        refreshHover(entry)
    }

    /// Popups anchored inside `entry` follow it. Placing one lays out `entry` again, so each is guarded while placed.
    func placeAttached(to entry: SurfaceEntry) {
        for popup in surfaces.values where popup.shown && !placingAttached.contains(popup.id) {
            guard let attachment = popup.options.attach, nodes[attachment.node]?.rootOwner === entry.root else { continue }
            placingAttached.insert(popup.id)
            place(popup)
            placingAttached.remove(popup.id)
        }
    }

    private func fixed(_ dimension: Compositor.Dimension?) -> CGFloat {
        if case .fixed(let value) = dimension { return value }
        return 0
    }

    /// The anchor node's screen and global frame, laying out its surface first so the frame is current.
    private func anchor(of attachment: Conversions.Attachment) -> (ScreenInfo, CGRect)? {
        guard let node = nodes[attachment.node],
              let host = surfaces.values.first(where: { $0.root === node.rootOwner }),
              host.shown,
              let screen = screens.first(where: { $0.id == host.config.screen })
        else { return nil }
        host.root.layoutNow()
        let local = node.frameInRoot
        let origin = host.surface.frame.origin
        return (screen, local.offsetBy(dx: origin.x, dy: origin.y))
    }
}

// MARK: - Bridge operations (called from JS through `Bridge`)

extension Runtime {
    func log(_ level: String, _ message: String) {
        if level == "error" { return reportError("[js] \(message)") }
        Log.write(level == "warn" ? .warn : .info, "[js] \(message)")
    }

    func createNode(_ kind: String) -> Int {
        guard !disposed else { return 0 }
        let id = makeID()
        let node: Node = switch kind {
        case "text": Text("")
        case "image": Image()
        case "shape": Shape()
        case "input": makeInput(id)
        default: Box()
        }
        nodes[id] = node
        nodeIDs[ObjectIdentifier(node)] = id
        return id
    }

    func setStyle(_ id: Int, _ key: String, _ value: JSValue) {
        guard let node = nodes[id] else { return }
        Conversions.applyStyle(key, value, to: node)
    }

    func setProp(_ id: Int, _ key: String, _ value: JSValue) {
        guard let node = nodes[id] else { return }
        if key == "draggable" { return setDraggable(id, value) }
        Conversions.applyProp(key, value, to: node)
    }

    func insert(_ parentID: Int, _ childID: Int, _ index: Int) {
        guard let parent = nodes[parentID], let child = nodes[childID] else { return }
        parent.insert(child, at: index)
    }

    func detach(_ id: Int) {
        nodes[id]?.removeFromParent()
    }

    /// Plays the node's `exit` (if any) before its layer goes away; it leaves the registry immediately.
    func destroyNode(_ id: Int) {
        guard let node = nodes.removeValue(forKey: id) else { return }
        nodeIDs[ObjectIdentifier(node)] = nil
        listeners[id] = nil
        draggables[id] = nil
        node.remove()
    }

    func createSurface(_ rootID: Int, _ configValue: JSValue) -> Int {
        guard !disposed, let node = nodes[rootID], let fallback = screens.first else { return 0 }
        let config = Conversions.surfaceConfig(configValue)
        let options = Conversions.surfaceOptions(configValue)
        if let name = options.name { host?.register(name: name, defaultHidden: options.defaultHidden) }
        var hidden = config
        hidden.visible = false
        let surface = Surface(config: hidden, screen: fallback, backend: backend)
        let root = RenderRoot(node: node, hostLayer: surface.rootLayer, size: surface.frame.size, contentsScale: fallback.scale)
        root.attachView = { [weak surface] view in surface?.attach(view) }
        let id = makeID()
        let entry = SurfaceEntry(id: id, surface: surface, root: root, config: hidden, options: options)
        surfaces[id] = entry
        wireEvents(of: entry)
        root.onLayout = { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.didLayout(entry)
        }
        entry.config = config
        place(entry)
        root.layoutNow()
        return id
    }

    func updateSurface(_ id: Int, _ configValue: JSValue) {
        guard let entry = surfaces[id] else { return }
        entry.config = Conversions.surfaceConfig(configValue)
        entry.options = Conversions.surfaceOptions(configValue)
        place(entry)
    }

    func destroySurface(_ id: Int) {
        guard let entry = surfaces.removeValue(forKey: id) else { return }
        listeners[id] = nil
        entry.root.detach()
        entry.surface.destroy()
        updateMouseMonitors()
        updatePointerMonitors()
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

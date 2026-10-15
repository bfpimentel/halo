import JavaScriptCore

/// Installs `globalThis.__native` (see `runtime/src/native.ts`). Every call arrives on the main thread.
@MainActor
enum Bridge {
    static func install(in context: JSContext, runtime: Runtime) {
        guard let native = JSValue(newObjectIn: context) else { return }
        weak let runtime = runtime

        func define(_ name: String, _ block: Any) {
            native.setObject(block, forKeyedSubscript: name as NSString)
        }

        let log: @convention(block) (String, String) -> Void = { level, message in
            MainActor.assumeIsolated { runtime?.log(level, message) }
        }
        let createNode: @convention(block) (String) -> Int = { kind in
            MainActor.assumeIsolated { runtime?.createNode(kind) ?? 0 }
        }
        let setStyle: @convention(block) (Int, String, JSValue) -> Void = { id, key, value in
            MainActor.assumeIsolated { runtime?.setStyle(id, key, value) }
        }
        let setProp: @convention(block) (Int, String, JSValue) -> Void = { id, key, value in
            MainActor.assumeIsolated { runtime?.setProp(id, key, value) }
        }
        let insert: @convention(block) (Int, Int, Double) -> Void = { parent, child, index in
            MainActor.assumeIsolated { runtime?.insert(parent, child, Int(min(index, Double(Int.max / 2)))) }
        }
        let detach: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated { runtime?.detach(id) }
        }
        let destroyNode: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated { runtime?.destroyNode(id) }
        }
        let createSurface: @convention(block) (Int, JSValue) -> Int = { root, config in
            MainActor.assumeIsolated { runtime?.createSurface(root, config) ?? 0 }
        }
        let updateSurface: @convention(block) (Int, JSValue) -> Void = { id, config in
            MainActor.assumeIsolated { runtime?.updateSurface(id, config) }
        }
        let destroySurface: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated { runtime?.destroySurface(id) }
        }
        let screens: @convention(block) () -> [[String: Any]] = {
            nonisolated(unsafe) var list: [[String: Any]] = []
            MainActor.assumeIsolated { list = runtime?.screenList() ?? [] }
            return list
        }
        let setTimer: @convention(block) (Double, Bool, JSValue) -> Int = { ms, repeats, callback in
            MainActor.assumeIsolated { runtime?.setTimer(ms, repeats, callback) ?? 0 }
        }
        let clearTimer: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated { runtime?.clearTimer(id) }
        }
        let exec: @convention(block) (String, [String], JSValue) -> Void = { command, arguments, callback in
            MainActor.assumeIsolated { runtime?.exec(command, arguments, callback) }
        }
        let lastEvent: @convention(block) (String) -> JSValue? = { name in
            nonisolated(unsafe) var payload: [String: String]?
            MainActor.assumeIsolated { payload = runtime?.lastEvent(name) }
            guard let context = JSContext.current() else { return nil }
            return payload.map { JSValue(object: $0, in: context) } ?? JSValue(nullIn: context)
        }
        let listen: @convention(block) (Int, String, Bool) -> Void = { id, kind, enabled in
            MainActor.assumeIsolated { runtime?.listen(id, kind, enabled) }
        }
        let setVisibility: @convention(block) (String, String) -> Void = { action, name in
            MainActor.assumeIsolated { runtime?.setVisibility(action, name) }
        }
        let focus: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated { runtime?.focusNode(id) }
        }
        let formatDate: @convention(block) (String, Double) -> String = { pattern, ms in
            MainActor.assumeIsolated { runtime?.formatDate(pattern, ms) ?? "" }
        }

        define("log", log)
        define("createNode", createNode)
        define("setStyle", setStyle)
        define("setProp", setProp)
        define("insert", insert)
        define("detach", detach)
        define("destroyNode", destroyNode)
        define("createSurface", createSurface)
        define("updateSurface", updateSurface)
        define("destroySurface", destroySurface)
        define("screens", screens)
        define("setTimer", setTimer)
        define("clearTimer", clearTimer)
        define("exec", exec)
        define("lastEvent", lastEvent)
        define("listen", listen)
        define("setVisibility", setVisibility)
        define("focus", focus)
        define("formatDate", formatDate)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }
}

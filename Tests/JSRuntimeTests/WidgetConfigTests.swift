import AppKit
import Compositor
import Foundation
import QuartzCore
import Testing
@testable import JSRuntime

private func parse(_ json: String) throws -> WidgetConfig {
    try WidgetConfig.parse(Data(json.utf8))
}

private func failure(_ json: String) -> String? {
    do {
        _ = try parse(json)
        return nil
    } catch {
        return "\(error)"
    }
}

struct WidgetConfigTests {
    @Test func decodesScreensAndProps() throws {
        let config = try parse("""
        { "widgets": {
          "b": { "widget": "clock", "screens": [2, 1], "props": { "size": 48, "label": "x" } },
          "a": { "widget": "clock" },
          "c": { "widget": "bar", "screens": "main" }
        } }
        """)
        #expect(config.instances.map(\.name) == ["a", "b", "c"])
        #expect(config.instances[0].screens == .all)
        #expect(config.instances[0].props == "{}")
        #expect(config.instances[1].screens == .indices([2, 1]))
        #expect(config.instances[1].props == #"{"label":"x","size":48}"#)
        #expect(config.instances[2].screens == .main)
    }

    @Test func rejectsInvalidConfigs() {
        #expect(failure("{") != nil)
        #expect(failure("[]")?.contains("must be an object") == true)
        #expect(failure(#"{ "widgets": {} }"#)?.contains("no widgets") == true)
        #expect(failure(#"{ "widgets": { "a": {} } }"#)?.contains("needs \"widget\"") == true)
        #expect(failure(#"{ "widgets": { "a": { "widget": "../x" } } }"#)?.contains("must be a name") == true)
        #expect(failure(#"{ "widgets": { "a": { "widget": "a", "screen": "all" } } }"#)?.contains("unknown field \"screen\"") == true)
        #expect(failure(#"{ "widget": {} }"#)?.contains("unknown field") == true)
        #expect(failure(#"{ "widgets": { "a": { "widget": "a", "screens": [0] } } }"#)?.contains("1-based") == true)
        #expect(failure(#"{ "widgets": { "a": { "widget": "a", "screens": [true] } } }"#)?.contains("1-based") == true)
        #expect(failure(#"{ "widgets": { "a": { "widget": "a", "screens": "left" } } }"#) != nil)
        #expect(failure(#"{ "widgets": { "a": { "widget": "a", "props": [] } } }"#)?.contains("props must be an object") == true)
    }

    @Test func resolvesFilesBeforeFolders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("halo-widgets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let widgets = dir.appendingPathComponent("widgets")
        try FileManager.default.createDirectory(at: widgets.appendingPathComponent("bar"), withIntermediateDirectories: true)
        try "".write(to: widgets.appendingPathComponent("bar/index.tsx"), atomically: true, encoding: .utf8)
        try "".write(to: widgets.appendingPathComponent("clock.tsx"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: widgets.appendingPathComponent("clock"), withIntermediateDirectories: true)
        try "".write(to: widgets.appendingPathComponent("clock/index.tsx"), atomically: true, encoding: .utf8)

        let config = try parse(#"{ "widgets": { "a": { "widget": "bar" }, "b": { "widget": "clock", "screens": [1] }, "c": { "widget": "gone" } } }"#)
        #expect(try config.resolve(config.instances[0], configDirectory: dir).path.hasSuffix("widgets/bar/index.tsx"))
        #expect(try config.resolve(config.instances[1], configDirectory: dir).path.hasSuffix("widgets/clock.tsx"))
        #expect(throws: WidgetConfig.Failure.self) { try config.resolve(config.instances[2], configDirectory: dir) }

        let entry = try WidgetConfig(instances: Array(config.instances.prefix(2))).entrySource(configDirectory: dir)
        #expect(entry.contains(#"{ name: "a", widget: "bar", load: () => require(""#))
        #expect(entry.contains(#"widgets/clock.tsx").default, screens: [1], props: {} }"#))
    }

    @Test func missingHaloJsonPointsAtInit() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("halo-empty-\(UUID().uuidString)")
        #expect(throws: WidgetConfig.Failure(description: "no halo.json in \(dir.path); run `halo init` to create one")) {
            try WidgetConfig.load(configDirectory: dir)
        }
    }
}

@MainActor
private final class SchemaHost: RuntimeHost {
    var schemas: [String] = []
    var errors: [String] = []
    func isHidden(name: String?) -> Bool { false }
    func report(error: String) { errors.append(error) }
    func register(name: String, defaultHidden: Bool) {}
    func requestVisibility(_ action: String, name: String) {}
    func schemasChanged(_ json: String) { schemas.append(json) }
}

@MainActor
private final class CountingBackend: CompositorBackend {
    var liveSurfaces = 0

    func makeSurface() -> BackendSurface {
        liveSurfaces += 1
        return CountedSurface(backend: self)
    }

    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class CountedSurface: BackendSurface {
    let rootLayer = CALayer()
    private weak var backend: CountingBackend?

    init(backend: CountingBackend) { self.backend = backend }

    var onEvent: ((SurfaceEvent) -> Void)?
    var onKey: ((KeyEvent) -> Bool)?
    func focus() {}
    func attach(_ view: NSView) {}
    func setFrame(_ frame: CGRect) {}
    func setLayer(_ layer: SurfaceLayer) {}
    func setInput(_ input: InputPolicy) {}
    func setMouseTransparent(_ transparent: Bool) {}
    func setVisible(_ visible: Bool) {}
    func destroy() { backend?.liveSurfaces -= 1 }
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/widgets")
private let first = ScreenInfo(id: 1, name: "First", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), index: 1)
private let second = ScreenInfo(id: 2, name: "Second", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), index: 2)

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct WidgetMountTests {
    /// Broken widgets (one at module level, one in render) don't stop the others; shared modules evaluate once;
    /// an invalid prop falls back to its schema default and is reported; schemas reach the host.
    @Test func instancesMountIndependentlyOnTheirScreens() throws {
        let script = try Bundler.locate().build(configDirectory: fixture)
        let backend = CountingBackend()
        let host = SchemaHost()
        let runtime = Runtime(backend: backend, screens: [first, second], host: host)
        runtime.evaluate(script)

        #expect(runtime.context.evaluateScript("__test.evaluations").toInt32() == 1)
        #expect(runtime.context.evaluateScript("__test.mounted.join(',')").toString()
            == "both@1,both@2,throws-at-load evaluated,none@2,left@1,main@1")
        #expect(backend.liveSurfaces == 5)
        #expect(host.schemas == [#"{"panel":{"label":{"type":"string","default":"none"}}}"#])
        #expect(host.errors.contains { $0.contains(#"widget "defaulted": props.label must be a string, got 5; using "none""#) })

        runtime.screensChanged([second])
        #expect(backend.liveSurfaces == 2)

        #expect(runtime.dispose() == .zero)
        #expect(backend.liveSurfaces == 0)
    }
}

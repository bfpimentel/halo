import AppKit
import Compositor
import Foundation
import QuartzCore
import Testing
@testable import JSRuntime

@MainActor
private final class Backend: CompositorBackend {
    var liveSurfaces = 0

    func makeSurface() -> BackendSurface {
        liveSurfaces += 1
        return Panel(backend: self)
    }

    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class Panel: BackendSurface {
    let rootLayer = CALayer()
    private weak var backend: Backend?

    init(backend: Backend) { self.backend = backend }

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

@MainActor
private final class Host: RuntimeHost {
    var closed = 0
    func isHidden(name: String?) -> Bool { false }
    func report(error: String) { Issue.record("settings reported \(error)") }
    func register(name: String, defaultHidden: Bool) {}
    func requestVisibility(_ action: String, name: String) {}
    func close() { closed += 1 }
}

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct SettingsTests {
    /// The editor reads the user's halo.json and widgets/, asks its host to close, and leaves nothing behind.
    @Test func editorLoadsTheConfigAndClosesCleanly() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("halo-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("widgets"), withIntermediateDirectories: true)
        try #"{ "widgets": { "clock": { "widget": "clock", "props": { "size": 20 } } } }"#
            .write(to: dir.appendingPathComponent("halo.json"), atomically: true, encoding: .utf8)
        try "export default () => null;".write(to: dir.appendingPathComponent("widgets/clock.tsx"), atomically: true, encoding: .utf8)

        let backend = Backend()
        let host = Host()
        let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let runtime = Runtime(backend: backend, screens: [screen], host: host, configDirectory: dir)
        runtime.evaluate(try Bundler.locate().buildSettings(configDirectory: dir))
        #expect(backend.liveSurfaces == 1)

        let deadline = Date().addingTimeInterval(5)
        while runtime.counts.nodes < 30, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(runtime.counts.nodes >= 30, "the instance list and its props rendered from halo.json")
        #expect(runtime.counts.watchers == 1)

        runtime.context.evaluateScript("__native.close()")
        #expect(host.closed == 1)
        #expect(runtime.dispose() == .zero)
        #expect(backend.liveSurfaces == 0)
    }
}

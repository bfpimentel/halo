import AppKit
import Compositor
import Foundation
import Services
import Testing
@testable import JSRuntime

@MainActor
private final class FakeService: Service {
    var starts = 0
    var stops = 0
    var publish: (@MainActor ([String: Any]) -> Void)?

    func start(publish: @escaping @MainActor ([String: Any]) -> Void) {
        starts += 1
        self.publish = publish
        publish(["present": true, "percent": 80])
    }

    func stop() {
        stops += 1
        publish = nil
    }
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/services")
private let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct ServiceTests {
    private func texts(_ runtime: Runtime) -> [String] {
        func walk(_ node: [String: Any]) -> [String] {
            ((node["text"] as? String).map { [$0] } ?? []) + ((node["children"] as? [[String: Any]]) ?? []).flatMap(walk)
        }
        let surfaces = runtime.inspect()["surfaces"] as? [[String: Any]] ?? []
        return surfaces.compactMap { $0["root"] as? [String: Any] }.flatMap(walk)
    }

    /// A service starts with its first reader, survives readers re-running, and stops with its last reader.
    @Test func servicesRunOnlyWhileRead() throws {
        let fake = FakeService()
        let runtime = Runtime(backend: NoSurfacesBackend(), screens: [screen])
        runtime.serviceFactory = { name, _ in name == "battery" ? fake : nil }
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        #expect(fake.starts == 1)
        #expect(texts(runtime) == ["80%"])

        fake.publish?(["present": true, "percent": 42])
        #expect(texts(runtime) == ["42%"])
        #expect(fake.starts == 1 && fake.stops == 0)

        runtime.context.evaluateScript("__test.show(false)")
        #expect(fake.stops == 1)
        #expect(runtime.counts.services == 0)

        runtime.context.evaluateScript("__test.show(true)")
        #expect(fake.starts == 2)
        #expect(runtime.dispose() == .zero)
        #expect(fake.stops == 2)
    }
}

@MainActor
final class NoSurfacesBackend: CompositorBackend {
    func makeSurface() -> BackendSurface { FakeBackendSurface() }
    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class FakeBackendSurface: BackendSurface {
    let rootLayer = CALayer()
    var onEvent: ((SurfaceEvent) -> Void)?
    var onKey: ((KeyEvent) -> Bool)?
    func setFrame(_ frame: CGRect) {}
    func setLayer(_ layer: SurfaceLayer) {}
    func setInput(_ input: InputPolicy) {}
    func setMouseTransparent(_ transparent: Bool) {}
    func setVisible(_ visible: Bool) {}
    func focus() {}
    func attach(_ view: NSView) {}
    func destroy() {}
}

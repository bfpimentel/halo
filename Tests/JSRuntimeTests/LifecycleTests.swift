import Compositor
import Foundation
import QuartzCore
import Testing
@testable import JSRuntime

@MainActor
private final class FakeBackend: CompositorBackend {
    var liveSurfaces = 0

    func makeSurface() -> BackendSurface {
        liveSurfaces += 1
        return FakeSurface(backend: self)
    }

    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class FakeSurface: BackendSurface {
    let rootLayer = CALayer()
    private weak var backend: FakeBackend?

    init(backend: FakeBackend) { self.backend = backend }

    func setFrame(_ frame: CGRect) {}
    func setLayer(_ layer: SurfaceLayer) {}
    func setInput(_ input: InputPolicy) {}
    func setVisible(_ visible: Bool) {}
    func destroy() { backend?.liveSurfaces -= 1 }
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/lifecycle")
private let left = ScreenInfo(id: 1, name: "Left", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
private let right = ScreenInfo(id: 2, name: "Right", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct LifecycleTests {
    /// Per screen: root box, clock text, 3 item texts, image = 6 nodes; 1 surface; 1 interval. Plus 1 shared clock ticker.
    @Test func configCleanupsReleaseEverythingTheyCreated() throws {
        let script = try Bundler.locate().build(configDirectory: fixture)
        let backend = FakeBackend()
        let runtime = Runtime(backend: backend, screens: [left, right])
        runtime.evaluate(script)
        #expect(runtime.counts == Runtime.Counts(nodes: 12, surfaces: 2, timers: 3))

        runtime.context.evaluateScript("__test.setItems(1)")
        #expect(runtime.counts.nodes == 8)

        runtime.screensChanged([left])
        #expect(runtime.counts == Runtime.Counts(nodes: 4, surfaces: 1, timers: 2))
        #expect(backend.liveSurfaces == 1)

        #expect(runtime.dispose() == .zero)
        #expect(backend.liveSurfaces == 0)
    }

    @Test func reloadingRepeatedlyLeavesNothingBehind() throws {
        let script = try Bundler.locate().build(configDirectory: fixture)
        let backend = FakeBackend()
        for _ in 0..<5 {
            let runtime = Runtime(backend: backend, screens: [left, right])
            runtime.evaluate(script)
            #expect(runtime.dispose() == .zero)
        }
        #expect(backend.liveSurfaces == 0)
    }
}

import AppKit
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

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/lifecycle")
private let left = ScreenInfo(id: 1, name: "Left", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
private let right = ScreenInfo(id: 2, name: "Right", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct LifecycleTests {
    /// Per screen: root box, clock text, 3 item texts, image = 6 nodes; 1 surface; 1 interval.
    /// Shared: the seconds ticker, plus module-level code's minute ticker and interval.
    @Test func configCleanupsReleaseEverythingTheyCreated() throws {
        let script = try Bundler.locate().build(configDirectory: fixture)
        let backend = FakeBackend()
        let runtime = Runtime(backend: backend, screens: [left, right])
        runtime.evaluate(script)
        #expect(runtime.counts == Runtime.Counts(nodes: 12, surfaces: 2, timers: 5))

        runtime.context.evaluateScript("__test.setItems(1)")
        #expect(runtime.counts.nodes == 8)

        runtime.screensChanged([left])
        #expect(runtime.counts == Runtime.Counts(nodes: 4, surfaces: 1, timers: 4))
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

    /// An unanchored-axis surface takes its content's size and follows it; its empty padding lets clicks through.
    @Test func contentSizedSurfacesFollowTheirContent() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/autosize")
        let runtime = Runtime(backend: FakeBackend(), screens: [left])
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        let entry = try #require(runtime.surfaces.values.first)
        #expect(entry.surface.frame.size == CGSize(width: 140, height: 50))

        runtime.context.evaluateScript("__test.setRows(3)")
        entry.root.layoutNow()
        #expect(entry.surface.frame.size == CGSize(width: 140, height: 78))
        #expect(entry.surface.frame.minX == CGFloat(1512 - 140) / 2)

        #expect(!runtime.isSolid(entry, at: CGPoint(x: 5, y: 5)))
        #expect(runtime.isSolid(entry, at: CGPoint(x: 30, y: 30)))
        runtime.dispose()
    }

    @Test func attachedPopupsFollowTheirAnchor() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/popup")
        let runtime = Runtime(backend: FakeBackend(), screens: [left])
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        let popup = try #require(runtime.surfaces.values.first { $0.options.attach != nil })
        let bar = try #require(runtime.surfaces.values.first { $0.options.attach == nil })
        #expect(popup.surface.frame == CGRect(x: 0, y: 44, width: 100, height: 60))

        runtime.context.evaluateScript("__test.shift(120)")
        bar.root.layoutNow()
        #expect(popup.surface.frame == CGRect(x: 120, y: 44, width: 100, height: 60))
        runtime.dispose()
    }
}

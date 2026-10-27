import AppKit
import Compositor
import Foundation
import QuartzCore
import Testing
@testable import JSRuntime

@MainActor
private final class HoverBackend: CompositorBackend {
    var surfaces: [HoverSurface] = []

    func makeSurface() -> BackendSurface {
        let surface = HoverSurface()
        surfaces.append(surface)
        return surface
    }

    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class HoverSurface: BackendSurface {
    let rootLayer = CALayer()
    var onEvent: ((SurfaceEvent) -> Void)?
    var onKey: ((KeyEvent) -> Bool)?
    var covered = false
    var coverChecks = 0
    var transparent = false

    func isCovered(at point: CGPoint) -> Bool {
        coverChecks += 1
        return covered
    }

    func focus() {}
    func attach(_ view: NSView) {}
    func setFrame(_ frame: CGRect) {}
    func setLayer(_ layer: SurfaceLayer) {}
    func setInput(_ input: InputPolicy) {}
    func setMouseTransparent(_ transparent: Bool) { self.transparent = transparent }
    func setVisible(_ visible: Bool) {}
    func destroy() {}
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/hover")
private let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct HoverTests {
    private func load() throws -> (Runtime, HoverSurface, Pointer) {
        let backend = HoverBackend()
        let runtime = Runtime(backend: backend, screens: [screen])
        let pointer = Pointer()
        runtime.pointerLocation = { pointer.location }
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        return (runtime, try #require(backend.surfaces.last), pointer)
    }

    private func log(_ runtime: Runtime) -> [String] {
        runtime.context.evaluateScript("__test.log").toArray().compactMap { $0 as? String }
    }

    /// Lets the main-queue pointer checks queued by placement and layout run.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(20))
    }

    @Test func hoverFollowsThePointerWithoutPanelEvents() async throws {
        let (runtime, _, pointer) = try load()
        try await settle()
        pointer.location = CGPoint(x: 50, y: 50)
        runtime.pointerMoved()
        pointer.location = CGPoint(x: 150, y: 50)
        runtime.pointerMoved()
        pointer.location = CGPoint(x: 250, y: 50)
        runtime.pointerMoved()
        #expect(log(runtime) == ["a true", "a false", "b true", "b false"])
        runtime.dispose()
    }

    @Test func coverIsCheckedOnlyWhenTheHoveredSetChanges() async throws {
        let (runtime, surface, pointer) = try load()
        try await settle()
        for x in stride(from: 10, through: 90, by: 10) {
            pointer.location = CGPoint(x: x, y: 50)
            runtime.pointerMoved()
        }
        #expect(surface.coverChecks == 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(surface.coverChecks == 2, "the settled pointer is checked once more")
        #expect(log(runtime) == ["a true"])
        runtime.dispose()
    }

    @Test func aCoveredSurfaceGetsNoHover() async throws {
        let (runtime, surface, pointer) = try load()
        try await settle()
        surface.covered = true
        pointer.location = CGPoint(x: 50, y: 50)
        runtime.pointerMoved()
        #expect(log(runtime).isEmpty)
        surface.covered = false
        runtime.pointerMoved()
        #expect(log(runtime) == ["a true"])
        runtime.dispose()
    }

    @Test func hidingEndsHoverAfterTheEffectsRun() async throws {
        let (runtime, _, pointer) = try load()
        try await settle()
        pointer.location = CGPoint(x: 50, y: 50)
        runtime.pointerMoved()
        runtime.context.evaluateScript("__test.hide()")
        #expect(log(runtime) == ["a true"], "hover handlers don't run inside the effect that hid the surface")
        try await settle()
        #expect(log(runtime) == ["a true", "a false"])
        runtime.dispose()
    }

    @Test func aRowReRenderedUnderAStillPointerIsHovered() async throws {
        let (runtime, _, pointer) = try load()
        try await settle()
        pointer.location = CGPoint(x: 50, y: 50)
        runtime.pointerMoved()
        runtime.context.evaluateScript("__test.rerender()")
        try await settle()
        #expect(log(runtime) == ["a true", "a1 true"])
        runtime.dispose()
    }

    @Test func clickThroughFollowsAnInputSwitchBeforeThePointerCheck() async throws {
        let (runtime, surface, pointer) = try load()
        let entry = try #require(runtime.surfaces.values.first)
        pointer.location = CGPoint(x: 250, y: 50)
        try await settle()
        #expect(surface.transparent)

        runtime.context.evaluateScript("__test.setInput('keyboard')")
        #expect(!entry.mouseTransparent, "a new input policy resets the panel's click-through")
        try await settle()
        #expect(entry.mouseTransparent)
        #expect(surface.transparent)
        runtime.dispose()
    }
}

@MainActor
private final class Pointer {
    var location = CGPoint(x: -1, y: -1)
}

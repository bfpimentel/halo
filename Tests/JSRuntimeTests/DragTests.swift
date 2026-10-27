import AppKit
import Compositor
import Foundation
import QuartzCore
import Services
import Testing
@testable import JSRuntime

@MainActor
private final class DragBackend: CompositorBackend {
    var surfaces: [DragSurface] = []

    func makeSurface() -> BackendSurface {
        let surface = DragSurface()
        surfaces.append(surface)
        return surface
    }

    func transaction(_ body: () -> Void) { body() }
}

@MainActor
private final class DragSurface: BackendSurface {
    let rootLayer = CALayer()
    var onEvent: ((SurfaceEvent) -> Void)?
    var onKey: ((KeyEvent) -> Bool)?
    var onDrag: ((DragEvent) -> Bool)?
    var dragged: [[String]] = []
    var visible = false

    func beginDrag(files: [String]) { dragged.append(files) }
    func focus() {}
    func attach(_ view: NSView) {}
    func setFrame(_ frame: CGRect) {}
    func setLayer(_ layer: SurfaceLayer) {}
    func setInput(_ input: InputPolicy) {}
    func setMouseTransparent(_ transparent: Bool) {}
    func setVisible(_ visible: Bool) { self.visible = visible }
    func destroy() {}
}

@MainActor
private final class FakeDragService: Service {
    var actions: [String] = []
    func start(publish: @escaping @MainActor ([String: Any]) -> Void) { publish(["active": false, "outgoing": false]) }
    func stop() {}
    func perform(_ action: String, _ value: Any?) -> Bool {
        actions.append(action)
        return true
    }
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/drag")
private let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct DragTests {
    private func load(drag: FakeDragService = FakeDragService()) throws -> (Runtime, DragSurface) {
        let backend = DragBackend()
        let runtime = Runtime(backend: backend, screens: [screen])
        runtime.serviceFactory = { name, _ in name == "drag" ? drag : nil }
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        return (runtime, try #require(backend.surfaces.last))
    }

    private func log(_ runtime: Runtime) -> [String] {
        runtime.context.evaluateScript("__test.log").toArray().compactMap { $0 as? String }
    }

    @Test func dropsRouteEnterLeaveAndDropToTheZoneUnderThePointer() throws {
        let (runtime, surface) = try load()
        let files = ["/Users/me/report.pdf", "/Users/me/photo.png"]
        let drag = try #require(surface.onDrag)

        #expect(drag(.over(CGPoint(x: 150, y: 50), files: files)) == false, "no drop zone at the draggable item")
        #expect(drag(.over(CGPoint(x: 40, y: 50), files: files)) == true)
        #expect(drag(.over(CGPoint(x: 60, y: 60), files: files)) == true, "moving inside the zone doesn't re-enter")
        #expect(drag(.over(CGPoint(x: 150, y: 50), files: files)) == false)
        _ = drag(.over(CGPoint(x: 40, y: 50), files: files))
        #expect(drag(.drop(CGPoint(x: 40, y: 50), files: files)) == true)
        #expect(log(runtime) == [
            "enter /Users/me/report.pdf,/Users/me/photo.png", "leave",
            "enter /Users/me/report.pdf,/Users/me/photo.png", "leave",
            "drop /Users/me/report.pdf,/Users/me/photo.png @40,50",
        ])
        #expect(drag(.drop(CGPoint(x: 150, y: 50), files: files)) == false, "dropping elsewhere is refused")
        runtime.dispose()
    }

    @Test func dropZonesAndDraggableItemsCatchThePointer() throws {
        let (runtime, _) = try load()
        let entry = try #require(runtime.surfaces.values.first)
        #expect(runtime.isSolid(entry.root.hitPath(at: CGPoint(x: 40, y: 50))), "an unpainted drop zone still takes the drop")
        #expect(runtime.isSolid(entry.root.hitPath(at: CGPoint(x: 150, y: 50))))
        #expect(runtime.dispose() == .zero)
    }

    @Test func draggingAnItemStartsAFileDragAndCancelsItsClick() throws {
        let (runtime, surface) = try load()
        let emit = try #require(surface.onEvent)

        emit(.mouseDown(CGPoint(x: 150, y: 50), button: 0))
        emit(.mouseDragged(CGPoint(x: 152, y: 51)))
        #expect(surface.dragged.isEmpty, "under 4 points is still a click")
        emit(.mouseDragged(CGPoint(x: 160, y: 50)))
        emit(.mouseUp(CGPoint(x: 160, y: 50), button: 0, clickCount: 1))
        #expect(surface.dragged == [["/tmp/a.txt", "/tmp/b.png"]])
        #expect(log(runtime).isEmpty, "the drag swallowed the click")

        emit(.mouseDown(CGPoint(x: 150, y: 50), button: 0))
        emit(.mouseUp(CGPoint(x: 150, y: 50), button: 0, clickCount: 1))
        #expect(log(runtime) == ["click"])

        runtime.context.evaluateScript("__test.clearDraggable()")
        emit(.mouseDown(CGPoint(x: 150, y: 50), button: 0))
        emit(.mouseDragged(CGPoint(x: 170, y: 50)))
        #expect(surface.dragged.count == 1, "no files, no drag")
        runtime.dispose()
    }

    @Test func aSurfaceUnderAFileDragStaysUntilTheDropLands() async throws {
        let (runtime, surface) = try load()
        let drag = try #require(surface.onDrag)
        let files = ["/Users/me/report.pdf"]
        #expect(drag(.over(CGPoint(x: 40, y: 50), files: files)))

        runtime.context.evaluateScript("__test.hide()")
        #expect(surface.visible, "hiding waits: macOS delivers the drop after the mouse-up")
        #expect(drag(.drop(CGPoint(x: 40, y: 50), files: files)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!surface.visible)
        #expect(log(runtime).last == "drop /Users/me/report.pdf @40,50")
        runtime.dispose()
    }

    @Test func dragsHaloStartsAreMarkedOutgoing() throws {
        let service = FakeDragService()
        let (runtime, surface) = try load(drag: service)
        let emit = try #require(surface.onEvent)
        emit(.mouseDown(CGPoint(x: 150, y: 50), button: 0))
        emit(.mouseDragged(CGPoint(x: 170, y: 50)))
        #expect(service.actions == ["outgoing"])
        runtime.dispose()
    }
}

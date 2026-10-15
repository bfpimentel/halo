import Compositor
import Foundation
import QuartzCore
import Testing
@testable import JSRuntime

@MainActor
private final class NoSurfaces: CompositorBackend {
    func makeSurface() -> BackendSurface { fatalError("the fixture creates no surfaces") }
    func transaction(_ body: () -> Void) { body() }
}

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/external")
private let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct ExternalSignalTests {
    private func seen(_ runtime: Runtime) -> [String] {
        runtime.context.evaluateScript("__test.seen").toArray().compactMap { $0 as? String }
    }

    @Test func eventsUpdateTheSignalAndUnparsableOnesAreIgnored() throws {
        let runtime = Runtime(backend: NoSurfaces(), screens: [screen])
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))

        runtime.deliver(event: "ws", payload: ["focused": "2"])
        runtime.deliver(event: "other", payload: ["focused": "9"])
        runtime.deliver(event: "ws", payload: ["prev": "2"])
        #expect(seen(runtime) == ["none", "2"])
        runtime.dispose()
    }

    @Test func aReloadedConfigStartsFromTheLastPayload() throws {
        let runtime = Runtime(backend: NoSurfaces(), screens: [screen], events: ["ws": ["focused": "B"]])
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))
        #expect(seen(runtime) == ["B"])
        runtime.dispose()
    }
}

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

private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/io")
private let screen = ScreenInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

@MainActor
@Suite(.enabled(if: (try? Bundler.locate()) != nil, "needs esbuild"))
struct IOTests {
    private func state(_ runtime: Runtime) -> [String: Any] {
        runtime.context.evaluateScript("__test").toDictionary() as? [String: Any] ?? [:]
    }

    private func strings(_ runtime: Runtime, _ key: String) -> [String] {
        (state(runtime)[key] as? [Any] ?? []).map { $0 is NSNull ? "<none>" : "\($0)" }
    }

    /// Sleeps instead of spinning the run loop: the test itself runs as a main-queue job, so only suspending it lets
    /// the main-queue deliveries (file reads, process output) run.
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return condition()
    }

    @Test func filesAndProcessesStreamAndAreReleasedWithTheConfig() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("halo-io-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        let watched = dir.appendingPathComponent("watched.txt")

        let runtime = Runtime(backend: NoSurfaces(), screens: [screen], configDirectory: dir)
        runtime.context.evaluateScript("globalThis.__input = { dir: \"\(dir.path)\" }")
        runtime.evaluate(try Bundler.locate().build(configDirectory: fixture))

        #expect(await waitUntil { strings(runtime, "exits") == ["3"] })
        #expect(strings(runtime, "lines") == ["a", "b", "c"])
        #expect(strings(runtime, "errors") == ["oops"])
        #expect(await waitUntil { state(runtime)["read"] as? String == "hello" })
        #expect(await waitUntil { state(runtime)["written"] as? Bool == true })
        #expect(try String(contentsOf: dir.appendingPathComponent("nested/out.txt"), encoding: .utf8) == "hi")
        #expect(await waitUntil { strings(runtime, "failures") == ["missing"] })

        #expect(await waitUntil { strings(runtime, "watched") == ["<none>"] })
        try "one".write(to: watched, atomically: true, encoding: .utf8)
        #expect(await waitUntil { strings(runtime, "watched").last == "one" })
        let handle = try FileHandle(forWritingTo: watched)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" two".utf8))
        try handle.close()
        #expect(await waitUntil { strings(runtime, "watched").last == "one two" })
        try FileManager.default.removeItem(at: watched)
        #expect(await waitUntil { strings(runtime, "watched").last == "<none>" })

        #expect(await waitUntil { !strings(runtime, "background").isEmpty })
        let sleeper = try #require(Int32(strings(runtime, "background").first ?? ""))
        #expect(runtime.counts.watchers == 1 && runtime.counts.processes == 1)

        #expect(runtime.dispose() == .zero)
        #expect(await waitUntil { kill(sleeper, 0) != 0 }, "the background sleep in the killed process group is gone")
    }
}

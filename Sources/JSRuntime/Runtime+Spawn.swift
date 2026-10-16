import Darwin
import Foundation
import JavaScriptCore

/// `spawn` (see `runtime/src/host.ts`): a long-running program whose stdout/stderr arrive line by line.
extension Runtime {
    final class Spawned {
        let pid: pid_t
        let onLines: JSValue
        let onExit: JSValue

        init(pid: pid_t, onLines: JSValue, onExit: JSValue) {
            self.pid = pid
            self.onLines = onLines
            self.onExit = onExit
        }

        /// The child leads its own process group, so this also stops what it started (`sh -c "a | b"`).
        func kill() {
            Darwin.kill(-pid, SIGTERM)
        }
    }

    /// Returns 0 when the program can't start; `onExit(-1, reason)` has been called by then.
    func spawn(_ command: String, _ arguments: [String], _ onLines: JSValue, _ onExit: JSValue) -> Int {
        guard !disposed else { return 0 }
        let argv = command.contains("/") ? [command] + arguments : ["/usr/bin/env", command] + arguments
        guard let child = Self.launch(argv) else {
            onExit.call(withArguments: [-1, "can't start \(command): \(String(cString: strerror(errno)))"])
            return 0
        }
        let id = makeID()
        spawned[id] = Spawned(pid: child.pid, onLines: onLines, onExit: onExit)

        let deliver: @Sendable (String, [String]) -> Void = { [weak self] stream, lines in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let entry = self.spawned[id] else { return }
                    entry.onLines.call(withArguments: [stream, lines])
                }
            }
        }
        offMain({ Self.drainAndWait(child, deliver) }, then: { [weak self] code in
            guard let self, let entry = self.spawned.removeValue(forKey: id) else { return }
            entry.onExit.call(withArguments: [code, NSNull()])
        })
        return id
    }

    /// Stops the program; its remaining output and exit are dropped.
    func kill(_ id: Int) {
        spawned.removeValue(forKey: id)?.kill()
    }

    func killSpawned() {
        for entry in spawned.values { entry.kill() }
        spawned.removeAll()
    }

    /// Reads both pipes to EOF (delivering lines as they come), then reaps the child. Returns its exit code,
    /// negative for a signal.
    private nonisolated static func drainAndWait(_ child: Child, _ deliver: @escaping @Sendable (String, [String]) -> Void) -> Int {
        let stderrDone = DispatchGroup()
        stderrDone.enter()
        DispatchQueue.global(qos: .utility).async {
            readLines(child.stderr) { deliver("err", $0) }
            stderrDone.leave()
        }
        readLines(child.stdout) { deliver("out", $0) }
        stderrDone.wait()
        var status: Int32 = 0
        waitpid(child.pid, &status, 0)
        return (status & 0x7f) == 0 ? Int((status >> 8) & 0xff) : -Int(status & 0x7f)
    }

    private struct Child: Sendable {
        let pid: pid_t
        let stdout: Int32
        let stderr: Int32
    }

    /// stdin is /dev/null; every other descriptor of ours stays closed in the child.
    private static func launch(_ argv: [String]) -> Child? {
        var out: [Int32] = [0, 0]
        var err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { return nil }
        guard pipe(&err) == 0 else {
            close(out[0]); close(out[1])
            return nil
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, out[1], 1)
        posix_spawn_file_actions_adddup2(&actions, err[1], 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        let cArguments = argv.map { strdup($0) } + [nil]
        defer { cArguments.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, argv[0], &actions, &attributes, cArguments, environ)
        close(out[1])
        close(err[1])
        guard status == 0 else {
            close(out[0]); close(err[0])
            errno = status
            return nil
        }
        return Child(pid: pid, stdout: out[0], stderr: err[0])
    }

    /// Blocks until EOF, handing over complete lines (without "\n" or "\r\n") as they arrive.
    private nonisolated static func readLines(_ fd: Int32, _ deliver: ([String]) -> Void) {
        defer { close(fd) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: buffer[0..<count])
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(line(pending[pending.startIndex..<newline]))
                pending.removeSubrange(pending.startIndex...newline)
            }
            if !lines.isEmpty { deliver(lines) }
        }
        if !pending.isEmpty { deliver([line(pending)]) }
    }

    private nonisolated static func line(_ bytes: Data) -> String {
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}

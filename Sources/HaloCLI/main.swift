import Darwin
import Foundation
import HaloHost
import IPC

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("halo: \(message)\n".utf8))
    exit(code)
}

func send(_ request: Request) -> Never {
    let path = IPC.socketPath
    let fd: Int32
    do {
        fd = try UnixSocket.connect(to: path)
    } catch {
        fail("halo is not running (nothing listening at \(path)); start it with `halo start`")
    }
    do {
        try UnixSocket.writeAll(fd, IPC.encode(request))
        let response = try IPC.decode(Response.self, from: UnixSocket.readLine(fd))
        close(fd)
        if let output = response.output { print(output) }
        if response.ok { exit(0) }
        fail(response.error ?? "request failed")
    } catch {
        fail("\(error)")
    }
}

func followLog() -> Never {
    let path = IPC.logPath
    guard FileManager.default.fileExists(atPath: path) else { fail("no log yet at \(path)") }
    let arguments = ["tail", "-n", "200", "-F", path]
    var cArguments = arguments.map { strdup($0) } + [nil]
    execv("/usr/bin/tail", &cArguments)
    fail("could not run tail: \(String(cString: strerror(errno)))")
}

let command: Command
do {
    command = try IPC.parse(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)", code: 64)
}

switch command {
case .initialize(let directory):
    do {
        let created = try initializeConfig(at: directory)
        print(created.isEmpty ? "nothing to do: the files already exist" : created.map { "created \($0)" }.joined(separator: "\n"))
    } catch {
        fail("\(error)")
    }
case .start(let config):
    MainActor.assumeIsolated { runHost(configPath: config) }
case .send(let request):
    send(request)
case .log:
    followLog()
case .help:
    print(IPC.usage)
}

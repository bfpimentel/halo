import AppKit
import IPC
import JSRuntime

/// `halo start`: runs the host in the foreground until `halo quit`, SIGINT or SIGTERM.
@MainActor
public func runHost(configPath: String?) -> Never {
    let directory = configPath.map { URL(fileURLWithPath: $0).standardizedFileURL } ?? defaultConfigDirectory()
    guard FileManager.default.fileExists(atPath: directory.path) else {
        Log.error("config directory \(directory.path) does not exist (create one with `halo init`, or pass --config <dir>)")
        exit(1)
    }

    let bundler: Bundler
    do {
        bundler = try Bundler.locate()
    } catch {
        Log.error("\(error)")
        exit(1)
    }

    if UnixSocket.isLive(IPC.socketPath) {
        Log.error("another halo host is already running (\(IPC.socketPath)); stop it with `halo quit`")
        exit(1)
    }
    Log.mirror(to: IPC.logPath)
    Log.info("halo \(IPC.version) · config \(directory.path) · runtime \(bundler.runtimeSources.path) · esbuild \(bundler.esbuild.path)")
    signal(SIGPIPE, SIG_IGN)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let host = Host(configDirectory: directory, bundler: bundler)
    do {
        try host.start(socketPath: IPC.socketPath)
    } catch {
        Log.error("\(error)")
        exit(1)
    }

    let signalSources = [SIGINT, SIGTERM].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { host.shutdown() }
            exit(0)
        }
        source.resume()
        return source
    }
    withExtendedLifetime(signalSources) {
        app.run()
    }
    exit(0)
}

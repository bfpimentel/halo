import AppKit
import JSRuntime

func configDirectory() -> URL {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--config"), arguments.indices.contains(flag + 1) {
        return URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
    }
    let environment = ProcessInfo.processInfo.environment
    let base = environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    return base.appendingPathComponent("halo")
}

let directory = configDirectory()
guard FileManager.default.fileExists(atPath: directory.path) else {
    Log.error("config directory \(directory.path) does not exist (create it with a main.tsx, or pass --config <dir>)")
    exit(1)
}

let bundler: Bundler
do {
    bundler = try Bundler.locate()
} catch {
    Log.error("\(error)")
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let host = Host(configDirectory: directory, bundler: bundler)
host.start()

app.run()

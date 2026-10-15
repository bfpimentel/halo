import Foundation

/// Compiles a config directory's `main.tsx` (plus the halo runtime library) into one script with esbuild.
public struct Bundler: Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public let esbuild: URL
    public let runtimeSources: URL

    public init(esbuild: URL, runtimeSources: URL) {
        self.esbuild = esbuild
        self.runtimeSources = runtimeSources
    }

    /// esbuild: `HALO_ESBUILD`, then `PATH` (plus common install dirs launchd leaves out), then `runtime/node_modules`.
    /// Runtime sources: `HALO_RUNTIME`, then `<prefix>/share/halo/runtime` next to the binary, then this checkout.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Bundler {
        let fileManager = FileManager.default
        let checkoutRuntime = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime")
        // The real binary, not the PATH symlink: Homebrew links bin/halo into the prefix but keeps share/ in the Cellar.
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executable.resolvingSymlinksInPath().deletingLastPathComponent()

        let runtimeCandidates = [
            environment["HALO_RUNTIME"].map(URL.init(fileURLWithPath:)),
            executableDir.appendingPathComponent("../share/halo/runtime").standardizedFileURL,
            checkoutRuntime,
        ].compactMap { $0 }
        guard let runtime = runtimeCandidates.first(where: { fileManager.fileExists(atPath: $0.appendingPathComponent("src/index.ts").path) }) else {
            throw Failure(description: "halo runtime sources not found (looked in \(runtimeCandidates.map(\.path)))")
        }

        let user = environment["USER"] ?? NSUserName()
        let searchPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [
            "/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.nix-profile/bin",
            "/etc/profiles/per-user/\(user)/bin", "/run/current-system/sw/bin",
        ]
        let esbuildCandidates = [environment["HALO_ESBUILD"]].compactMap { $0 }
            + searchPath.map { "\($0)/esbuild" }
            + [runtime.appendingPathComponent("node_modules/.bin/esbuild").path]
        guard let esbuild = esbuildCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw Failure(description: "esbuild not found; install it (e.g. `brew install esbuild`) or set HALO_ESBUILD")
        }

        return Bundler(esbuild: URL(fileURLWithPath: esbuild), runtimeSources: runtime.appendingPathComponent("src"))
    }

    /// `runtimeSources` without Homebrew's versioned Cellar directory (`…/Cellar/halo/<version>/…` → `…/opt/halo/…`),
    /// so paths written into user files (tsconfig) survive upgrades.
    public var stableRuntimeSources: String {
        let path = runtimeSources.path
        guard let range = path.range(of: #"/Cellar/halo/[^/]+/"#, options: .regularExpression) else { return path }
        return path.replacingCharacters(in: range, with: "/opt/halo/")
    }

    /// How a source-map path (relative to the config directory) should read in errors: the config's own files stay
    /// relative, halo's runtime becomes `halo/<file>`.
    public func displayName(forSource source: String, configDirectory: URL) -> String {
        let absolute = URL(fileURLWithPath: source, relativeTo: configDirectory).standardizedFileURL.path
        let runtime = runtimeSources.standardizedFileURL.path + "/"
        return absolute.hasPrefix(runtime) ? "halo/" + absolute.dropFirst(runtime.count) : source
    }

    public func build(configDirectory: URL) throws -> String {
        let main = configDirectory.appendingPathComponent("main.tsx").path
        let quotedMain = String(decoding: try JSONEncoder().encode(main), as: UTF8.self)
        let entry = """
        import { mount } from "halo/internal";
        import * as config from \(quotedMain);
        mount(config.default);
        """
        let process = Process()
        process.executableURL = esbuild
        process.currentDirectoryURL = configDirectory
        process.arguments = [
            "--bundle",
            "--format=iife",
            "--platform=neutral",
            "--target=es2022",
            "--main-fields=module,main",
            "--jsx=automatic",
            "--jsx-import-source=halo",
            "--alias:halo=\(runtimeSources.path)",
            "--loader=ts",
            "--sourcefile=halo-entry.ts",
            "--sourcemap=inline",
            "--sources-content=false",
            "--log-level=error",
            "--color=false",
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(Data(entry.utf8))
        try stdin.fileHandleForWriting.close()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(description: String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output, as: UTF8.self)
    }
}

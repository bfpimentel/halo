import Foundation
import JSRuntime

/// `halo init`: a config directory with a `halo.json`, a starter widget and a tsconfig that points the editor at halo's sources.
/// Never overwrites existing files.
public func initializeConfig(at path: String?) throws -> [String] {
    let directory = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
        ?? defaultConfigDirectory()
    let runtime = try Bundler.locate().stableRuntimeSources
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let files: [(String, String)] = [
        ("tsconfig.json", """
        {
          "compilerOptions": {
            "target": "ES2022",
            "module": "ESNext",
            "moduleResolution": "Bundler",
            "strict": true,
            "noEmit": true,
            "jsx": "react-jsx",
            "jsxImportSource": "halo",
            "lib": ["ES2022"],
            "paths": {
              "halo": ["\(runtime)/index.ts"],
              "halo/*": ["\(runtime)/*"]
            }
          },
          "include": ["**/*.ts", "**/*.tsx"]
        }

        """),
        ("halo.json", """
        {
          "widgets": {
            "clock": { "widget": "clock", "screens": "all" }
          }
        }

        """),
        ("widgets/clock.tsx", """
        import { Box, Surface, Text, defineWidget } from "halo";
        import { clock } from "halo/services";

        export default defineWidget({
          props: {
            format: { type: "string", default: "HH:mm", label: "Time format" },
            size: { type: "number", default: 22, min: 10, max: 96, label: "Text size" },
          },
          render: ({ screen, props }) => (
            <Surface name="clock" screen={screen} anchor={["bottom", "right"]} margins={[0, 16, 16, 0]}
                     layer="desktop" enter={{ from: { opacity: 0, scale: 0.9 }, curve: "spring" }}>
              <Box style={{ padding: [10, 16], background: "#1e1e2ee0", radius: 12 }}>
                <Text style={{ fontSize: props.size, fontWeight: "semibold", color: "#cdd6f4" }}>
                  {clock.format(props.format)}
                </Text>
              </Box>
            </Surface>
          ),
        });

        """),
    ]

    var created: [String] = []
    for (name, contents) in files {
        let file = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: file.path) else { continue }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        created.append(file.path)
    }
    return created
}

func defaultConfigDirectory() -> URL {
    let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
    return base.appendingPathComponent("halo")
}

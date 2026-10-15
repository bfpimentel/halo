// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "halo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "halo", targets: ["HaloCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/facebook/yoga.git", exact: "3.2.1"),
    ],
    targets: [
        .target(name: "Compositor"),
        .target(name: "Render", dependencies: [.product(name: "yoga", package: "yoga")]),
        .target(name: "JSRuntime", dependencies: ["Compositor", "Render"]),
        .target(name: "IPC"),
        .target(name: "HaloHost", dependencies: ["Compositor", "Render", "JSRuntime", "IPC"]),
        .executableTarget(name: "HaloCLI", dependencies: ["HaloHost", "IPC"]),
        .testTarget(name: "CompositorTests", dependencies: ["Compositor"]),
        .testTarget(name: "RenderTests", dependencies: ["Render"]),
        .testTarget(
            name: "JSRuntimeTests",
            dependencies: ["JSRuntime", "Compositor", "Render"],
            exclude: ["Fixtures"]
        ),
        .testTarget(name: "IPCTests", dependencies: ["IPC"]),
        .testTarget(name: "HaloHostTests", dependencies: ["HaloHost", "IPC"]),
    ]
)

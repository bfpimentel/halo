// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "halo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "halo-host", targets: ["HaloHost"]),
    ],
    targets: [
        .target(name: "Compositor"),
        .executableTarget(name: "HaloHost", dependencies: ["Compositor"]),
        .testTarget(name: "CompositorTests", dependencies: ["Compositor"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Render",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RenderCore", targets: ["RenderCore"]), .executable(name: "Render", targets: ["RenderApp"])],
    targets: [
        .target(name: "RenderCore"),
        .target(name: "RenderMedia", dependencies: ["RenderCore"]),
        .executableTarget(name: "RenderApp", dependencies: ["RenderCore", "RenderMedia"]),
        .testTarget(name: "RenderCoreTests", dependencies: ["RenderCore"]),
        .testTarget(name: "RenderMediaTests", dependencies: ["RenderMedia", "RenderCore"])
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Render",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RenderCore", targets: ["RenderCore"]), .executable(name: "Render", targets: ["RenderApp"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "RenderCore"),
        .target(name: "RenderAudioDSP",publicHeadersPath: "include",linkerSettings: [.linkedFramework("MediaToolbox"),.linkedFramework("AudioToolbox"),.linkedFramework("CoreMedia")]),
        .target(name: "RenderMedia", dependencies: ["RenderCore","RenderAudioDSP"]),
        .executableTarget(name: "RenderApp", dependencies: ["RenderCore", "RenderMedia", .product(name: "Sparkle",package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks"])]),
        .testTarget(name: "RenderCoreTests", dependencies: ["RenderCore"]),
        .testTarget(name: "RenderMediaTests", dependencies: ["RenderMedia", "RenderCore"])
    ]
)

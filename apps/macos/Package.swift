// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Grove",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Grove", targets: ["Grove"])],
    targets: [
        .target(name: "GroveCore"),
        .executableTarget(name: "Grove", dependencies: ["GroveCore"], resources: [.process("Resources")]),
        .testTarget(name: "GroveCoreTests", dependencies: ["GroveCore"]),
        .testTarget(name: "GroveTests", dependencies: ["Grove", "GroveCore"])
    ]
)

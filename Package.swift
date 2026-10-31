// swift-tools-version: 5.9
import PackageDescription

// The app compiles these same sources through Xcode's synchronized Lumina group.
// This package makes policy, persistence, and solar calculations testable without hardware.
let package = Package(
    name: "LuminaCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LuminaCore", targets: ["LuminaCore"])],
    targets: [
        .target(name: "LuminaCore", path: "Lumina/Core"),
        .testTarget(name: "LuminaCoreTests", dependencies: ["LuminaCore"])
    ]
)

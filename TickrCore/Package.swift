// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TickrCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TickrCore", targets: ["TickrCore"])],
    targets: [
        .target(name: "TickrCore"),
        .testTarget(name: "TickrCoreTests", dependencies: ["TickrCore"]),
    ]
)

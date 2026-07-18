// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeNetwork",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "NativeNetwork",
            targets: ["NativeNetwork"]
        ),
    ],
    targets: [
        .target(
            name: "NativeNetwork",
            path: "Sources/NativeNetwork"
        ),
        .executableTarget(
            name: "NativeNetworkDemo",
            dependencies: ["NativeNetwork"],
            path: "Examples/NativeNetworkDemo"
        ),
        .testTarget(
            name: "NativeNetworkTests",
            dependencies: ["NativeNetwork"],
            path: "Tests/NativeNetworkTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

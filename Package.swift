// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkingKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(name: "NetworkingKit", targets: ["NetworkingKit"])
    ],
    targets: [
        .target(name: "NetworkingKit", path: "Sources/NetworkingKit"),
        .testTarget(name: "NetworkingKitTests", dependencies: ["NetworkingKit"], path: "Tests/NetworkingKitTests")
    ]
)

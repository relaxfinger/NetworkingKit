//
//  Package.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkingKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "NetworkingKit",
            targets: ["NetworkingKit"]
        ),
    ],
    targets: [
        .target(
            name: "NetworkingKit",
            path: "Sources/NetworkingKit"
        ),
        .testTarget(
            name: "NetworkingKitTests",
            dependencies: ["NetworkingKit"],
            path: "Tests/NetworkingKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

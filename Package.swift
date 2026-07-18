//
//  Package.swift
//  NativeNetwork
//
//  Copyright (c) 2026 NativeNetwork contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NativeNetwork",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
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
        .testTarget(
            name: "NativeNetworkTests",
            dependencies: ["NativeNetwork"],
            path: "Tests/NativeNetworkTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

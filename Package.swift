//
//  Package.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

// swift-tools-version: 6.1
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
        .plugin(
            name: "BackendReferencePlugin",
            targets: ["BackendReferencePlugin"]
        ),
        .plugin(
            name: "BackendReferenceCommandPlugin",
            targets: ["BackendReferenceCommandPlugin"]
        ),
    ],
    targets: [
        .target(
            name: "NetworkingKit",
            path: "Sources/NetworkingKit"
        ),
        .executableTarget(
            name: "BackendReferenceGenerator",
            path: "Sources/BackendReferenceGenerator"
        ),
        .plugin(
            name: "BackendReferencePlugin",
            capability: .buildTool(),
            dependencies: ["BackendReferenceGenerator"],
            path: "Plugins/BackendReferencePlugin"
        ),
        .plugin(
            name: "BackendReferenceCommandPlugin",
            capability: .command(
                intent: .custom(
                    verb: "generate-backend-reference",
                    description: "Generate the backend API HTML reference."
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Generates the backend API HTML reference in Docs/BackendAPIReference."
                    )
                ]
            ),
            path: "Plugins/BackendReferenceCommandPlugin"
        ),
        .testTarget(
            name: "NetworkingKitTests",
            dependencies: ["NetworkingKit"],
            path: "Tests/NetworkingKitTests"
        ),
        .testTarget(
            name: "NetworkingKitAPICompatibilityTests",
            dependencies: ["NetworkingKit"],
            path: "Tests/NetworkingKitAPICompatibilityTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

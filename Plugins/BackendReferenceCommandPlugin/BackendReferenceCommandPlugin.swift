import Foundation
import PackagePlugin

@main
struct BackendReferenceCommandPlugin: CommandPlugin {
    private var pluginPackageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func performCommand(context: PluginContext, arguments: [String]) throws {
        try generate(appRoot: context.package.directoryURL, scriptsRoot: context.package.directoryURL)
    }

    fileprivate func generate(appRoot: URL, scriptsRoot: URL) throws {
        let generator = scriptsRoot.appending(path: "Sources/BackendReferenceGenerator/main.swift")
        let outputDirectory = appRoot.appending(path: "Docs/BackendAPIReference", directoryHint: .isDirectory)
        try runSwift(script: generator, arguments: [
            "--source-directory", appRoot.path,
            "--output-directory", outputDirectory.path
        ])
    }

    private func runSwift(script: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", script.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "SDKROOT")
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BackendReferenceCommandPlugin", code: Int(process.terminationStatus))
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension BackendReferenceCommandPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try generate(appRoot: context.xcodeProject.directoryURL, scriptsRoot: pluginPackageRoot)
    }
}
#endif

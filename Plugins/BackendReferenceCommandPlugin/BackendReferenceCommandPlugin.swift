import Foundation
import PackagePlugin

@main
struct BackendReferenceCommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        try generate(appRoot: context.package.directoryURL, toolURL: context.tool(named: "BackendReferenceGenerator").url)
    }

    fileprivate func generate(appRoot: URL, toolURL: URL) throws {
        let outputDirectory = appRoot.appending(path: "Docs/BackendAPIReference", directoryHint: .isDirectory)
        try runGenerator(toolURL: toolURL, arguments: [
            "--source-directory", appRoot.path,
            "--output-directory", outputDirectory.path
        ])
    }

    private func runGenerator(toolURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments
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
        try generate(appRoot: context.xcodeProject.directoryURL, toolURL: context.tool(named: "BackendReferenceGenerator").url)
    }
}
#endif

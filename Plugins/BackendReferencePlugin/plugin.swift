import PackagePlugin
import Foundation

@main
struct BackendReferencePlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let tool = try context.tool(named: "BackendReferenceGenerator")
        let stamp = context.pluginWorkDirectoryURL.appendingPathComponent("backend-reference.stamp")
        let outputDirectory = context.pluginWorkDirectoryURL.appendingPathComponent("BackendAPIReference", isDirectory: true)

        return [
            .buildCommand(
                displayName: "Generate backend API reference",
                executable: tool.url,
                arguments: [
                    "--source-directory", sourceTarget.directoryURL.path,
                    "--output-directory", outputDirectory.path,
                    "--stamp", stamp.path
                ],
                outputFiles: [stamp]
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension BackendReferencePlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "BackendReferenceGenerator")
        let stamp = context.pluginWorkDirectoryURL.appendingPathComponent("backend-reference.stamp")
        let outputDirectory = context.pluginWorkDirectoryURL.appendingPathComponent("BackendAPIReference", isDirectory: true)

        return [
            .buildCommand(
                displayName: "Generate backend API reference",
                executable: tool.url,
                arguments: [
                    "--source-directory", context.xcodeProject.directoryURL.path,
                    "--output-directory", outputDirectory.path,
                    "--stamp", stamp.path
                ],
                outputFiles: [stamp]
            )
        ]
    }
}
#endif

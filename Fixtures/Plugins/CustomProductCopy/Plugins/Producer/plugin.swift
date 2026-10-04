import Foundation
import PackagePlugin

@main
struct Producer: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let inputs = context.package.directoryURL.appending(path: "Inputs")
        let script = inputs.appending(path: "produce.sh")
        let source = inputs.appending(path: "library.c")
        let archive = context.pluginWorkDirectoryURL.appending(path: "$(BUILD_SUBDIR)/libArtifacts.a")
        return [.buildCommand(
            displayName: "Produce archive with debug information",
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path, source.path, archive.path],
            inputFiles: [script, source],
            productFiles: [BuildProduct(archive)]
        )]
    }
}

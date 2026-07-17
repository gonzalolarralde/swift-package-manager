import Foundation
import PackagePlugin

@main
struct FirmwareBuilder: ProductBuilderPlugin {
    func createBuildPlan(
        context: PluginContext,
        input: ProductBuilderInput
    ) async throws -> ProductBuilderPlan {
        let finalizer = try context.tool(named: "FirmwareFinalizer")
        let elf = input.outputDirectoryURL.appendingPathComponent("\(input.product.name).elf")
        let bin = input.outputDirectoryURL.appendingPathComponent("\(input.product.name).bin")
        let uf2 = input.outputDirectoryURL.appendingPathComponent("\(input.product.name).uf2")
        let emitsDebugDirectory = input.arguments.contains("--emit-debug-directory")
        let debugDirectory = input.outputDirectoryURL.appendingPathComponent("\(input.product.name).debug")

        var arguments = [
            "--archive", input.aggregateStaticLibraryURL.path,
            "--type", input.typeIdentifier,
            "--configuration", input.buildConfiguration,
            "--triple", input.targetTriple,
            "--elf", elf.path,
            "--bin", bin.path,
            "--uf2", uf2.path,
        ]
        for resource in input.resourceURLs {
            arguments += ["--resource", resource.path]
        }
        arguments += input.arguments
        if emitsDebugDirectory {
            arguments += ["--debug-directory", debugDirectory.path]
        }

        let commandOutputs = [elf, bin, uf2] + (emitsDebugDirectory ? [debugDirectory] : [])

        return ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: "Finalizing \(input.product.name) as ELF, BIN, and UF2",
                    executable: finalizer.url,
                    arguments: arguments,
                    inputFiles: [input.aggregateStaticLibraryURL] + input.resourceURLs,
                    outputFiles: commandOutputs
                ),
            ],
            outputFiles: [elf, bin, uf2],
            outputDirectories: emitsDebugDirectory ? [debugDirectory] : []
        )
    }
}

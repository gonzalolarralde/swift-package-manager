//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel

import struct Basics.AbsolutePath
import struct Basics.InternalError
import enum Basics.Sandbox
import struct LLBuildManifest.Node
import struct SPMBuildCore.BuildParameters
import struct SPMBuildCore.ProductBuilderPluginInvocationResult
import struct PackageGraph.ResolvedModule
import struct PackageGraph.ResolvedProduct
import struct TSCBasic.ByteString

extension LLBuildManifestBuilder {
    func createProductCommand(_ buildProduct: ProductBuildDescription) throws {
        let cmdName = try buildProduct.commandName

        // Add dependency on Info.plist generation on Darwin platforms.
        let testInputs: [AbsolutePath]
        if buildProduct.product.type == .test
            && buildProduct.buildParameters.triple.isDarwin()
            && buildProduct.buildParameters.testingParameters.experimentalTestOutput {
            let testBundleInfoPlistPath = try buildProduct.binaryPath.parentDirectory.parentDirectory.appending(component: "Info.plist")
            testInputs = [testBundleInfoPlistPath]

            self.manifest.addWriteInfoPlistCommand(
                principalClass: "\(buildProduct.product.modules[buildProduct.product.modules.startIndex].c99name).SwiftPMXCTestObserver",
                outputPath: testBundleInfoPlistPath
            )
        } else {
            testInputs = []
        }

        // Create a phony node to represent the entire target.
        let targetName = try buildProduct.llbuildTargetName
        let output: Node = .virtual(targetName)

        let finalProductNodes: [Node]
        switch buildProduct.product.type {
        case .library(.static):
            let archiveNode = try Node.file(buildProduct.binaryPath)
            try self.manifest.addShellCmd(
                name: cmdName,
                description: "Archiving \(buildProduct.binaryPath.prettyPath())",
                inputs: (buildProduct.objects + [buildProduct.linkFileListPath]).map(Node.file),
                outputs: [archiveNode],
                arguments: try buildProduct.archiveArguments()
            )

            if let productBuilderResult = buildProduct.productBuilderResult {
                finalProductNodes = try self.addProductBuilderCommands(
                    productBuilderResult,
                    for: buildProduct,
                    archiveNode: archiveNode
                )
            } else {
                // Product-builder tool bootstrap plans intentionally stop at
                // the internal archive and never build this product target.
                finalProductNodes = [archiveNode]
            }

        default:
            let inputs = try buildProduct.objects
                + buildProduct.dylibs.map { try $0.binaryPath }
                + [buildProduct.linkFileListPath]
                + testInputs

            let shouldCodeSign: Bool
            let linkedBinaryNode: Node
            let linkedBinaryPath = try buildProduct.binaryPath
            if case .executable = buildProduct.product.type,
               buildProduct.buildParameters.triple.isMacOSX,
               buildProduct.buildParameters.debuggingParameters.shouldEnableDebuggingEntitlement {
                shouldCodeSign = true
                linkedBinaryNode = try .file(buildProduct.binaryPath, isMutated: true)
            } else {
                shouldCodeSign = false
                linkedBinaryNode = try .file(buildProduct.binaryPath)
            }

            try self.manifest.addShellCmd(
                name: cmdName,
                description: "Linking \(buildProduct.binaryPath.prettyPath())",
                inputs: inputs.map(Node.file),
                outputs: [linkedBinaryNode],
                arguments: try buildProduct.linkArguments()
            )

            if shouldCodeSign {
                let basename = try buildProduct.binaryPath.basename
                let plistPath = try buildProduct.binaryPath.parentDirectory
                    .appending(component: "\(basename)-entitlement.plist")
                self.manifest.addEntitlementPlistCommand(
                    entitlement: "com.apple.security.get-task-allow",
                    outputPath: plistPath
                )

                let cmdName = try buildProduct.commandName
                let codeSigningOutput = Node.virtual(targetName + "-CodeSigning")
                try self.manifest.addShellCmd(
                    name: "\(cmdName)-entitlements",
                    description: "Applying debug entitlements to \(buildProduct.binaryPath.prettyPath())",
                    inputs: [linkedBinaryNode, .file(plistPath)],
                    outputs: [codeSigningOutput],
                    arguments: buildProduct.codeSigningArguments(plistPath: plistPath, binaryPath: linkedBinaryPath)
                )
                finalProductNodes = [codeSigningOutput]
            } else {
                finalProductNodes = [linkedBinaryNode]
            }
        }

        self.manifest.addNode(output, toTarget: targetName)
        self.manifest.addPhonyCmd(
            name: output.name,
            inputs: finalProductNodes,
            outputs: [output]
        )

        if self.plan.graph.reachableProducts.contains(id: buildProduct.product.id) {
            if buildProduct.product.type != .test {
                self.addNode(output, toTarget: .main)
            }
            self.addNode(output, toTarget: .test)
        }

        self.manifest.addWriteLinkFileListCommand(
            objects: Array(buildProduct.objects),
            linkFileListPath: buildProduct.linkFileListPath
        )
    }

    /// Adds the commands declared by a custom product's builder plug-in. The
    /// internally generated archive and every resource bundle are mandatory
    /// inputs, while dependencies between builder commands remain driven by
    /// their explicitly declared input/output paths.
    private func addProductBuilderCommands(
        _ result: ProductBuilderPluginInvocationResult,
        for buildProduct: ProductBuildDescription,
        archiveNode: Node
    ) throws -> [Node] {
        let finalDirectoryPaths = Set(result.outputDirectories)
        var copiedDirectoryPaths = Set<AbsolutePath>()
        var resourceBundleNodes = [AbsolutePath: Node]()

        for module in buildProduct.staticTargets {
            guard let description = self.plan.description(for: module, context: buildProduct.destination),
                  let bundlePath = description.bundlePath
            else {
                continue
            }
            resourceBundleNodes[bundlePath] = .virtual(description.llbuildResourcesCmdName)
            for resource in description.resources where self.fileSystem.isDirectory(resource.path) {
                switch resource.rule {
                case .copy, .process:
                    copiedDirectoryPaths.insert(try bundlePath.appending(resource.destination))
                case .embedInCode:
                    break
                }
            }
        }

        func inputNode(for path: AbsolutePath) -> Node {
            if let bundleNode = resourceBundleNodes[path] {
                return bundleNode
            }
            if copiedDirectoryPaths.contains(path) || finalDirectoryPaths.contains(path) {
                return .directory(path)
            }
            return .file(path)
        }

        func outputNode(for path: AbsolutePath) -> Node {
            finalDirectoryPaths.contains(path) ? .directory(path) : .file(path)
        }

        func uniqued(_ nodes: [Node]) -> [Node] {
            var seen = Set<Node>()
            return nodes.filter { seen.insert($0).inserted }
        }

        let mandatoryResourceNodes = resourceBundleNodes.values.sorted { $0.name < $1.name }
        for (index, command) in result.buildCommands.enumerated() {
            let executable = command.configuration.executable
            let displayName = command.configuration.displayName ?? executable.basename
            var commandLine = [executable.pathString] + command.configuration.arguments
            if !self.disableSandboxForPluginCommands {
                commandLine = try Sandbox.apply(
                    command: commandLine,
                    fileSystem: self.fileSystem,
                    strictness: .writableTemporaryDirectory,
                    writableDirectories: [result.pluginOutputDirectory]
                )
            }

            let inputs = uniqued(
                [archiveNode, .file(executable)]
                    + mandatoryResourceNodes
                    + command.inputFiles.map(inputNode(for:))
            )
            let outputs = command.outputFiles.map(outputNode(for:))
            let signature = ([
                buildProduct.package.identity.description,
                buildProduct.product.name,
                String(index),
                executable.pathString,
            ] + command.configuration.arguments + command.outputFiles.map(\.pathString))
                .joined(separator: "|")

            self.manifest.addShellCmd(
                name: "ProductBuilder-" + ByteString(encodingAsUTF8: signature).sha256Checksum,
                description: displayName,
                inputs: inputs,
                outputs: outputs,
                arguments: commandLine,
                environment: command.configuration.environment,
                workingDirectory: command.configuration.workingDirectory?.pathString
            )
        }

        return result.outputFiles.map(Node.file) + result.outputDirectories.map(Node.directory)
    }
}

extension ProductBuildDescription {
    package var llbuildTargetName: String {
        get throws {
            try self.product.getLLBuildTargetName(buildParameters: self.buildParameters)
        }
    }

    package var commandName: String {
        get throws {
            try "C.\(self.llbuildTargetName)\(self.buildParameters.suffix)"
        }
    }
}

fileprivate func llbuildNameWithoutExtension(
    for product: String,
    buildParameters: BuildParameters
) -> String {
    "\(product)-\(buildParameters.triple.tripleString)-\(buildParameters.buildConfig)\(buildParameters.suffix)"
}

fileprivate func executableName(
    for product: String,
    buildParameters: BuildParameters
) -> String {
    "\(llbuildNameWithoutExtension(for: product, buildParameters: buildParameters)).exe"
}

fileprivate func dynamicLibraryName(
    for product: String,
    buildParameters: BuildParameters
) -> String {
    "\(llbuildNameWithoutExtension(for: product, buildParameters: buildParameters)).dylib"
}

fileprivate func staticLibraryName(
    for product: String,
    buildParameters: BuildParameters
) -> String {
    "\(llbuildNameWithoutExtension(for: product, buildParameters: buildParameters)).a"
}

fileprivate func testName(
    for testProduct: String,
    buildParameters: BuildParameters
) -> String {
    "\(llbuildNameWithoutExtension(for: testProduct, buildParameters: buildParameters)).test"
}

func getLLBuildTargetName(
    macro: ResolvedModule,
    buildParameters: BuildParameters
) -> String {
    assert(macro.type == .macro)
    #if BUILD_MACROS_AS_DYLIBS
    return dynamicLibraryName(for: macro.name, buildParameters: buildParameters)
    #else
    return executableName(for: macro.name, buildParameters: buildParameters)
    #endif
}

extension ResolvedProduct {
    public func getLLBuildTargetName(buildParameters: BuildParameters) throws -> String {
        switch type {
        case .library(.dynamic):
            return dynamicLibraryName(for: self.name, buildParameters: buildParameters)
        case .test:
            return testName(for: self.name, buildParameters: buildParameters)
        case .library(.static):
            return staticLibraryName(for: self.name, buildParameters: buildParameters)
        case .library(.automatic):
            throw InternalError("automatic library not supported")
        case .executable, .snippet:
            return executableName(for: self.name, buildParameters: buildParameters)
        case .macro:
            guard let macroModule = self.modules.first else {
                throw InternalError("macro product \(self.name) has no targets")
            }
            return Build.getLLBuildTargetName(macro: macroModule, buildParameters: buildParameters)
        case .plugin:
            throw InternalError("unexpectedly asked for the llbuild target name of a plugin product")
        }
    }
}

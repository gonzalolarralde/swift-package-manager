//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// The inputs SwiftPM makes available when a product builder plug-in plans the
/// commands that create a custom product.
@available(_PackageDescription, introduced: 6.3)
public struct ProductBuilderInput {
    /// The custom product being built. Its `targets` are the targets selected in
    /// the package manifest.
    public let product: Product

    /// A stable identifier for the custom product kind, supplied by its definition library.
    public let typeIdentifier: String

    /// A static archive containing the product's target objects and their static
    /// target dependencies. The archive is produced before builder commands run.
    public let aggregateStaticLibraryURL: URL

    /// The exact destination URLs of copied and processed resources.
    public let resourceURLs: [URL]

    /// The destination URLs of resource bundles associated with the product's targets.
    public let resourceBundleURLs: [URL]

    /// Opaque arguments from the custom product declaration.
    public let arguments: [String]

    /// The directory in which all intermediate and final builder outputs must be created.
    public let outputDirectoryURL: URL

    /// The destination build configuration, such as `debug` or `release`.
    public let buildConfiguration: String

    /// The destination target triple.
    public let targetTriple: String

    @_spi(PackagePluginInternal)
    public init(
        product: Product,
        typeIdentifier: String,
        aggregateStaticLibraryURL: URL,
        resourceURLs: [URL],
        resourceBundleURLs: [URL],
        arguments: [String],
        outputDirectoryURL: URL,
        buildConfiguration: String,
        targetTriple: String
    ) {
        self.product = product
        self.typeIdentifier = typeIdentifier
        self.aggregateStaticLibraryURL = aggregateStaticLibraryURL
        self.resourceURLs = resourceURLs
        self.resourceBundleURLs = resourceBundleURLs
        self.arguments = arguments
        self.outputDirectoryURL = outputDirectoryURL
        self.buildConfiguration = buildConfiguration
        self.targetTriple = targetTriple
    }
}

/// A declarative plan for creating the final artifacts of a custom product.
///
/// SwiftPM evaluates the plug-in while planning the build. It executes the
/// returned commands later, after their declared inputs have been built.
@available(_PackageDescription, introduced: 6.3)
public struct ProductBuilderPlan {
    /// Explicit-input, explicit-output commands to incorporate into the build graph.
    /// Product builders cannot use prebuild commands.
    public let commands: [Command]

    /// Command outputs that are final file artifacts of the product.
    public let outputFiles: [URL]

    /// Command outputs that are final directory artifacts of the product.
    public let outputDirectories: [URL]

    public init(
        commands: [Command],
        outputFiles: [URL] = [],
        outputDirectories: [URL] = []
    ) {
        self.commands = commands
        self.outputFiles = outputFiles
        self.outputDirectories = outputDirectories
    }
}

/// Errors found while validating a plan returned by a product builder plug-in.
@available(_PackageDescription, introduced: 6.3)
public enum ProductBuilderPlanValidationError: Error, CustomStringConvertible {
    case prebuildCommandNotSupported
    case commandHasNoOutputs
    case outputOutsideOutputDirectory(URL)
    case outputHasMultipleProducers(URL)
    case noFinalOutputs
    case duplicateFinalOutput(URL)
    case finalOutputHasNoProducer(URL)

    public var description: String {
        switch self {
        case .prebuildCommandNotSupported:
            return "product builder plug-ins cannot return prebuild commands"
        case .commandHasNoOutputs:
            return "every product builder command must declare at least one output"
        case .outputOutsideOutputDirectory(let url):
            return "product builder output '\(url.path)' is outside the product output directory"
        case .outputHasMultipleProducers(let url):
            return "product builder output '\(url.path)' is produced by more than one command"
        case .noFinalOutputs:
            return "a product builder plan must declare at least one final output"
        case .duplicateFinalOutput(let url):
            return "product builder final output '\(url.path)' is declared more than once"
        case .finalOutputHasNoProducer(let url):
            return "product builder final output '\(url.path)' is not produced by any command"
        }
    }
}

@available(_PackageDescription, introduced: 6.3)
extension ProductBuilderPlan {
    /// Validates the graph-shaping portions of a product build plan.
    @_spi(PackagePluginInternal)
    public func validate(outputDirectory: URL) throws {
        var producerCounts: [URL: Int] = [:]
        // Use lexical normalization here. `standardizedFileURL` consults the
        // file system and can resolve an existing output directory through a
        // symlink while leaving its not-yet-created children unresolved.
        let outputDirectory = outputDirectory.standardized

        for command in self.commands {
            let outputs: [URL]
            switch command {
            case .buildCommand(_, _, _, _, _, let outputFiles):
                guard !outputFiles.isEmpty else {
                    throw ProductBuilderPlanValidationError.commandHasNoOutputs
                }
                outputs = outputFiles
            case .prebuildCommand:
                throw ProductBuilderPlanValidationError.prebuildCommandNotSupported
            }

            for output in outputs {
                let output = output.standardized
                guard output.isDescendant(of: outputDirectory) else {
                    throw ProductBuilderPlanValidationError.outputOutsideOutputDirectory(output)
                }
                producerCounts[output, default: 0] += 1
                if producerCounts[output, default: 0] > 1 {
                    throw ProductBuilderPlanValidationError.outputHasMultipleProducers(output)
                }
            }
        }

        let finalOutputs = (self.outputFiles + self.outputDirectories).map(\.standardized)
        guard !finalOutputs.isEmpty else {
            throw ProductBuilderPlanValidationError.noFinalOutputs
        }

        var seenFinalOutputs = Set<URL>()
        for output in finalOutputs {
            guard output.isDescendant(of: outputDirectory) else {
                throw ProductBuilderPlanValidationError.outputOutsideOutputDirectory(output)
            }
            guard seenFinalOutputs.insert(output).inserted else {
                throw ProductBuilderPlanValidationError.duplicateFinalOutput(output)
            }
            guard producerCounts[output] == 1 else {
                throw ProductBuilderPlanValidationError.finalOutputHasNoProducer(output)
            }
        }
    }
}

private extension URL {
    func isDescendant(of directory: URL) -> Bool {
        let directoryComponents = directory.pathComponents
        let components = self.pathComponents
        return components.count > directoryComponents.count
            && components.prefix(directoryComponents.count).elementsEqual(directoryComponents)
    }
}

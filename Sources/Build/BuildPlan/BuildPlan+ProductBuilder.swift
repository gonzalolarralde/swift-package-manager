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

import Basics
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import struct TSCBasic.StringError

extension ModulesGraph {
    /// Resolves the product-builder plug-in declared by a custom product.
    ///
    /// A plug-in in the declaring package may be named either by its target or
    /// by a plug-in product. A plug-in from a dependency must be vended as a
    /// plug-in product, matching the rules for ordinary plug-in usages.
    func productBuilderPlugin(for product: ResolvedProduct) throws -> ResolvedModule {
        guard let customProduct = product.underlying.customProduct else {
            throw InternalError("product '\(product.name)' is not a custom product")
        }
        guard let declaringPackage = self.package(for: product) else {
            throw InternalError("could not determine package for custom product '\(product.name)'")
        }

        let providerPackage: ResolvedPackage
        let mayReferenceTargetDirectly: Bool
        if let packageName = customProduct.builderPluginPackage {
            let referencedIdentities = Set(declaringPackage.manifest.dependencies.compactMap { dependency in
                if dependency.nameForModuleDependencyResolutionOnly.caseInsensitiveCompare(packageName) == .orderedSame
                    || dependency.identity.description.caseInsensitiveCompare(packageName) == .orderedSame
                {
                    dependency.identity
                } else {
                    nil
                }
            })
            let candidates = self.directDependencies(for: declaringPackage).filter {
                referencedIdentities.contains($0.identity)
                    || $0.identity.description.caseInsensitiveCompare(packageName) == .orderedSame
                    || $0.manifest.displayName.caseInsensitiveCompare(packageName) == .orderedSame
            }
            guard let candidate = candidates.count == 1 ? candidates[0] : nil else {
                if candidates.isEmpty {
                    throw StringError(
                        "custom product '\(product.name)' references builder plug-in package "
                            + "'\(packageName)', which is not a direct dependency of package "
                            + "'\(declaringPackage.manifest.displayName)'"
                    )
                }
                throw StringError(
                    "custom product '\(product.name)' has an ambiguous builder plug-in package reference "
                        + "'\(packageName)'"
                )
            }
            providerPackage = candidate
            mayReferenceTargetDirectly = false
        } else {
            providerPackage = declaringPackage
            mayReferenceTargetDirectly = true
        }

        var candidates: [ResolvedModule] = []
        if mayReferenceTargetDirectly,
           let target = providerPackage.modules.first(where: { $0.name == customProduct.builderPlugin })
        {
            candidates.append(target)
        }
        for pluginProduct in providerPackage.products where
            pluginProduct.name == customProduct.builderPlugin && pluginProduct.type == .plugin
        {
            candidates.append(contentsOf: pluginProduct.modules)
        }

        var seen = Set<ResolvedModule.ID>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        guard let plugin = candidates.count == 1 ? candidates[0] : nil else {
            let packageDescription = customProduct.builderPluginPackage.map { " in package '\($0)'" } ?? ""
            if candidates.isEmpty {
                throw StringError(
                    "custom product '\(product.name)' references unknown builder plug-in "
                        + "'\(customProduct.builderPlugin)'\(packageDescription)"
                )
            }
            throw StringError(
                "custom product '\(product.name)' references ambiguous builder plug-in "
                    + "'\(customProduct.builderPlugin)'\(packageDescription)"
            )
        }
        guard let pluginModule = plugin.underlying as? PluginModule else {
            throw StringError(
                "builder '\(customProduct.builderPlugin)' for custom product '\(product.name)' is not a plug-in"
            )
        }
        guard pluginModule.capability == .productBuilder else {
            throw StringError(
                "builder plug-in '\(customProduct.builderPlugin)' for custom product '\(product.name)' "
                    + "must declare the '.productBuilder' capability"
            )
        }
        return plugin
    }

    /// Returns the unique product-builder plug-ins needed by reachable custom
    /// products. These have to participate in host tool preparation even though
    /// they are not ordinary target plug-in dependencies.
    func productBuilderPlugins() throws -> [ResolvedModule] {
        var seen = Set<ResolvedModule.ID>()
        return try self.reachableProducts.compactMap { product in
            guard product.underlying.customProduct != nil else {
                return nil
            }
            let plugin = try self.productBuilderPlugin(for: product)
            return seen.insert(plugin.id).inserted ? plugin : nil
        }
    }
}

extension BuildPlan {
    /// Evaluates the builder plug-in for each reachable custom product after
    /// normal product planning has populated its aggregate archive inputs.
    func invokeProductBuilderPlugins(
        configuration: PluginConfiguration,
        tools: [ResolvedModule.ID: [String: PluginTool]],
        pkgConfigDirectories: [AbsolutePath],
        observabilityScope: ObservabilityScope
    ) async throws {
        for buildProduct in self.productMap.values {
            guard let customProduct = buildProduct.product.underlying.customProduct,
                  self.graph.reachableProducts.contains(id: buildProduct.product.id),
                  !buildProduct.buildParameters.shouldSkipBuilding
            else {
                continue
            }

            guard buildProduct.dylibs.isEmpty else {
                throw StringError(
                    "custom product '\(buildProduct.product.name)' has dynamic library dependencies; "
                        + "product-builder plug-ins currently support only the aggregate static target closure"
                )
            }
            guard buildProduct.libraryBinaryPaths.isEmpty else {
                throw StringError(
                    "custom product '\(buildProduct.product.name)' has binary library dependencies; "
                        + "product-builder plug-ins do not expose those inputs yet"
                )
            }

            let plugin = try self.graph.productBuilderPlugin(for: buildProduct.product)
            guard let pluginModule = plugin.underlying as? PluginModule else {
                throw InternalError("resolved product builder '\(plugin.name)' is not a plug-in module")
            }
            guard let accessibleTools = tools[plugin.id] else {
                throw InternalError("no tools were prepared for product builder plug-in '\(plugin.name)'")
            }

            let (resourceFiles, resourceBundles) = try self.productBuilderResources(for: buildProduct)
            let pluginOutputDirectory = buildProduct.tempsPath.appending("product-builder")
            let productOutputDirectory = pluginOutputDirectory.appending("outputs")
            let result = try await pluginModule.invokeProductBuilder(
                package: buildProduct.package,
                product: buildProduct.product,
                typeIdentifier: customProduct.typeIdentifier,
                aggregateStaticLibrary: try buildProduct.binaryPath,
                resourceFiles: resourceFiles,
                resourceBundles: resourceBundles,
                arguments: customProduct.arguments,
                productOutputDirectory: productOutputDirectory,
                buildConfiguration: buildProduct.buildParameters.configuration.dirname,
                targetTriple: buildProduct.buildParameters.triple.tripleString,
                buildEnvironment: buildProduct.buildParameters.buildEnvironment,
                workers: self.toolsBuildParameters.workers,
                scriptRunner: configuration.scriptRunner,
                workingDirectory: buildProduct.package.path,
                pluginOutputDirectory: pluginOutputDirectory,
                toolSearchDirectories: [self.toolsBuildParameters.toolchain.swiftCompilerPath.parentDirectory],
                accessibleTools: accessibleTools,
                writableDirectories: [pluginOutputDirectory],
                readOnlyDirectories: [buildProduct.package.path],
                allowNetworkConnections: [],
                pkgConfigDirectories: pkgConfigDirectories,
                sdkRootPath: buildProduct.buildParameters.toolchain.sdkRootPath,
                fileSystem: self.fileSystem,
                modulesGraph: self.graph,
                observabilityScope: observabilityScope
            )

            let diagnosticsEmitter = observabilityScope.makeDiagnosticsEmitter {
                var metadata = ObservabilityMetadata()
                metadata.packageIdentity = buildProduct.package.identity
                metadata.packageKind = buildProduct.package.manifest.packageKind
                metadata.pluginName = plugin.name
                return metadata
            }
            for line in result.textOutput.split(whereSeparator: { $0.isNewline }) {
                diagnosticsEmitter.emit(info: line)
            }
            for diagnostic in result.diagnostics {
                diagnosticsEmitter.emit(diagnostic)
            }
            guard result.succeeded else {
                throw StringError(
                    "build planning stopped because product builder plug-in '\(plugin.name)' failed for "
                        + "custom product '\(buildProduct.product.name)'"
                )
            }

            buildProduct.productBuilderResult = result
        }
    }

    /// Computes the exact resource destinations that will exist when builder
    /// commands execute, plus the bundle roots useful for locating them.
    private func productBuilderResources(
        for buildProduct: ProductBuildDescription
    ) throws -> (files: [AbsolutePath], bundles: [AbsolutePath]) {
        var files = Set<AbsolutePath>()
        var bundles = Set<AbsolutePath>()

        for module in buildProduct.staticTargets {
            guard let description = self.description(for: module, context: buildProduct.destination),
                  let bundlePath = description.bundlePath
            else {
                continue
            }
            bundles.insert(bundlePath)
            for resource in description.resources {
                switch resource.rule {
                case .copy, .process:
                    files.insert(try bundlePath.appending(resource.destination))
                case .embedInCode:
                    // Embedded resources are compiled into the aggregate archive.
                    break
                }
            }
        }

        return (files.sorted(), bundles.sorted())
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.InternalError
import Foundation
import PackageGraph
import PackageModel
import struct TSCBasic.StringError

extension ModulesGraph {
    /// Resolves the product-builder plug-in declared by an artifact product.
    ///
    /// A plug-in in the declaring package may be named either by its target or
    /// by a plug-in product. A plug-in from a dependency must be vended as a
    /// plug-in product, matching the rules for ordinary plug-in usages.
    package func productBuilderPlugin(for product: ResolvedProduct) throws -> ResolvedModule {
        guard let artifactProduct = product.underlying.customProduct else {
            throw InternalError("product '\(product.name)' is not an artifact product")
        }
        guard let declaringPackage = self.package(for: product) else {
            throw InternalError("could not determine package for artifact product '\(product.name)'")
        }

        let providerPackage: ResolvedPackage
        let mayReferenceTargetDirectly: Bool
        if let packageName = artifactProduct.builderPluginPackage {
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
                        "artifact product '\(product.name)' references builder plug-in package "
                            + "'\(packageName)', which is not a direct dependency of package "
                            + "'\(declaringPackage.manifest.displayName)'"
                    )
                }
                throw StringError(
                    "artifact product '\(product.name)' has an ambiguous builder plug-in package reference "
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
           let target = providerPackage.modules.first(where: { $0.name == artifactProduct.builderPlugin })
        {
            candidates.append(target)
        }
        for pluginProduct in providerPackage.products where
            pluginProduct.name == artifactProduct.builderPlugin && pluginProduct.type == .plugin
        {
            candidates.append(contentsOf: pluginProduct.modules)
        }

        var seen = Set<ResolvedModule.ID>()
        candidates = candidates.filter { seen.insert($0.id).inserted }
        guard let plugin = candidates.count == 1 ? candidates[0] : nil else {
            let packageDescription = artifactProduct.builderPluginPackage.map { " in package '\($0)'" } ?? ""
            if candidates.isEmpty {
                throw StringError(
                    "artifact product '\(product.name)' references unknown builder plug-in "
                        + "'\(artifactProduct.builderPlugin)'\(packageDescription)"
                )
            }
            throw StringError(
                "artifact product '\(product.name)' references ambiguous builder plug-in "
                    + "'\(artifactProduct.builderPlugin)'\(packageDescription)"
            )
        }
        guard let pluginModule = plugin.underlying as? PluginModule else {
            throw StringError(
                "builder '\(artifactProduct.builderPlugin)' for artifact product '\(product.name)' is not a plug-in"
            )
        }
        guard pluginModule.capability == .productBuilder else {
            throw StringError(
                "builder plug-in '\(artifactProduct.builderPlugin)' for artifact product '\(product.name)' "
                    + "must declare the '.productBuilder' capability"
            )
        }
        return plugin
    }

    /// Returns the unique product-builder plug-ins needed by reachable artifact products.
    package func productBuilderPlugins() throws -> [ResolvedModule] {
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

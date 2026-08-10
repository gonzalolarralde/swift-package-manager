//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SourceControl
import struct TSCUtility.Version

enum ConstExprManifestModel {
    static func makeManifest(
        json: String,
        manifestPath: AbsolutePath,
        toolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        pruneDependencies: Bool
    ) throws -> Manifest {
        let parsed = try ManifestJSONParser.parse(
            v4: json,
            toolsVersion: toolsVersion,
            packageKind: packageKind,
            packagePath: manifestPath.parentDirectory,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem
        )

        var products = parsed.products
        var targets = parsed.targets
        if products.isEmpty, targets.isEmpty,
           fileSystem.isFile(manifestPath.parentDirectory.appending(component: moduleMapFilename)) {
            try products.append(
                ProductDescription(
                    name: parsed.name,
                    type: .library(.automatic),
                    targets: [parsed.name]
                )
            )
            targets.append(
                try TargetDescription(
                    name: parsed.name,
                    path: "",
                    type: .system,
                    packageAccess: false,
                    pkgConfig: parsed.pkgConfig,
                    providers: parsed.providers
                )
            )
        }

        return Manifest(
            displayName: parsed.name,
            packageIdentity: packageIdentity,
            path: manifestPath,
            packageKind: packageKind,
            packageLocation: packageLocation,
            defaultLocalization: parsed.defaultLocalization,
            platforms: parsed.platforms,
            version: packageVersion?.version,
            revision: packageVersion?.revision,
            toolsVersion: toolsVersion,
            pkgConfig: parsed.pkgConfig,
            providers: parsed.providers,
            cLanguageStandard: parsed.cLanguageStandard,
            cxxLanguageStandard: parsed.cxxLanguageStandard,
            swiftLanguageVersions: parsed.swiftLanguageVersions,
            dependencies: parsed.dependencies,
            products: products,
            targets: targets,
            traits: parsed.traits,
            pruneDependencies: pruneDependencies
        )
    }
}

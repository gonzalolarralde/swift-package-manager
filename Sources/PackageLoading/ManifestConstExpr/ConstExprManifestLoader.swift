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
import Dispatch
import PackageDescriptionConstExpr
import PackageModel
import SourceControl
import struct TSCBasic.ByteString
import struct TSCUtility.Version

/// Attempts sealed, in-process evaluation of a Package.swift manifest. Every
/// uncertainty is represented by ``ConstExprManifestFallback``; this loader
/// never compiles rewritten source and never emits user-facing diagnostics.
package final class ConstExprManifestLoader: ManifestLoaderProtocol {
    package var delegate: ManifestLoaderDelegate?

    private let configurationProvider: ConstExprBuildConfigurationProvider
    private let pruneDependencies: Bool
    private let environmentOverride: [String: String]?

    package init(
        toolchain: UserToolchain,
        pruneDependencies: Bool = false,
        extraManifestFlags: [String] = [],
        environment: [String: String]? = nil
    ) {
        self.configurationProvider = ConstExprBuildConfigurationProvider(
            toolchain: toolchain,
            extraFlags: extraManifestFlags
        )
        self.pruneDependencies = pruneDependencies
        self.environmentOverride = environment
    }

    package func resetCache(observabilityScope: ObservabilityScope) async {}
    package func purgeCache(observabilityScope: ObservabilityScope) async {}

    package func load(
        manifestPath: AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> Manifest {
        let start = DispatchTime.now()
        delegateQueue.async { [delegate = self.delegate] in
            delegate?.willLoad(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath
            )
        }

        let contents: ByteString
        do {
            contents = try fileSystem.readFileContents(manifestPath)
        } catch {
            throw StringError("could not read package manifest at \(manifestPath): \(error)")
        }
        guard let source = contents.validDescription else {
            throw ConstExprManifestFallback(
                reasonCode: "non-utf8-source",
                detail: "the manifest is not valid UTF-8"
            )
        }
        let manifest = try parse(
            manifestPath: manifestPath,
            source: source,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            delegateQueue: delegateQueue
        )

        delegateQueue.async { [delegate = self.delegate] in
            delegate?.didLoad(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                duration: start.distance(to: .now())
            )
        }
        return manifest
    }

    package func parse(
        manifestPath: AbsolutePath,
        source: String,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem
    ) throws -> Manifest {
        try parse(
            manifestPath: manifestPath,
            source: source,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            delegateQueue: nil
        )
    }

    private func parse(
        manifestPath: AbsolutePath,
        source: String,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        delegateQueue: DispatchQueue?
    ) throws -> Manifest {
        guard manifestToolsVersion >= .v5_9 else {
            throw ConstExprManifestFallback(
                reasonCode: "unsupported-tools-version",
                detail: "the initial registry models PackageDescription 5.9-and-newer APIs"
            )
        }
        let configuration = try configurationProvider.configuration(
            for: manifestToolsVersion
        )
        let activeSourceFile = try ConstExprManifestSource.prepare(
            source,
            fileName: manifestPath.pathString,
            configuration: configuration
        )
        let environment = environmentOverride ?? Dictionary(
            uniqueKeysWithValues: Environment.current.map { ($0.key.rawValue, $0.value) }
        )
        let evaluation = PackageDescriptionConstExprBridge.evaluateManifest(
            sourceFile: activeSourceFile,
            fileName: manifestPath.pathString,
            context: .init(
                packageDirectory: manifestPath.parentDirectory.pathString,
                environment: environment,
                gitInformation: ConstExprManifestSource.usesContextGitInformation(activeSourceFile)
                    ? Self.gitInformation(at: manifestPath.parentDirectory)
                    : nil,
                packageDescriptionVersion: .init(
                    major: manifestToolsVersion.major,
                    minor: manifestToolsVersion.minor,
                    patch: manifestToolsVersion.patch
                ),
                enableSignposts: environment["SWIFTPM_CONSTEXPR_SIGNPOSTS"] == "1"
            )
        )
        let json: String
        switch evaluation {
        case .success(let manifestJSON):
            json = manifestJSON
        case .fallback(let fallback):
            throw ConstExprManifestFallback(
                reasonCode: fallback.reasonCode,
                detail: fallback.detail,
                line: fallback.line,
                column: fallback.column
            )
        }

        do {
            let start = DispatchTime.now()
            delegateQueue?.async { [delegate = self.delegate] in
                delegate?.willParse(
                    packageIdentity: packageIdentity,
                    packageLocation: packageLocation
                )
            }
            let manifest = try ConstExprManifestModel.makeManifest(
                json: json,
                manifestPath: manifestPath,
                toolsVersion: manifestToolsVersion,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                packageVersion: packageVersion,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: fileSystem,
                pruneDependencies: pruneDependencies
            )
            delegateQueue?.async { [delegate = self.delegate] in
                delegate?.didParse(
                    packageIdentity: packageIdentity,
                    packageLocation: packageLocation,
                    duration: start.distance(to: .now())
                )
            }
            return manifest
        } catch {
            throw ConstExprManifestFallback(
                reasonCode: "invalid-manifest-json",
                detail: "the evaluated PackageDescription value could not be loaded: \(error)"
            )
        }
    }

    private static func gitInformation(
        at packageDirectory: AbsolutePath
    ) -> PackageDescriptionConstExprContext.GitInformation? {
        do {
            let repository = GitRepository(path: packageDirectory)
            return .init(
                currentTag: repository.getCurrentTag(),
                currentCommit: try repository.getCurrentRevision().identifier,
                hasUncommittedChanges: repository.hasUncommittedChanges()
            )
        } catch {
            return nil
        }
    }
}

extension ConstExprManifestLoader: ManifestLoaderDelegateConfigurable {}

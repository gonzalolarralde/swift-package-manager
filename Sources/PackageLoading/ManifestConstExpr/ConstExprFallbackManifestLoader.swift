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
import Foundation
import PackageModel
import SourceControl
import struct TSCUtility.Version

package final class ConstExprFallbackManifestLoader: ManifestLoaderProtocol {
    package enum Mode: Sendable {
        case fallback
        case crosscheck
    }

    private let constExprLoader: any ManifestLoaderProtocol
    private let executingLoader: any ManifestLoaderProtocol
    private let mode: Mode
    private let reportFallbacks: Bool
    // A configurable child is allowed to retain its delegate weakly.
    private var phaseForwardingDelegate: ManifestLoaderPhaseForwardingDelegate?

    package var delegate: ManifestLoaderDelegate? {
        didSet {
            let forwardingDelegate = delegate.map(ManifestLoaderPhaseForwardingDelegate.init)
            phaseForwardingDelegate = forwardingDelegate
            (constExprLoader as? any ManifestLoaderDelegateConfigurable)?.delegate = forwardingDelegate
            (executingLoader as? any ManifestLoaderDelegateConfigurable)?.delegate = forwardingDelegate
        }
    }

    package init(
        constExprLoader: any ManifestLoaderProtocol,
        executingLoader: any ManifestLoaderProtocol,
        mode: Mode,
        reportFallbacks: Bool = false
    ) {
        self.constExprLoader = constExprLoader
        self.executingLoader = executingLoader
        self.mode = mode
        self.reportFallbacks = reportFallbacks
    }

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

        let arguments = ManifestLoadArguments(
            manifestPath: manifestPath,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue
        )

        let fastManifest: Manifest
        let fastStart = DispatchTime.now()
        do {
            fastManifest = try await arguments.load(with: constExprLoader)
        } catch let fallback as ConstExprManifestFallback {
            if reportFallbacks {
                observabilityScope.emit(info: fallback.description)
            }
            let executedManifest = try await arguments.load(with: executingLoader)
            return finishLoad(
                executedManifest,
                start: start,
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                delegateQueue: delegateQueue
            )
        }
        guard mode == .crosscheck else {
            return finishLoad(
                fastManifest,
                start: start,
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                delegateQueue: delegateQueue
            )
        }

        let fastDuration = fastStart.distance(to: .now())
        let executionStart = DispatchTime.now()
        let executedManifest = try await arguments.load(with: executingLoader)
        let executionDuration = executionStart.distance(to: .now())
        let fastJSON = try Self.canonicalJSON(fastManifest)
        let executedJSON = try Self.canonicalJSON(executedManifest)
        guard fastJSON == executedJSON else {
            throw CrosscheckError.manifestMismatch(
                path: manifestPath.pathString,
                constExprJSON: fastJSON,
                executedJSON: executedJSON
            )
        }
        observabilityScope.emit(debug: "ConstExpr manifest crosscheck succeeded for '\(manifestPath)' (fast: \(fastDuration), executed: \(executionDuration))")
        return finishLoad(
            fastManifest,
            start: start,
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            manifestPath: manifestPath,
            delegateQueue: delegateQueue
        )
    }

    package func resetCache(observabilityScope: ObservabilityScope) async {
        await constExprLoader.resetCache(observabilityScope: observabilityScope)
        await executingLoader.resetCache(observabilityScope: observabilityScope)
    }

    package func purgeCache(observabilityScope: ObservabilityScope) async {
        await constExprLoader.purgeCache(observabilityScope: observabilityScope)
        await executingLoader.purgeCache(observabilityScope: observabilityScope)
    }

    private static func canonicalJSON(_ manifest: Manifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(manifest), as: UTF8.self)
    }

    private func finishLoad(
        _ manifest: Manifest,
        start: DispatchTime,
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        delegateQueue: DispatchQueue
    ) -> Manifest {
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

    package enum CrosscheckError: Error, CustomStringConvertible {
        case manifestMismatch(path: String, constExprJSON: String, executedJSON: String)

        package var description: String {
            switch self {
            case .manifestMismatch(let path, let constExprJSON, let executedJSON):
                return "ConstExpr manifest for '\(path)' does not match execution: \(constExprJSON) != \(executedJSON)"
            }
        }
    }
}

extension ConstExprFallbackManifestLoader: ManifestLoaderDelegateConfigurable {}

private final class ManifestLoaderPhaseForwardingDelegate: ManifestLoaderDelegate {
    private let delegate: ManifestLoaderDelegate

    init(_ delegate: ManifestLoaderDelegate) {
        self.delegate = delegate
    }

    func willLoad(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {}

    func didLoad(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {}

    func willParse(packageIdentity: PackageIdentity, packageLocation: String) {
        delegate.willParse(packageIdentity: packageIdentity, packageLocation: packageLocation)
    }

    func didParse(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        duration: DispatchTimeInterval
    ) {
        delegate.didParse(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            duration: duration
        )
    }

    func willCompile(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {
        delegate.willCompile(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            manifestPath: manifestPath
        )
    }

    func didCompile(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        delegate.didCompile(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            manifestPath: manifestPath,
            duration: duration
        )
    }

    func willEvaluate(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {
        delegate.willEvaluate(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            manifestPath: manifestPath
        )
    }

    func didEvaluate(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        delegate.didEvaluate(
            packageIdentity: packageIdentity,
            packageLocation: packageLocation,
            manifestPath: manifestPath,
            duration: duration
        )
    }
}

private struct ManifestLoadArguments {
    let manifestPath: AbsolutePath
    let manifestToolsVersion: ToolsVersion
    let packageIdentity: PackageIdentity
    let packageKind: PackageReference.Kind
    let packageLocation: String
    let packageVersion: (version: Version?, revision: String?)?
    let identityResolver: IdentityResolver
    let dependencyMapper: DependencyMapper
    let fileSystem: FileSystem
    let observabilityScope: ObservabilityScope
    let delegateQueue: DispatchQueue

    func load(with loader: any ManifestLoaderProtocol) async throws -> Manifest {
        try await loader.load(
            manifestPath: manifestPath,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue
        )
    }
}

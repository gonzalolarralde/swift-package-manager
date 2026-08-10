//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import PackageLoading
import PackageModel
import SourceControl
import struct TSCUtility.Version
import XCTest

final class ConstExprManifestDelegateTests: XCTestCase {
    func testFastLoadEmitsOnlyLoadAndParseEvents() async throws {
        let loader = try ConstExprManifestTestSupport.makeLoader()
        let delegate = RecordingManifestLoaderDelegate()
        let delegateQueue = DispatchQueue(label: "org.swift.swiftpm.constexpr-delegate.fast")
        loader.delegate = delegate

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/DelegateFast/Package.swift")
        try fileSystem.writeFileContents(
            path,
            string: """
            // swift-tools-version: 6.1
            import PackageDescription
            let package = Package(name: "DelegateFast")
            """
        )

        _ = try await load(
            loader,
            path: path,
            fileSystem: fileSystem,
            delegateQueue: delegateQueue
        )
        delegateQueue.sync {}

        XCTAssertEqual(delegate.events, [.willLoad, .willParse, .didParse, .didLoad])
    }

    func testFallbackEmitsOneLoadPairAndForwardsExecutionPhases() async throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            "import PackageDescription\nlet package = Package(name: \"DelegateFallback\")"
        )
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: DelegateRejectingManifestLoader(),
            executingLoader: DelegateReturningManifestLoader(manifest: manifest),
            mode: .fallback
        )
        let delegate = RecordingManifestLoaderDelegate()
        let delegateQueue = DispatchQueue(label: "org.swift.swiftpm.constexpr-delegate.fallback")
        loader.delegate = delegate

        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/DelegateFallback/Package.swift")
        try fileSystem.writeFileContents(path, string: "unchanged")

        _ = try await load(
            loader,
            path: path,
            fileSystem: fileSystem,
            delegateQueue: delegateQueue
        )
        delegateQueue.sync {}

        XCTAssertEqual(
            delegate.events,
            [
                .willLoad,
                .willCompile,
                .didCompile,
                .willEvaluate,
                .didEvaluate,
                .willParse,
                .didParse,
                .didLoad,
            ]
        )
    }

    private func load(
        _ loader: any ManifestLoaderProtocol,
        path: AbsolutePath,
        fileSystem: FileSystem,
        delegateQueue: DispatchQueue
    ) async throws -> Manifest {
        let identityResolver = DefaultIdentityResolver()
        return try await loader.load(
            manifestPath: path,
            manifestToolsVersion: .v6_1,
            packageIdentity: .plain("fixture"),
            packageKind: .fileSystem(path.parentDirectory),
            packageLocation: path.parentDirectory.pathString,
            packageVersion: nil,
            identityResolver: identityResolver,
            dependencyMapper: DefaultDependencyMapper(identityResolver: identityResolver),
            fileSystem: fileSystem,
            observabilityScope: ObservabilitySystem.makeForTesting().topScope,
            delegateQueue: delegateQueue
        )
    }
}

private enum ManifestDelegateEvent: Equatable {
    case willLoad
    case didLoad
    case willParse
    case didParse
    case willCompile
    case didCompile
    case willEvaluate
    case didEvaluate
}

private final class RecordingManifestLoaderDelegate: ManifestLoaderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ManifestDelegateEvent] = []

    var events: [ManifestDelegateEvent] {
        lock.withLock { storedEvents }
    }

    func willLoad(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {
        append(.willLoad)
    }

    func didLoad(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        append(.didLoad)
    }

    func willParse(packageIdentity: PackageIdentity, packageLocation: String) {
        append(.willParse)
    }

    func didParse(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        duration: DispatchTimeInterval
    ) {
        append(.didParse)
    }

    func willCompile(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {
        append(.willCompile)
    }

    func didCompile(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        append(.didCompile)
    }

    func willEvaluate(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath
    ) {
        append(.willEvaluate)
    }

    func didEvaluate(
        packageIdentity: PackageIdentity,
        packageLocation: String,
        manifestPath: AbsolutePath,
        duration: DispatchTimeInterval
    ) {
        append(.didEvaluate)
    }

    private func append(_ event: ManifestDelegateEvent) {
        lock.withLock { storedEvents.append(event) }
    }
}

private final class DelegateRejectingManifestLoader:
    ManifestLoaderProtocol,
    ManifestLoaderDelegateConfigurable
{
    var delegate: ManifestLoaderDelegate?

    func load(
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
        delegateQueue.async { [delegate] in
            delegate?.willLoad(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath
            )
        }
        throw ConstExprManifestFallback(reasonCode: "expected", detail: "expected")
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

private final class DelegateReturningManifestLoader:
    ManifestLoaderProtocol,
    ManifestLoaderDelegateConfigurable
{
    var delegate: ManifestLoaderDelegate?
    private let manifest: Manifest

    init(manifest: Manifest) {
        self.manifest = manifest
    }

    func load(
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
        delegateQueue.async { [delegate] in
            delegate?.willLoad(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath
            )
            delegate?.willCompile(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath
            )
            delegate?.didCompile(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                duration: .nanoseconds(1)
            )
            delegate?.willEvaluate(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath
            )
            delegate?.didEvaluate(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                duration: .nanoseconds(1)
            )
            delegate?.willParse(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation
            )
            delegate?.didParse(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                duration: .nanoseconds(1)
            )
            delegate?.didLoad(
                packageIdentity: packageIdentity,
                packageLocation: packageLocation,
                manifestPath: manifestPath,
                duration: .nanoseconds(1)
            )
        }
        return manifest
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

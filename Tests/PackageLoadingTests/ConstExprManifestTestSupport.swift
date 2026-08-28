//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import SourceControl

enum ConstExprManifestTestSupport {
    static let manifestPath = AbsolutePath("/ConstExprFixture/Package.swift")

    static func makeLoader(
        environment: [String: String] = [:],
        extraManifestFlags: [String] = []
    ) throws -> ConstExprManifestLoader {
        ConstExprManifestLoader(
            toolchain: try UserToolchain.default,
            extraManifestFlags: extraManifestFlags,
            environment: environment
        )
    }

    static func parse(
        _ source: String,
        toolsVersion: ToolsVersion = .v6_1,
        environment: [String: String] = [:],
        extraManifestFlags: [String] = [],
        fileSystem: FileSystem = InMemoryFileSystem()
    ) throws -> Manifest {
        let identityResolver = DefaultIdentityResolver()
        return try makeLoader(
            environment: environment,
            extraManifestFlags: extraManifestFlags
        ).parse(
            manifestPath: manifestPath,
            source: source,
            manifestToolsVersion: toolsVersion,
            packageIdentity: .plain("fixture"),
            packageKind: .fileSystem(manifestPath.parentDirectory),
            packageLocation: manifestPath.parentDirectory.pathString,
            packageVersion: nil,
            identityResolver: identityResolver,
            dependencyMapper: DefaultDependencyMapper(identityResolver: identityResolver),
            fileSystem: fileSystem
        )
    }

    static func fallback(
        _ source: String,
        toolsVersion: ToolsVersion = .v6_1,
        environment: [String: String] = [:],
        extraManifestFlags: [String] = []
    ) throws -> ConstExprManifestFallback {
        do {
            _ = try parse(
                source,
                toolsVersion: toolsVersion,
                environment: environment,
                extraManifestFlags: extraManifestFlags
            )
            throw UnexpectedSuccess()
        } catch let fallback as ConstExprManifestFallback {
            return fallback
        }
    }

    private struct UnexpectedSuccess: Error {}
}

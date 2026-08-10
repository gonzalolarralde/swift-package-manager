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
import PackageLoading
import PackageModel
import SourceControl
import struct TSCBasic.ByteString
import struct TSCUtility.Version
import XCTest

final class ConstExprManifestFallbackTests: XCTestCase {
    func testFallbackPassesOriginalBytesToExecutingLoader() async throws {
        let source = """
        // swift-tools-version: 6.1
        import PackageDescription

        let package = Package(  name: "OriginalSpacing"  ) // retain me
        """
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/OriginalBytes/Package.swift")
        try fileSystem.writeFileContents(path, string: source)
        let expected = try fileSystem.readFileContents(path)
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: RejectingManifestLoader(expected: expected),
            executingLoader: OriginalBytesManifestLoader(expected: expected),
            mode: .fallback
        )

        do {
            _ = try await load(loader, path: path, fileSystem: fileSystem)
            XCTFail("the sentinel executing loader should stop the test")
        } catch OriginalBytesManifestLoader.Result.observedOriginal {
            // Expected.
        }
    }

    func testFallbackReasonIsSilentByDefault() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try ConstExprManifestTestSupport.parse(
            "import PackageDescription\nlet package = Package(name: \"Fallback\")"
        )
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: AlwaysFallbackManifestLoader(),
            executingLoader: ReturningManifestLoader(manifest),
            mode: .fallback
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/Silent/Package.swift")
        try fileSystem.writeFileContents(path, string: "unchanged")

        _ = try await load(
            loader,
            path: path,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )
        XCTAssertTrue(observability.diagnostics.isEmpty, observability.diagnostics.description)
    }

    func testCrosscheckAcceptsEqualCanonicalManifests() async throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            "import PackageDescription\nlet package = Package(name: \"Equal\")"
        )
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ReturningManifestLoader(manifest),
            executingLoader: ReturningManifestLoader(manifest),
            mode: .crosscheck
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/Crosscheck/Package.swift")
        try fileSystem.writeFileContents(path, string: "unused")

        let result = try await load(loader, path: path, fileSystem: fileSystem)
        XCTAssertEqual(result.displayName, "Equal")
    }

    func testCrosscheckReportsMismatch() async throws {
        let fast = try ConstExprManifestTestSupport.parse(
            "import PackageDescription\nlet package = Package(name: \"Fast\")"
        )
        let executed = try ConstExprManifestTestSupport.parse(
            "import PackageDescription\nlet package = Package(name: \"Executed\")"
        )
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ReturningManifestLoader(fast),
            executingLoader: ReturningManifestLoader(executed),
            mode: .crosscheck
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/Mismatch/Package.swift")
        try fileSystem.writeFileContents(path, string: "unused")

        do {
            _ = try await load(loader, path: path, fileSystem: fileSystem)
            XCTFail("expected a crosscheck mismatch")
        } catch is ConstExprFallbackManifestLoader.CrosscheckError {
            // Expected.
        }
    }

    func testToolsVersionSixMatchesExecution() async throws {
        let toolchain = try UserToolchain.default
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ConstExprManifestLoader(toolchain: toolchain),
            executingLoader: ManifestLoader(toolchain: toolchain),
            mode: .crosscheck
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/ToolsVersionSix/Package.swift")
        try fileSystem.writeFileContents(
            path,
            string: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "Six",
                products: [.library(name: "Six", targets: ["Six"])],
                targets: [.target(name: "Six")]
            )
            """
        )

        let manifest = try await load(
            loader,
            path: path,
            toolsVersion: .v6_0,
            fileSystem: fileSystem
        )
        XCTAssertEqual(manifest.displayName, "Six")
    }

    func testToolsVersionFiveMatchesExecution() async throws {
        let toolchain = try UserToolchain.default
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ConstExprManifestLoader(toolchain: toolchain),
            executingLoader: ManifestLoader(toolchain: toolchain),
            mode: .crosscheck
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/ToolsVersionFive/Package.swift")
        try fileSystem.writeFileContents(
            path,
            string: """
            // swift-tools-version: 5.0
            import PackageDescription
            let linux = BuildSettingCondition.when(platforms: [.linux])
            let package = Package(
                name: "Five",
                products: [.library(name: "Five", targets: ["Five"])],
                dependencies: [
                    .package(url: "https://example.test/remote.git", .branch("main")),
                ],
                targets: [
                    .target(
                        name: "Five",
                        swiftSettings: [.define("LINUX", linux)]
                    ),
                ]
            )
            """
        )

        let manifest = try await load(
            loader,
            path: path,
            toolsVersion: .v5,
            fileSystem: fileSystem
        )
        XCTAssertEqual(manifest.displayName, "Five")
    }

    func testCompilerSuppliesDiagnosticsAfterFastPathMiss() async throws {
        let toolchain = try UserToolchain.default
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ConstExprManifestLoader(toolchain: toolchain),
            executingLoader: ManifestLoader(toolchain: toolchain),
            mode: .fallback
        )
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/CompilerDiagnostics/Package.swift")
        try fileSystem.writeFileContents(
            path,
            string: """
            // swift-tools-version: 6.1
            import PackageDescription
            let package = Package(name: nameFromUnknownModule)
            """
        )

        do {
            _ = try await load(loader, path: path, fileSystem: fileSystem)
            XCTFail("expected compiler diagnostics")
        } catch ManifestParseError.invalidManifestFormat(let message, _, _) {
            XCTAssertTrue(
                message.contains("cannot find 'nameFromUnknownModule' in scope"),
                message
            )
        }
    }

    func testDeprecatedLanguageStandardWarningComesFromCompiler() async throws {
        let toolchain = try UserToolchain.default
        let loader = ConstExprFallbackManifestLoader(
            constExprLoader: ConstExprManifestLoader(toolchain: toolchain),
            executingLoader: ManifestLoader(toolchain: toolchain),
            mode: .fallback
        )
        let observability = ObservabilitySystem.makeForTesting()
        let fileSystem = InMemoryFileSystem()
        let path = AbsolutePath("/DeprecatedLanguageStandard/Package.swift")
        try fileSystem.writeFileContents(
            path,
            string: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "Deprecated", cxxLanguageStandard: .cxx1z)
            """
        )

        let manifest = try await load(
            loader,
            path: path,
            toolsVersion: .v6_0,
            fileSystem: fileSystem,
            observabilityScope: observability.topScope
        )
        XCTAssertEqual(manifest.displayName, "Deprecated")
        XCTAssertTrue(
            observability.diagnostics.contains {
                $0.message.contains("cxx1z") && $0.message.contains("deprecated")
            },
            observability.diagnostics.description
        )
    }

    private func load(
        _ loader: any ManifestLoaderProtocol,
        path: AbsolutePath,
        toolsVersion: ToolsVersion = .v6_1,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope = ObservabilitySystem.makeForTesting().topScope
    ) async throws -> Manifest {
        let identityResolver = DefaultIdentityResolver()
        return try await loader.load(
            manifestPath: path,
            manifestToolsVersion: toolsVersion,
            packageIdentity: .plain("fixture"),
            packageKind: .fileSystem(path.parentDirectory),
            packageLocation: path.parentDirectory.pathString,
            packageVersion: nil,
            identityResolver: identityResolver,
            dependencyMapper: DefaultDependencyMapper(identityResolver: identityResolver),
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: .global()
        )
    }
}

private final class RejectingManifestLoader: ManifestLoaderProtocol {
    let expected: ByteString

    init(expected: ByteString) {
        self.expected = expected
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
        guard try fileSystem.readFileContents(manifestPath) == expected else {
            throw StringError("the ConstExpr loader did not receive the original bytes")
        }
        throw ConstExprManifestFallback(reasonCode: "test-fallback", detail: "expected")
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

private final class OriginalBytesManifestLoader: ManifestLoaderProtocol {
    enum Result: Error { case observedOriginal }
    let expected: ByteString

    init(expected: ByteString) {
        self.expected = expected
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
        guard try fileSystem.readFileContents(manifestPath) == expected else {
            throw StringError("fallback changed the manifest bytes")
        }
        throw Result.observedOriginal
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

private final class AlwaysFallbackManifestLoader: ManifestLoaderProtocol {
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
        throw ConstExprManifestFallback(reasonCode: "expected", detail: "expected")
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

private final class ReturningManifestLoader: ManifestLoaderProtocol {
    let manifest: Manifest

    init(_ manifest: Manifest) {
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
        manifest
    }

    func resetCache(observabilityScope: ObservabilityScope) async {}
    func purgeCache(observabilityScope: ObservabilityScope) async {}
}

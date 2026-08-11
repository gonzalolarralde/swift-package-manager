//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageLoading
import XCTest

final class ConstExprManifestIsolationTests: XCTestCase {
    private let contextualManifest = """
        import PackageDescription
        let package = Package(name: Context.environment["FIXTURE_NAME"]!)
        """

    func testSequentialEvaluationsUseDistinctContexts() throws {
        let first = try ConstExprManifestTestSupport.parse(
            contextualManifest,
            environment: ["FIXTURE_NAME": "FirstContext"]
        )
        let second = try ConstExprManifestTestSupport.parse(
            contextualManifest,
            environment: ["FIXTURE_NAME": "SecondContext"]
        )

        XCTAssertEqual(first.displayName, "FirstContext")
        XCTAssertEqual(second.displayName, "SecondContext")
    }

    func testConcurrentEvaluationsKeepTaskLocalContextsIsolated() async throws {
        let names = (0..<16).map { "Context\($0)" }
        let observed = try await withThrowingTaskGroup(of: String.self) { group in
            for name in names {
                group.addTask { [contextualManifest] in
                    try ConstExprManifestTestSupport.parse(
                        contextualManifest,
                        environment: ["FIXTURE_NAME": name]
                    ).displayName
                }
            }

            var results: [String] = []
            for try await name in group {
                results.append(name)
            }
            return results
        }

        XCTAssertEqual(observed.sorted(), names.sorted())
    }

    func testKnownUnusedGlobalIsCertifiedAndAccepted() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let knownButUnused = ["constant", "value"]
            let package = Package(name: "KnownUnused")
            """
        )

        XCTAssertEqual(manifest.displayName, "KnownUnused")
    }

    func testEffectfulUnusedGlobalFallsBackDuringCertification() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let unused = print("must not execute")
            let package = Package(name: "EffectfulUnused")
            """
        )

        XCTAssertEqual(fallback.reasonCode, "unsupported-source")
    }

    func testPreconditionedVersionInitializerIsNeverSpeculated() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let invalid = Version(-1, 0, 0)
            let package = Package(name: "InvalidVersion")
            """
        )

        XCTAssertEqual(fallback.reasonCode, "unsupported-source")
    }

    func testMalformedInactiveRegionDoesNotBlockFastPath() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            #if false
            let broken = Package(name: "Inactive"
            #endif
            let package = Package(name: "Active")
            """
        )

        XCTAssertEqual(manifest.displayName, "Active")
    }
}

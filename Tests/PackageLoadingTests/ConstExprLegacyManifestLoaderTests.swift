//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

@testable import PackageLoading
import XCTest

final class ConstExprLegacyManifestLoaderTests: XCTestCase {
    func testToolsVersionFiveNineOmittedDefaults() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(name: "LegacyDefaults")
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(manifest.displayName, "LegacyDefaults")
        XCTAssertTrue(manifest.products.isEmpty)
        XCTAssertTrue(manifest.targets.isEmpty)
        XCTAssertNil(manifest.swiftLanguageVersions)
    }

    func testLegacyLabelsMaterializeTheCurrentPackageModel() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let legacyVersions: [SwiftVersion] = [.v4_2, .v5]
            let package = Package(
                name: "LegacyLabels",
                defaultLocalization: "en",
                products: [.library(name: "LegacyLabels", targets: ["LegacyLabels"])],
                targets: [.target(name: "LegacyLabels")],
                swiftLanguageVersions: legacyVersions,
                cLanguageStandard: .c11,
                cxxLanguageStandard: .cxx17
            )
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(manifest.displayName, "LegacyLabels")
        XCTAssertEqual(manifest.defaultLocalization, "en")
        XCTAssertEqual(manifest.swiftLanguageVersions?.map(\.rawValue), ["4.2", "5"])
        XCTAssertEqual(manifest.cLanguageStandard, "c11")
        XCTAssertEqual(manifest.cxxLanguageStandard, "c++17")
    }

    func testCachedNetworkingManifest() throws {
        // https://github.com/freshOS/Networking at the pinned corpus revision.
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            // swift-tools-version:5.9
            // The swift-tools-version declares the minimum version of Swift required to build this package.

            import PackageDescription

            let package = Package(
                name: "Networking",
                platforms: [.iOS(.v13), .macOS(.v10_15), .watchOS(.v6), .tvOS(.v13)],
                products: [.library(name: "Networking", targets: ["Networking"])],
                targets: [
                    .target(name: "Networking", path: "Sources", resources: [.copy("PrivacyInfo.xcprivacy")]),
                    .testTarget(name: "NetworkingTests", dependencies: ["Networking"])
                ]
            )
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(manifest.displayName, "Networking")
        XCTAssertEqual(manifest.targets.map(\.name), ["Networking", "NetworkingTests"])
    }

    func testCachedStatusItemControllerManifest() throws {
        // https://github.com/hexedbits/StatusItemController at the pinned corpus revision.
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            // swift-tools-version:5.9
            import PackageDescription

            let package = Package(
                name: "StatusItemController",
                platforms: [
                    .macOS(.v11)
                ],
                products: [
                    .library(
                        name: "StatusItemController",
                        targets: ["StatusItemController"])
                ],
                targets: [
                    .target(
                        name: "StatusItemController",
                        path: "Sources"),
                    .testTarget(name: "StatusItemControllerTests",
                                dependencies: ["StatusItemController"],
                                path: "Tests")
                ],
                swiftLanguageVersions: [.v5]
            )
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(manifest.displayName, "StatusItemController")
        XCTAssertEqual(manifest.swiftLanguageVersions?.map(\.rawValue), ["5"])
    }

    func testCachedSafeGlobalMacroAndRangeManifest() throws {
        // https://github.com/Frizlab/SafeGlobal at the pinned corpus revision.
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            // swift-tools-version: 5.9
            import PackageDescription
            import CompilerPluginSupport

            let swiftSettings: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

            let package = Package(
                name: "SafeGlobal",
                platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
                products: [
                    .library(name: "SafeGlobal", targets: ["SafeGlobal"]),
                ],
                dependencies: [
                    .package(
                        url: "https://github.com/swiftlang/swift-syntax.git",
                        "509.0.0"..<"604.0.0"
                    ),
                ],
                targets: [
                    .macro(
                        name: "SafeGlobalMacros",
                        dependencies: [
                            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                            .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
                        ],
                        swiftSettings: swiftSettings
                    ),
                    .target(
                        name: "SafeGlobal",
                        dependencies: ["SafeGlobalMacros"],
                        swiftSettings: swiftSettings
                    ),
                ]
            )
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(manifest.displayName, "SafeGlobal")
        XCTAssertEqual(manifest.dependencies.count, 1)
        XCTAssertEqual(manifest.targets.map(\.name), ["SafeGlobalMacros", "SafeGlobal"])
    }

    func testDeprecatedLegacyInitializerIsUnavailableAtToolsVersionSix() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "Deprecated", swiftLanguageVersions: [.v5])
            """,
            toolsVersion: .v6_0
        )

        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testDeprecatedPADLDependencyOverloadRemainsACompilerFallback() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(
                name: "LVGL",
                dependencies: [
                    .package(
                        url: "https://github.com/lhoward/AsyncExtensions",
                        .branch("linux")
                    ),
                ]
            )
            """,
            toolsVersion: .v5_9
        )

        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testToolsVersionBeforeFiveNineRemainsAnExplicitMiss() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "TooOld")
            """,
            toolsVersion: .v5_8
        )

        XCTAssertEqual(fallback.reasonCode, "unsupported-tools-version")
    }

    func testLegacyInitializerSessionStateResetsAfterFallback() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let candidates = [Package(name: "First"), Package(name: "Second")]
            let package = candidates[0]
            """,
            toolsVersion: .v5_9
        )
        XCTAssertEqual(fallback.reasonCode, "package-initializer-count")

        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(name: "AfterLegacyFallback")
            """,
            toolsVersion: .v5_9
        )
        XCTAssertEqual(manifest.displayName, "AfterLegacyFallback")
    }
}

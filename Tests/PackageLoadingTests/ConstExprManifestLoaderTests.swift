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

final class ConstExprManifestLoaderTests: XCTestCase {
    func testRepresentativeGraph() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription

            let targetNames = ["Core"]
            let commonSwiftSettings = [SwiftSetting.define("FEATURE")]
            let package = Package(
                name: "Fixture",
                defaultLocalization: "en",
                platforms: [.macOS(.v13), .iOS(.v16)],
                products: [.library(name: "Fixture", targets: targetNames)],
                dependencies: [
                    .package(url: "https://example.com/dependency.git", from: "1.2.3"),
                ],
                targets: [
                    .target(
                        name: "Core",
                        resources: [.process("Resources")],
                        swiftSettings: commonSwiftSettings
                    ),
                ]
            )
            """
        )

        XCTAssertEqual(manifest.displayName, "Fixture")
        XCTAssertEqual(manifest.products.map(\.name), ["Fixture"])
        XCTAssertEqual(manifest.targets.map(\.name), ["Core"])
        XCTAssertEqual(manifest.dependencies.count, 1)
    }

    func testContextualDotInit() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package: Package = .init(name: "DotInit")
            """
        )
        XCTAssertEqual(manifest.displayName, "DotInit")
    }

    func testIfConfigAndInjectedContext() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            #if swift(>=6.0)
            let name = Context.environment["CONSTEXPR_FIXTURE"]!
            #else
            let name = unknownInactiveBranch
            #endif
            let package = Package(name: name)
            """,
            environment: ["CONSTEXPR_FIXTURE": "Configured"]
        )
        XCTAssertEqual(manifest.displayName, "Configured")
    }

    func testIfConfigUsesManifestCompilerFlags() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            #if CONSTEXPR_MANIFEST_FLAG
            let name = "Flagged"
            #else
            let name = unknownInactiveBranch
            #endif
            let package = Package(name: name)
            """,
            extraManifestFlags: ["-D", "CONSTEXPR_MANIFEST_FLAG"]
        )
        XCTAssertEqual(manifest.displayName, "Flagged")
    }

    func testGitInformationDetectionUsesActiveSyntax() {
        XCTAssertTrue(ConstExprManifestSource.usesContextGitInformation(in: """
        import PackageDescription
        let info = Context /* trivia */ . gitInformation
        let package = Package(name: info!.currentCommit)
        """))
        XCTAssertFalse(ConstExprManifestSource.usesContextGitInformation(in: """
        import PackageDescription
        // Context.gitInformation must not trigger repository I/O.
        let package = Package(name: "NoGitProbe")
        """))
    }

    func testBuildSettingsAndConditions() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let condition = BuildSettingCondition.when(
                platforms: [.linux],
                configuration: .release
            )
            let package = Package(
                name: "Settings",
                targets: [
                    .target(
                        name: "Settings",
                        cSettings: [.define("C_FLAG", to: "1", condition)],
                        cxxSettings: [.headerSearchPath("include")],
                        swiftSettings: [.enableUpcomingFeature("ExistentialAny")],
                        linkerSettings: [.linkedLibrary("sqlite3")]
                    ),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.targets.map(\.name), ["Settings"])
    }

    func testCurrentConcurrencySettings() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let settings: [SwiftSetting] = [
                .strictMemorySafety(),
                .defaultIsolation(MainActor.self),
                .defaultIsolation(nil),
            ]
            let package = Package(
                name: "ConcurrencySettings",
                targets: [
                    .target(name: "ConcurrencySettings", swiftSettings: settings),
                ]
            )
            """,
            toolsVersion: .v6_2
        )
        XCTAssertEqual(manifest.targets.map(\.name), ["ConcurrencySettings"])
    }

    func testCurrentLanguageModesAndStandards() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "Languages",
                targets: [
                    .target(
                        name: "Languages",
                        swiftSettings: [.swiftLanguageMode(.v5)]
                    ),
                ],
                swiftLanguageModes: [.v5, .v6],
                cLanguageStandard: .c11,
                cxxLanguageStandard: .cxx20
            )
            """,
            toolsVersion: .v6_0
        )
        XCTAssertEqual(manifest.displayName, "Languages")
        XCTAssertEqual(manifest.targets.map(\.name), ["Languages"])
    }

    func testDeprecatedLanguageStandardFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "Deprecated", cxxLanguageStandard: .cxx1z)
            """,
            toolsVersion: .v6_0
        )
        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testContextualVersionRangeFactory() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let lower: Version = "1.2.3"
            let range: Range<Version> = .upToNextMajor(from: lower)
            let package = Package(
                name: "Ranges",
                dependencies: [
                    .package(
                        url: "https://example.com/range.git",
                        range
                    ),
                    .package(id: "scope.package", range),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.dependencies.count, 2)
    }

    func testInlineContextualVersionRangeFactory() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "InlineRange",
                dependencies: [
                    .package(
                        url: "https://example.com/range.git",
                        .upToNextMajor(from: "2.27.0")
                    ),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.dependencies.count, 1)
    }

    func testInlineHalfOpenStringVersionRange() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "InlineStringRange",
                dependencies: [
                    .package(
                        url: "https://example.com/range.git",
                        "509.0.0" ..< "605.0.0"
                    ),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.dependencies.count, 1)
    }

    func testPluginsAndMacroTarget() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            import CompilerPluginSupport
            let package = Package(
                name: "Plugins",
                targets: [
                    .target(name: "Core", plugins: [.plugin(name: "Generate")]),
                    .macro(name: "Macros"),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.targets.map(\.name), ["Core", "Macros"])
    }

    func testCurrentPlatformConstants() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "Platforms",
                platforms: [
                    .macOS(.v15),
                    .iOS(.v18),
                    .tvOS(.v18),
                    .watchOS(.v11),
                    .driverKit(.v24),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.displayName, "Platforms")
    }

    func testStringPlatformVersions() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "StringPlatforms",
                platforms: [
                    .macOS("13.0"),
                    .macCatalyst("16.0"),
                    .iOS("16.0"),
                    .tvOS("16.0"),
                    .watchOS("9.0"),
                    .visionOS("1.0"),
                    .driverKit("22.0"),
                ]
            )
            """,
            toolsVersion: .v6_2
        )
        XCTAssertEqual(manifest.displayName, "StringPlatforms")
    }

    func testDirectTargetDependencyEnumCase() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "DirectTargetDependency",
                targets: [
                    .target(name: "Core"),
                    .target(
                        name: "Feature",
                        dependencies: [
                            .targetItem(name: "Core", condition: nil),
                        ]
                    ),
                ]
            )
            """,
            toolsVersion: .v6_2
        )
        XCTAssertEqual(manifest.targets.map(\.name), ["Core", "Feature"])
    }

    func testPlatformConstantsBeforeDeprecationBoundary() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "EarlierPlatforms",
                platforms: [
                    .macOS(.v11),
                    .iOS(.v14),
                    .tvOS(.v14),
                    .watchOS(.v7),
                ]
            )
            """
        )
        XCTAssertEqual(manifest.displayName, "EarlierPlatforms")
    }

    func testDeprecatedPlatformConstantFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(
                name: "DeprecatedPlatform",
                platforms: [.watchOS(.v4)]
            )
            """,
            toolsVersion: .v6_3
        )
        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testDeprecatedPackageInitializerFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "DeprecatedInit", swiftLanguageVersions: [.v6])
            """,
            toolsVersion: .v6_0
        )
        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testMissingImportFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            "let package = Package(name: \"NoImport\")"
        )
        XCTAssertEqual(fallback.reasonCode, "missing-package-description-import")
    }

    func testReferencedUnknownFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: nameFromAnotherModule)
            """
        )
        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testUnreferencedUnknownFallsBackDuringCertification() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let unrelated = valueFromAnotherModule
            let package = Package(name: "Known")
            """
        )
        XCTAssertEqual(fallback.reasonCode, "unsupported-source")
    }

    func testMutationFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "Mutable")
            package.targets.append(.target(name: "Later"))
            """
        )
        XCTAssertEqual(fallback.reasonCode, "unsupported-top-level")
    }

    func testExactlyOnePackageInitializerAndSessionReset() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let candidates = [Package(name: "First"), Package(name: "Second")]
            let package = candidates[0]
            """
        )
        XCTAssertEqual(fallback.reasonCode, "package-initializer-count")

        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(name: "AfterFallback")
            """
        )
        XCTAssertEqual(manifest.displayName, "AfterFallback")
    }

    func testMalformedSourceFallsBack() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "Broken"
            """
        )
        XCTAssertEqual(fallback.reasonCode, "malformed-source")
    }

    func testToolsVersionSixPackageInitializer() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "Six",
                products: [.library(name: "Six", targets: ["Six"])],
                targets: [.target(name: "Six")]
            )
            """,
            toolsVersion: .v6_0
        )
        XCTAssertEqual(manifest.displayName, "Six")
        XCTAssertEqual(manifest.products.map(\.name), ["Six"])
        XCTAssertEqual(manifest.targets.map(\.name), ["Six"])
    }

}

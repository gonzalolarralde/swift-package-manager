//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

@testable import PackageLoading
import PackageModel
import XCTest

final class ConstExprHistoricalManifestLoaderTests: XCTestCase {
    func testToolsFiveZeroPackageTargetsSettingsAndRequirements() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let linux = BuildSettingCondition.when(platforms: [.linux])
            let package = Package(
                name: "FiveZero",
                platforms: [.macOS(.v10_10)],
                products: [.library(name: "FiveZero", targets: ["Core"])],
                dependencies: [
                    .package(url: "https://example.test/remote.git", .branch("main")),
                ],
                targets: [
                    .target(
                        name: "Core",
                        dependencies: [
                            .target(name: "Utility"),
                            .product(name: "Remote"),
                            .byName(name: "Shared"),
                        ],
                        swiftSettings: [.define("LINUX", linux)]
                    ),
                    .testTarget(name: "CoreTests", dependencies: ["Core"]),
                ],
                swiftLanguageVersions: [.v5]
            )
            """,
            toolsVersion: .v5
        )

        XCTAssertEqual(manifest.displayName, "FiveZero")
        XCTAssertEqual(manifest.targets.map(\.name), ["Core", "CoreTests"])
        XCTAssertEqual(manifest.dependencies.count, 1)
        XCTAssertEqual(manifest.swiftLanguageVersions?.map(\.rawValue), ["5"])
    }

    func testToolsFiveTwoNamedDependenciesAndProducts() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveTwo",
                dependencies: [
                    .package(name: "Remote", url: "https://example.test/remote.git", from: "1.2.3"),
                    .package(name: "Local", path: "../Local"),
                ],
                targets: [
                    .target(
                        name: "FiveTwo",
                        dependencies: [.product(name: "Remote", package: "Remote")]
                    ),
                ]
            )
            """,
            toolsVersion: .v5_2
        )

        XCTAssertEqual(manifest.displayName, "FiveTwo")
        XCTAssertEqual(manifest.dependencies.count, 2)
        XCTAssertEqual(manifest.targets.map(\.name), ["FiveTwo"])
    }

    func testToolsFiveOneRawLanguageStandardAndFavoredVersionRange() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveOne",
                dependencies: [
                    .package(
                        url: "https://example.test/remote.git",
                        .upToNextMinor(from: "0.3.0")
                    ),
                ],
                targets: [.target(name: "FiveOne")],
                cxxLanguageStandard: CXXLanguageStandard(rawValue: "c++20")
            )
            """,
            toolsVersion: ToolsVersion(version: "5.1.0")
        )

        XCTAssertEqual(manifest.displayName, "FiveOne")
        XCTAssertEqual(manifest.dependencies.count, 1)
        XCTAssertEqual(manifest.cxxLanguageStandard, "c++20")
    }

    func testToolsFiveThreeResourcesBinaryTargetsAndConditions() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let linux = TargetDependencyCondition.when(platforms: [.linux])
            let package = Package(
                name: "FiveThree",
                defaultLocalization: "en",
                products: [.library(name: "FiveThree", targets: ["FiveThree"])],
                targets: [
                    .target(
                        name: "FiveThree",
                        dependencies: [
                            .product(name: "Remote", package: "remote", condition: linux),
                        ],
                        resources: [.process("Resources")]
                    ),
                    .binaryTarget(name: "Binary", path: "Artifacts/Binary.xcframework"),
                    .testTarget(
                        name: "FiveThreeTests",
                        dependencies: ["FiveThree"],
                        resources: [.copy("Fixtures")]
                    ),
                ]
            )
            """,
            toolsVersion: .v5_3
        )

        XCTAssertEqual(manifest.displayName, "FiveThree")
        XCTAssertEqual(manifest.defaultLocalization, "en")
        XCTAssertEqual(manifest.targets.map(\.name), ["FiveThree", "Binary", "FiveThreeTests"])
    }

    func testToolsFiveFourExecutableTarget() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveFour",
                products: [.executable(name: "tool", targets: ["tool"])],
                targets: [
                    .executableTarget(
                        name: "tool",
                        resources: [.copy("Configuration.json")]
                    ),
                ]
            )
            """,
            toolsVersion: .v5_4
        )

        XCTAssertEqual(manifest.displayName, "FiveFour")
        XCTAssertEqual(manifest.products.map(\.name), ["tool"])
        XCTAssertEqual(manifest.targets.map(\.name), ["tool"])
    }

    func testToolsFiveFivePluginsAndSpecificRequirements() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveFive",
                products: [.plugin(name: "Generator", targets: ["Generator"])],
                dependencies: [
                    .package(url: "https://example.test/branch.git", branch: "main"),
                    .package(url: "https://example.test/revision.git", revision: "abc123"),
                ],
                targets: [
                    .plugin(name: "Generator", capability: .buildTool()),
                    .target(name: "Client", plugins: [.plugin(name: "Generator")]),
                ]
            )
            """,
            toolsVersion: .v5_5
        )

        XCTAssertEqual(manifest.displayName, "FiveFive")
        XCTAssertEqual(manifest.dependencies.count, 2)
        XCTAssertEqual(manifest.targets.map(\.name), ["Generator", "Client"])
    }

    func testToolsFiveSixExactDependencyAndConditions() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let release = BuildSettingCondition.when(configuration: .release)
            let package = Package(
                name: "FiveSix",
                dependencies: [
                    .package(url: "https://example.test/exact.git", exact: "1.2.3"),
                ],
                targets: [
                    .target(
                        name: "FiveSix",
                        linkerSettings: [.linkedLibrary("sqlite3", release)]
                    ),
                ]
            )
            """,
            toolsVersion: .v5_6
        )

        XCTAssertEqual(manifest.displayName, "FiveSix")
        XCTAssertEqual(manifest.dependencies.count, 1)
    }

    func testToolsFiveSevenRegistryDependencyAndModuleAliases() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveSeven",
                dependencies: [.package(id: "example.remote", from: "1.0.0")],
                targets: [
                    .target(
                        name: "FiveSeven",
                        dependencies: [
                            .product(
                                name: "Remote",
                                package: "remote",
                                moduleAliases: ["RemoteCore": "LocalCore"]
                            ),
                        ]
                    ),
                    .plugin(
                        name: "CommandPlugin",
                        capability: .command(
                            intent: .custom(verb: "format", description: "Format sources"),
                            permissions: [
                                .writeToPackageDirectory(reason: "Update formatted sources"),
                            ]
                        )
                    ),
                ]
            )
            """,
            toolsVersion: .v5_7
        )

        XCTAssertEqual(manifest.displayName, "FiveSeven")
        XCTAssertEqual(manifest.dependencies.count, 1)
        XCTAssertEqual(manifest.targets.map(\.name), ["FiveSeven", "CommandPlugin"])
    }

    func testToolsFiveEightUpcomingFeature() throws {
        let manifest = try ConstExprManifestTestSupport.parse(
            """
            import PackageDescription
            let package = Package(
                name: "FiveEight",
                targets: [
                    .target(
                        name: "FiveEight",
                        swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
                    ),
                ]
            )
            """,
            toolsVersion: .v5_8
        )

        XCTAssertEqual(manifest.displayName, "FiveEight")
        XCTAssertEqual(manifest.targets.map(\.name), ["FiveEight"])
    }

    func testDeprecatedRequirementSpellingFallsBackAtFiveSix() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(
                name: "DeprecatedRequirement",
                dependencies: [
                    .package(url: "https://example.test/remote.git", .branch("main")),
                ]
            )
            """,
            toolsVersion: .v5_6
        )

        XCTAssertEqual(fallback.reasonCode, "unresolved-binding")
    }

    func testMutationStillFallsBackAtFiveZero() throws {
        let fallback = try ConstExprManifestTestSupport.fallback(
            """
            import PackageDescription
            let package = Package(name: "Mutable")
            package.targets.append(.target(name: "Added"))
            """,
            toolsVersion: .v5
        )

        XCTAssertEqual(fallback.reasonCode, "unsupported-top-level")
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

import Basics
import PackageLoading
@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
@testable import PackageGraph
@_spi(SwiftPMInternal)
@testable import PackageModel
@testable import SPMBuildCore

import _InternalBuildTestSupport
import _InternalTestSupport
import Testing

@Suite
struct ProductBuilderResolutionTests {
    @Test
    func externalBuilderUsesManifestDependencyName() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Support/Plugins/RP2350Builder/Plugin.swift",
        ])
        let dependency = PackageDependency.fileSystem(
            identity: .plain("support"),
            nameForTargetDependencyResolutionOnly: "BoardSupport",
            path: "/Support",
            productFilter: .specific(["RP2350Builder"])
        )
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    dependencies: [dependency],
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "RP2350Builder",
                                builderPluginPackage: "BoardSupport"
                            )
                        ),
                    ],
                    targets: [try TargetDescription(name: "FirmwareCore")]
                ),
                .createFileSystemManifest(
                    displayName: "actual-support-identity",
                    path: "/Support",
                    toolsVersion: .v6_3,
                    products: [
                        try ProductDescription(
                            name: "RP2350Builder",
                            type: .plugin,
                            targets: ["RP2350Builder"]
                        ),
                    ],
                    targets: [
                        try TargetDescription(
                            name: "RP2350Builder",
                            type: .plugin,
                            pluginCapability: .productBuilder
                        ),
                    ]
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        let plugin = try graph.productBuilderPlugin(for: product)
        #expect(plugin.name == "RP2350Builder")
        #expect(plugin.packageIdentity == .plain("support"))
    }

    @Test
    func wrongPluginCapabilityIsRejected() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Firmware/Plugins/FirmwareBuilder/Plugin.swift",
        ])
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "FirmwareBuilder"
                            )
                        ),
                    ],
                    targets: [
                        try TargetDescription(name: "FirmwareCore"),
                        try TargetDescription(
                            name: "FirmwareBuilder",
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        #expect(throws: StringError(
            "builder plug-in 'FirmwareBuilder' for artifact product 'Firmware' "
                + "must declare the '.productBuilder' capability"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    @Test
    func unknownBuilderPackageIsRejected() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
        ])
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "FirmwareBuilder",
                                builderPluginPackage: "MissingSupport"
                            )
                        ),
                    ],
                    targets: [try TargetDescription(name: "FirmwareCore")]
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        #expect(throws: StringError(
            "artifact product 'Firmware' references builder plug-in package 'MissingSupport', "
                + "which is not a direct dependency of package 'Firmware'"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    @Test
    func ambiguousBuilderPackageIsRejected() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/board-support/Plugins/DashedBuilder/Plugin.swift",
            "/boardsupport/Plugins/CompactBuilder/Plugin.swift",
        ])
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    dependencies: [
                        .fileSystem(
                            identity: .plain("board-support"),
                            nameForTargetDependencyResolutionOnly: "DashedSupport",
                            path: "/board-support",
                            productFilter: .specific(["DashedBuilder"])
                        ),
                        .fileSystem(
                            identity: .plain("boardsupport"),
                            nameForTargetDependencyResolutionOnly: "CompactSupport",
                            path: "/boardsupport",
                            productFilter: .specific(["CompactBuilder"])
                        ),
                    ],
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "FirmwareBuilder",
                                builderPluginPackage: "BoardSupport"
                            )
                        ),
                    ],
                    targets: [try TargetDescription(name: "FirmwareCore")]
                ),
                try Self.builderPackageManifest(
                    displayName: "BoardSupport",
                    path: "/board-support",
                    pluginName: "DashedBuilder"
                ),
                try Self.builderPackageManifest(
                    displayName: "DifferentSupport",
                    path: "/boardsupport",
                    pluginName: "CompactBuilder"
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        #expect(throws: StringError(
            "artifact product 'Firmware' has an ambiguous builder plug-in package reference 'BoardSupport'"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    @Test
    func unknownBuilderPluginIsRejected() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Support/Plugins/OtherBuilder/Plugin.swift",
        ])
        let dependency = PackageDependency.fileSystem(
            identity: .plain("support"),
            nameForTargetDependencyResolutionOnly: "BoardSupport",
            path: "/Support",
            productFilter: .specific(["OtherBuilder"])
        )
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    dependencies: [dependency],
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "MissingBuilder",
                                builderPluginPackage: "BoardSupport"
                            )
                        ),
                    ],
                    targets: [try TargetDescription(name: "FirmwareCore")]
                ),
                try Self.builderPackageManifest(
                    displayName: "Support",
                    path: "/Support",
                    pluginName: "OtherBuilder"
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        #expect(throws: StringError(
            "artifact product 'Firmware' references unknown builder plug-in 'MissingBuilder' "
                + "in package 'BoardSupport'"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    @Test
    func ambiguousBuilderPluginIsRejected() throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Firmware/Plugins/FirmwareBuilder/Plugin.swift",
            "/Firmware/Plugins/AlternateBuilder/Plugin.swift",
        ])
        let graph = try loadModulesGraph(
            fileSystem: fileSystem,
            manifests: [
                .createRootManifest(
                    displayName: "Firmware",
                    path: "/Firmware",
                    toolsVersion: .v6_3,
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: .init(
                                typeIdentifier: "dev.example.pico-uf2",
                                builderPlugin: "FirmwareBuilder"
                            )
                        ),
                        try ProductDescription(
                            name: "FirmwareBuilder",
                            type: .plugin,
                            targets: ["AlternateBuilder"]
                        ),
                    ],
                    targets: [
                        try TargetDescription(name: "FirmwareCore"),
                        try TargetDescription(
                            name: "FirmwareBuilder",
                            type: .plugin,
                            pluginCapability: .productBuilder
                        ),
                        try TargetDescription(
                            name: "AlternateBuilder",
                            type: .plugin,
                            pluginCapability: .productBuilder
                        ),
                    ]
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        let product = try #require(graph.product(for: "Firmware"))
        #expect(throws: StringError(
            "artifact product 'Firmware' references ambiguous builder plug-in 'FirmwareBuilder'"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    private static func builderPackageManifest(
        displayName: String,
        path: AbsolutePath,
        pluginName: String = "FirmwareBuilder"
    ) throws -> Manifest {
        .createFileSystemManifest(
            displayName: displayName,
            path: path,
            toolsVersion: .v6_3,
            products: [
                try ProductDescription(
                    name: pluginName,
                    type: .plugin,
                    targets: [pluginName]
                ),
            ],
            targets: [
                try TargetDescription(
                    name: pluginName,
                    type: .plugin,
                    pluginCapability: .productBuilder
                ),
            ]
        )
    }

}

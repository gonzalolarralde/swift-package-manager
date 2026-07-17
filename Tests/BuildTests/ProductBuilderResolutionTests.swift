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
@testable import Build
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
            "builder plug-in 'FirmwareBuilder' for custom product 'Firmware' "
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
            "custom product 'Firmware' references builder plug-in package 'MissingSupport', "
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
            "custom product 'Firmware' has an ambiguous builder plug-in package reference 'BoardSupport'"
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
            "custom product 'Firmware' references unknown builder plug-in 'MissingBuilder' "
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
            "custom product 'Firmware' references ambiguous builder plug-in 'FirmwareBuilder'"
        )) {
            try graph.productBuilderPlugin(for: product)
        }
    }

    @Test
    func dynamicLibraryDependencyIsRejectedBeforePluginInvocation() async throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Firmware/Plugins/FirmwareBuilder/Plugin.swift",
            "/DynamicSupport/Sources/DynamicSupport/DynamicSupport.swift",
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
                            identity: .plain("dynamicsupport"),
                            nameForTargetDependencyResolutionOnly: "DynamicSupport",
                            path: "/DynamicSupport",
                            productFilter: .specific(["DynamicSupport"])
                        ),
                    ],
                    products: [
                        try ProductDescription(
                            name: "Firmware",
                            type: .library(.static),
                            targets: ["FirmwareCore"],
                            customProduct: Self.customProduct
                        ),
                    ],
                    targets: [
                        try TargetDescription(
                            name: "FirmwareCore",
                            dependencies: [.product(name: "DynamicSupport", package: "DynamicSupport")]
                        ),
                        try TargetDescription(
                            name: "FirmwareBuilder",
                            type: .plugin,
                            pluginCapability: .productBuilder
                        ),
                    ]
                ),
                .createFileSystemManifest(
                    displayName: "DynamicSupport",
                    path: "/DynamicSupport",
                    toolsVersion: .v6_3,
                    products: [
                        try ProductDescription(
                            name: "DynamicSupport",
                            type: .library(.dynamic),
                            targets: ["DynamicSupport"]
                        ),
                    ],
                    targets: [try TargetDescription(name: "DynamicSupport")]
                ),
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        await #expect(throws: StringError(
            "custom product 'Firmware' has dynamic library dependencies; "
                + "product-builder plug-ins currently support only the aggregate static target closure"
        )) {
            _ = try await mockBuildPlan(
                graph: graph,
                pluginConfiguration: Self.pluginConfiguration,
                fileSystem: fileSystem,
                observabilityScope: ObservabilitySystem.NOOP
            )
        }
    }

    @Test
    func binaryLibraryDependencyIsRejectedBeforePluginInvocation() async throws {
        let fileSystem = InMemoryFileSystem(emptyFiles: [
            "/Firmware/Sources/FirmwareCore/Firmware.swift",
            "/Firmware/Plugins/FirmwareBuilder/Plugin.swift",
            "/Firmware/BinarySupport.xcframework/macos-arm64/libBinarySupport.a",
        ])
        try fileSystem.writeFileContents(
            "/Firmware/BinarySupport.xcframework/Info.plist",
            string: Self.binaryXCFrameworkInfoPlist
        )
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
                            customProduct: Self.customProduct
                        ),
                    ],
                    targets: [
                        try TargetDescription(name: "FirmwareCore", dependencies: ["BinarySupport"]),
                        try TargetDescription(
                            name: "FirmwareBuilder",
                            type: .plugin,
                            pluginCapability: .productBuilder
                        ),
                        try TargetDescription(
                            name: "BinarySupport",
                            path: "BinarySupport.xcframework",
                            type: .binary
                        ),
                    ]
                ),
            ],
            binaryArtifacts: [
                .plain("firmware"): [
                    "BinarySupport": .init(
                        kind: .xcframework,
                        originURL: nil,
                        path: "/Firmware/BinarySupport.xcframework"
                    ),
                ],
            ],
            observabilityScope: ObservabilitySystem.NOOP
        )

        await #expect(throws: StringError(
            "custom product 'Firmware' has binary library dependencies; "
                + "product-builder plug-ins do not expose those inputs yet"
        )) {
            _ = try await mockBuildPlan(
                triple: .arm64MacOS,
                graph: graph,
                pluginConfiguration: Self.pluginConfiguration,
                fileSystem: fileSystem,
                observabilityScope: ObservabilitySystem.NOOP
            )
        }
    }

    private static let customProduct = ProductDescription.CustomProduct(
        typeIdentifier: "dev.example.pico-uf2",
        builderPlugin: "FirmwareBuilder"
    )

    private static var pluginConfiguration: PluginConfiguration {
        PluginConfiguration(
            scriptRunner: FailingPluginScriptRunner(),
            workDirectory: "/tmp/product-builder-resolution-tests",
            disableSandbox: true
        )
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

    private static let binaryXCFrameworkInfoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AvailableLibraries</key>
            <array>
                <dict>
                    <key>LibraryIdentifier</key>
                    <string>macos-arm64</string>
                    <key>LibraryPath</key>
                    <string>libBinarySupport.a</string>
                    <key>SupportedArchitectures</key>
                    <array><string>arm64</string></array>
                    <key>SupportedPlatform</key>
                    <string>macos</string>
                </dict>
            </array>
            <key>CFBundlePackageType</key>
            <string>XFWK</string>
            <key>XCFrameworkFormatVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
}

private struct FailingPluginScriptRunner: PluginScriptRunner {
    var hostTriple: Triple {
        get throws { .arm64MacOS }
    }

    func compilePluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        completion(.failure(StringError("product-builder plug-in should not be invoked")))
    }

    func buildCommandLine(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope?
    ) -> (
        commandLine: [String],
        execName: String,
        execFilePath: AbsolutePath,
        diagFilePath: AbsolutePath
    ) {
        fatalError("product-builder plug-in should not be invoked")
    }

    func runPluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        workers: UInt32,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate & PluginScriptRunnerDelegate
    ) async throws -> Int32 {
        throw StringError("product-builder plug-in should not be invoked")
    }
}

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

import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import Testing

struct PackageDescription6_3LoadingTests {
    @Test
    func customProduct() async throws {
        let toolsVersion = try #require(ToolsVersion(
            string: "6.3.0",
            experimentalFeatures: [.experimentalProductBuilders]
        ))
        let content = """
            import PackageDescription

            let package = Package(
                name: "Firmware",
                products: [
                    .custom(
                        name: "Firmware",
                        typeIdentifier: "com.example.picou2f",
                        targets: ["FirmwareCore"],
                        builderPlugin: "RP2350Builder",
                        builderPluginPackage: "RP2350Support",
                        arguments: ["--family", "rp2350"]
                    )
                ],
                targets: [
                    .target(name: "FirmwareCore"),
                    .plugin(
                        name: "RP2350Builder",
                        capability: .productBuilder()
                    )
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, validationDiagnostics) = try await PackageDescriptionLoadingTests.loadAndValidateManifest(
            content,
            toolsVersion: toolsVersion,
            packageKind: .fileSystem(.root),
            manifestLoader: ManifestLoader(toolchain: try UserToolchain.default),
            observabilityScope: observability.topScope
        )

        #expect(validationDiagnostics.isEmpty)
        #expect(manifest.products.count == 1)

        let product = try #require(manifest.products.first)
        #expect(product.name == "Firmware")
        #expect(product.type == .library(.static))
        #expect(product.targets == ["FirmwareCore"])
        #expect(product.customProduct == .init(
            typeIdentifier: "com.example.picou2f",
            builderPlugin: "RP2350Builder",
            builderPluginPackage: "RP2350Support",
            arguments: ["--family", "rp2350"]
        ))

        let plugin = try #require(manifest.targets.first { $0.name == "RP2350Builder" })
        #expect(plugin.pluginCapability == .productBuilder)
    }

    @Test
    func customProductRequiresExperimentalOptIn() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "Firmware",
                products: [
                    .custom(
                        name: "Firmware",
                        typeIdentifier: "com.example.picou2f",
                        targets: ["FirmwareCore"],
                        builderPlugin: "FirmwareBuilder"
                    )
                ],
                targets: [
                    .target(name: "FirmwareCore"),
                    .plugin(name: "FirmwareBuilder", capability: .productBuilder())
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await PackageDescriptionLoadingTests.loadAndValidateManifest(
            content,
            toolsVersion: .v6_3,
            packageKind: .fileSystem(.root),
            manifestLoader: ManifestLoader(toolchain: try UserToolchain.default),
            observabilityScope: observability.topScope
        )

        #expect(validationDiagnostics.map(\.message) == [
            "custom products and product-builder plug-ins require "
                + "';(experimentalProductBuilders)' in the swift-tools-version header",
        ])
    }
}

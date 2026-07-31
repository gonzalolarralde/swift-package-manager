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
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.large,
        .Feature.Command.Package.CommandPlugin,
        .Feature.Plugin,
    )
)
struct ProductBuilderBuildResultTests {
    @Test(.requiresSwiftConcurrencySupport)
    func commandPluginReceivesArtifactProductFiles() async throws {
        try await fixture(name: "Miscellaneous/Plugins/CustomProductBuilder") { fixturePath in
            func expectArtifacts(in stdout: String) {
                #expect(stdout.contains("build-succeeded: true"), "stdout:\n\(stdout)")

                let artifactLines = stdout.split(separator: "\n").filter { $0.hasPrefix("artifact: ") }
                #expect(artifactLines.count == 4, "stdout:\n\(stdout)")
                #expect(artifactLines.contains { $0.contains("file|") && $0.hasSuffix("/ArtifactFixture.elf") })
                #expect(artifactLines.contains { $0.contains("file|") && $0.hasSuffix("/ArtifactFixture.bin") })
                #expect(artifactLines.contains { $0.contains("file|") && $0.hasSuffix("/ArtifactFixture.uf2") })
                #expect(artifactLines.contains {
                    $0.contains("file|") && $0.hasSuffix("/ArtifactFixture.debug/metadata.txt")
                })
                #expect(artifactLines.allSatisfy {
                    $0.contains("/plugins/outputs/customproductbuilder/ArtifactFixture/destination/")
                        && $0.contains("/debug/FirmwareBuilder/outputs/")
                }, "stdout:\n\(stdout)")
            }

            for _ in 0..<2 {
                let (stdout, _) = try await executeSwiftPackage(
                    fixturePath,
                    configuration: .debug,
                    extraArgs: ["report-product-artifacts"],
                    buildSystem: .swiftbuild
                )
                expectArtifacts(in: stdout)
            }
        }
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import SPMBuildCore
import XCTest
import _InternalTestSupport

final class ConstExprManifestOptionsTests: XCTestCase {
    func testExecutingLoaderRemainsTheDefault() throws {
        let options = try GlobalOptions.parse([])
        XCTAssertEqual(options.manifest.mode, .onlyExecuted)
        XCTAssertFalse(options.manifest.showFallbacks)
    }

    func testExperimentalModesParse() throws {
        for mode in ManifestProcessingOptions.Mode.allCases {
            let options = try GlobalOptions.parse([
                "--experimental-manifest-processing-mode",
                mode.rawValue,
            ])
            XCTAssertEqual(options.manifest.mode, mode)
        }
    }

    func testDeveloperFallbackTelemetryFlagParses() throws {
        let options = try GlobalOptions.parse([
            "--experimental-show-constexpr-manifest-fallbacks",
        ])
        XCTAssertTrue(options.manifest.showFallbacks)
    }

    func testDumpPackageStdoutStaysJSONForFastPathAndFallback() async throws {
        let manifests = [
            ("Fast", """
                // swift-tools-version: 6.1
                import PackageDescription
                let package = Package(name: "Fast")
                """),
            ("Fallback", """
                // swift-tools-version: 6.1
                import PackageDescription
                let package = Package(name: "Fallback")
                package.targets.append(.target(name: "Later"))
                """),
        ]

        for (expectedName, manifest) in manifests {
            try await withTemporaryDirectory { packagePath in
                try localFileSystem.writeFileContents(
                    packagePath.appending("Package.swift"),
                    string: manifest
                )
                let result = try await executeSwiftPackage(
                    packagePath,
                    extraArgs: [
                        "--experimental-manifest-processing-mode",
                        "constexpr-with-fallback",
                        "--experimental-show-constexpr-manifest-fallbacks",
                        "dump-package",
                    ],
                    buildSystem: .native
                )
                let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
                let dictionary = try XCTUnwrap(object as? [String: Any])
                XCTAssertEqual(dictionary["name"] as? String, expectedName)
            }
        }
    }
}

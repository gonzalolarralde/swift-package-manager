//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel
import SwiftIfConfig

final class ConstExprBuildConfigurationProvider: @unchecked Sendable {
    private let toolchain: UserToolchain
    private let extraFlags: [String]
    private let lock = NSLock()
    private var configurations: [ToolsVersion: StaticBuildConfiguration]

    init(
        toolchain: UserToolchain,
        extraFlags: [String]
    ) {
        self.toolchain = toolchain
        self.extraFlags = extraFlags
        self.configurations = [:]
    }

    func configuration(for toolsVersion: ToolsVersion) throws -> StaticBuildConfiguration {
        lock.lock()
        defer { lock.unlock() }
        if let existing = configurations[toolsVersion] {
            return existing
        }
        let arguments = [
            toolchain.swiftCompilerPathForManifests.pathString,
            "-frontend",
            "-print-static-build-config",
        ] + Self.targetFlags(toolchain: toolchain)
            + toolchain.swiftCompilerFlags
            + ManifestLoader.interpreterFlags(for: toolsVersion, toolchain: toolchain)
            + extraFlags
        let output: String
        do {
            output = try AsyncProcess.popen(
                arguments: arguments,
                environment: toolchain.swiftCompilerEnvironment
            ).utf8Output()
        } catch {
            throw ConstExprManifestFallback(
                reasonCode: "build-configuration",
                detail: "could not query the host compiler build configuration: \(error)"
            )
        }
        do {
            let configuration = try JSONDecoder().decode(
                StaticBuildConfiguration.self,
                from: Data(output.utf8)
            )
            configurations[toolsVersion] = configuration
            return configuration
        } catch {
            throw ConstExprManifestFallback(
                reasonCode: "build-configuration",
                detail: "could not decode the host compiler build configuration: \(error)"
            )
        }
    }

    private static func targetFlags(toolchain: UserToolchain) -> [String] {
        #if os(macOS)
        let triple: String
        if let version = toolchain.swiftPMLibrariesLocation
            .manifestLibraryMinimumDeploymentTarget?.versionString
        {
            triple = toolchain.targetTriple.tripleString(forPlatformVersion: version)
        } else {
            triple = toolchain.targetTriple.tripleString
        }
        return ["-target", triple]
        #else
        return []
        #endif
    }
}

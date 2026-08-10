//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import PackageLoading
import PackageModel
import SourceControl
import XCTest

final class ConstExprPackageIndexCorpusTests: XCTestCase {
    func testPackageIndexCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["SWIFTPM_CONSTEXPR_CORPUS_INPUT"],
              let outputPath = environment["SWIFTPM_CONSTEXPR_CORPUS_OUTPUT"]
        else {
            throw XCTSkip("set SWIFTPM_CONSTEXPR_CORPUS_INPUT and _OUTPUT to run the corpus")
        }

        let decoder = JSONDecoder()
        let rows = try String(contentsOfFile: inputPath, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { try decoder.decode(Input.self, from: Data($0.utf8)) }
        let toolchain = try UserToolchain.default
        let fastLoader = ConstExprManifestLoader(
            toolchain: toolchain,
            environment: environment
        )
        let shouldCrosscheck = environment["SWIFTPM_CONSTEXPR_CORPUS_CROSSCHECK"] == "1"
        let outputURL = URL(fileURLWithPath: outputPath)
        if !FileManager.default.fileExists(atPath: outputPath) {
            guard FileManager.default.createFile(atPath: outputPath, contents: nil) else {
                throw StringError("could not create corpus output at \(outputPath)")
            }
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        try outputHandle.seekToEnd()
        defer { try? outputHandle.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for (index, row) in rows.enumerated() {
            var output = await evaluate(
                row,
                index: index,
                loader: fastLoader
            )
            if shouldCrosscheck, let packagePath = row.packagePath, output.status == "success" {
                await crosscheck(
                    row,
                    packagePath: packagePath,
                    toolchain: toolchain,
                    fastLoader: fastLoader,
                    output: &output
                )
            }
            var data = try encoder.encode(output)
            data.append(0x0A)
            try outputHandle.write(contentsOf: data)
            try outputHandle.synchronize()
        }
    }

    private func evaluate(
        _ row: Input,
        index: Int,
        loader: ConstExprManifestLoader
    ) async -> Output {
        let path: AbsolutePath
        let source: String
        let toolsVersion: ToolsVersion
        do {
            path = try AbsolutePath(validating: row.manifestPath)
            source = try localFileSystem.readFileContents(path).validDescription ?? {
                throw StringError("manifest is not UTF-8")
            }()
            guard source.sha256Checksum == row.sha256.lowercased() else {
                return Output(
                    url: row.url,
                    sha256: row.sha256.lowercased(),
                    status: "parseFailure",
                    reasonCode: "content-hash-mismatch",
                    durationNanoseconds: 0,
                    detail: "cached manifest does not match the recorded SHA-256"
                )
            }
            toolsVersion = try ToolsVersionParser.parse(
                manifestPath: path,
                fileSystem: localFileSystem
            )
        } catch {
            return Output(
                url: row.url,
                sha256: row.sha256.lowercased(),
                status: "parseFailure",
                reasonCode: "input",
                durationNanoseconds: 0,
                detail: String(describing: error)
            )
        }

        let identityResolver = DefaultIdentityResolver()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try loader.parse(
                manifestPath: path,
                source: source,
                manifestToolsVersion: toolsVersion,
                packageIdentity: .plain("corpus-\(index)"),
                packageKind: .fileSystem(path.parentDirectory),
                packageLocation: row.url,
                packageVersion: nil,
                identityResolver: identityResolver,
                dependencyMapper: DefaultDependencyMapper(identityResolver: identityResolver),
                fileSystem: localFileSystem
            )
            return Output(
                url: row.url,
                sha256: row.sha256.lowercased(),
                status: "success",
                durationNanoseconds: nanoseconds(start.duration(to: clock.now)),
                toolsVersion: toolsVersion.description
            )
        } catch let fallback as ConstExprManifestFallback {
            return Output(
                url: row.url,
                sha256: row.sha256.lowercased(),
                status: "fallback",
                reasonCode: fallback.reasonCode,
                durationNanoseconds: nanoseconds(start.duration(to: clock.now)),
                toolsVersion: toolsVersion.description,
                detail: fallback.detail
            )
        } catch {
            return Output(
                url: row.url,
                sha256: row.sha256.lowercased(),
                status: "parseFailure",
                reasonCode: "loader-error",
                durationNanoseconds: nanoseconds(start.duration(to: clock.now)),
                toolsVersion: toolsVersion.description,
                detail: String(describing: error)
            )
        }
    }

    private func crosscheck(
        _ row: Input,
        packagePath: String,
        toolchain: UserToolchain,
        fastLoader: ConstExprManifestLoader,
        output: inout Output
    ) async {
        do {
            let path = try AbsolutePath(validating: packagePath)
            let identityResolver = DefaultIdentityResolver()
            let executing = ManifestLoader(toolchain: toolchain)
            let dependencyMapper = DefaultDependencyMapper(identityResolver: identityResolver)
            let observability = ObservabilitySystem.makeForTesting()
            let fast = try await fastLoader.load(
                packagePath: path,
                packageIdentity: .plain("corpus-crosscheck"),
                packageKind: .fileSystem(path),
                packageLocation: row.url,
                packageVersion: nil,
                currentToolsVersion: .current,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope,
                delegateQueue: .global()
            )
            let executed = try await executing.load(
                packagePath: path,
                packageIdentity: .plain("corpus-crosscheck"),
                packageKind: .fileSystem(path),
                packageLocation: row.url,
                packageVersion: nil,
                currentToolsVersion: .current,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: localFileSystem,
                observabilityScope: observability.topScope,
                delegateQueue: .global()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if try encoder.encode(fast) == encoder.encode(executed) {
                output.crosscheck = "success"
            } else {
                output.status = "crosscheckMismatch"
                output.crosscheck = "mismatch"
            }
        } catch let fallback as ConstExprManifestFallback {
            output.crosscheck = "fallback:\(fallback.reasonCode)"
        } catch {
            output.crosscheck = "error"
            output.detail = [output.detail, String(describing: error)]
                .compactMap { $0 }.joined(separator: "; ")
        }
    }

    private func nanoseconds(_ duration: Duration) -> UInt64 {
        let parts = duration.components
        let seconds = UInt64(max(0, parts.seconds)) * 1_000_000_000
        let fractional = UInt64(max(0, parts.attoseconds / 1_000_000_000))
        return seconds + fractional
    }
}

private struct Input: Decodable {
    let url: String
    let manifestPath: String
    let sha256: String
    let packagePath: String?
}

private struct Output: Encodable {
    let url: String
    let sha256: String
    var status: String
    var reasonCode: String?
    let durationNanoseconds: UInt64
    var toolsVersion: String?
    var detail: String?
    var crosscheck: String?
}

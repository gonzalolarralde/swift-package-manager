//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageLoading
import PackageModel
import SourceControl
import XCTest

final class ConstExprManifestLoaderPerformanceTests: XCTestCase {
    func testRepresentativeManifestBenchmark() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SWIFTPM_CONSTEXPR_BENCHMARK"] == "1" else {
            throw XCTSkip("set SWIFTPM_CONSTEXPR_BENCHMARK=1 to run the release benchmark")
        }
        let iterations = max(
            1,
            Int(environment["SWIFTPM_CONSTEXPR_BENCHMARK_ITERATIONS"] ?? "1000") ?? 1000
        )
        let loader = try ConstExprManifestTestSupport.makeLoader(environment: environment)
        let fileSystem = InMemoryFileSystem()
        let identityResolver = DefaultIdentityResolver()
        let dependencyMapper = DefaultDependencyMapper(identityResolver: identityResolver)
        let source = Self.representativeManifest
        let clock = ContinuousClock()

        func evaluate() throws {
            let manifest = try loader.parse(
                manifestPath: ConstExprManifestTestSupport.manifestPath,
                source: source,
                manifestToolsVersion: .v6_1,
                packageIdentity: .plain("benchmark"),
                packageKind: .fileSystem(ConstExprManifestTestSupport.manifestPath.parentDirectory),
                packageLocation: "/benchmark",
                packageVersion: nil,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: fileSystem
            )
            precondition(manifest.displayName == "Benchmark")
        }

        let coldStart = clock.now
        try evaluate()
        let cold = nanoseconds(coldStart.duration(to: clock.now))
        var warm: [UInt64] = []
        warm.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            try evaluate()
            warm.append(nanoseconds(start.duration(to: clock.now)))
        }

        let sorted = warm.sorted()
        let mean = warm.reduce(0, +) / UInt64(warm.count)
        let result = Result(
            coldNanoseconds: cold,
            warmMeanNanoseconds: mean,
            warmMedianNanoseconds: percentile(sorted, 0.50),
            warmP90Nanoseconds: percentile(sorted, 0.90),
            warmP99Nanoseconds: percentile(sorted, 0.99),
            iterations: iterations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print("SWIFTPM_CONSTEXPR_BENCHMARK \(String(decoding: try encoder.encode(result), as: UTF8.self))")
    }

    private func percentile(_ sorted: [UInt64], _ value: Double) -> UInt64 {
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * value).rounded(.up)))
        return sorted[index]
    }

    private func nanoseconds(_ duration: Duration) -> UInt64 {
        let parts = duration.components
        return UInt64(max(0, parts.seconds)) * 1_000_000_000
            + UInt64(max(0, parts.attoseconds / 1_000_000_000))
    }

    private struct Result: Encodable {
        let coldNanoseconds: UInt64
        let warmMeanNanoseconds: UInt64
        let warmMedianNanoseconds: UInt64
        let warmP90Nanoseconds: UInt64
        let warmP99Nanoseconds: UInt64
        let iterations: Int
    }

    private static let representativeManifest = """
        import PackageDescription
        let names = ["Core", "Utilities"]
        let package = Package(
            name: "Benchmark",
            defaultLocalization: "en",
            platforms: [.macOS(.v13), .iOS(.v16)],
            products: [.library(name: "Benchmark", targets: names)],
            dependencies: [
                .package(url: "https://example.com/one.git", from: "1.2.3"),
                .package(url: "https://example.com/two.git", branch: "main"),
            ],
            targets: [
                .target(
                    name: "Core",
                    resources: [.process("Resources")],
                    swiftSettings: [.define("FEATURE")]
                ),
                .target(name: "Utilities", dependencies: ["Core"]),
            ]
        )
        """
}

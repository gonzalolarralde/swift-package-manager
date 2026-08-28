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

import Dispatch
import Foundation
@_spi(ConstExprManifest) import PackageDescription
import XCTest

final class ConstExprManifestSessionTests: XCTestCase {
    func testNestedEvaluationsRestoreOuterSession() {
        let outer = Package._withConstExprManifestEvaluation {
            _ = Package(name: "OuterBefore")
            let inner = Package._withConstExprManifestEvaluation {
                _ = Package(name: "Inner")
            }
            _ = Package(name: "OuterAfter")
            return inner.packageInitializerCount
        }

        XCTAssertEqual(outer.result, 1)
        XCTAssertEqual(outer.packageInitializerCount, 2)
    }

    func testUnrelatedConcurrentConstructionIsNotCounted() throws {
        guard !CommandLine.arguments.contains("-fileno"),
              !CommandLine.arguments.contains("-handle")
        else {
            throw XCTSkip("test must not register a real manifest exit handler")
        }

        let evaluationStarted = DispatchSemaphore(value: 0)
        let allowEvaluationToFinish = DispatchSemaphore(value: 0)
        let evaluationFinished = expectation(description: "evaluation finished")
        let observedCount = LockedInitializerCount()

        DispatchQueue.global().async {
            let evaluation = Package._withConstExprManifestEvaluation {
                evaluationStarted.signal()
                allowEvaluationToFinish.wait()
                _ = Package(name: "Evaluated")
            }
            observedCount.store(evaluation.packageInitializerCount)
            evaluationFinished.fulfill()
        }

        XCTAssertEqual(evaluationStarted.wait(timeout: .now() + 5), .success)
        _ = Package(name: "Unrelated")
        allowEvaluationToFinish.signal()

        wait(for: [evaluationFinished], timeout: 5)
        XCTAssertEqual(observedCount.value, 1)
    }
}

private final class LockedInitializerCount: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Int?

    var value: Int? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storedValue = value
    }
}

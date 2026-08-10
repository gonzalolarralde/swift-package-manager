//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

final class ConstExprPackageDescriptionInterfaceTests: XCTestCase {
    func testPublicInterfaceDoesNotExposeConstExpr() throws {
        let testBundle = Bundle(for: Self.self).bundleURL.standardizedFileURL
        for module in ["PackageDescription", "CompilerPluginSupport"] {
            let interface = try XCTUnwrap(Self.findPublicInterface(
                module: module,
                startingAt: testBundle
            ), "\(module).swiftinterface was not emitted by the active test build")
            let source = try String(contentsOf: interface, encoding: .utf8)
            XCTAssertFalse(source.contains("import ConstExpr"), module)
            XCTAssertFalse(source.contains("__constExpr"), module)
            XCTAssertFalse(source.contains("registrationAccess"), module)
        }
    }

    private static func findPublicInterface(
        module: String,
        startingAt testBundle: URL
    ) -> URL? {
        var directory = testBundle
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("Modules", isDirectory: true)
                .appendingPathComponent("\(module).swiftinterface")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }
}

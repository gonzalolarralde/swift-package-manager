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
@_spi(PackagePluginInternal) import PackagePlugin
import XCTest

final class ProductBuilderPlanTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/product-builder")
    private let executable = URL(fileURLWithPath: "/usr/bin/touch")

    func testValidPlan() throws {
        let intermediate = self.outputDirectory.appendingPathComponent("firmware.elf")
        let final = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: "Link firmware",
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [intermediate]
                ),
                .buildCommand(
                    displayName: "Convert firmware",
                    executable: self.executable,
                    arguments: [],
                    inputFiles: [intermediate],
                    outputFiles: [final]
                ),
            ],
            outputFiles: [final]
        )

        XCTAssertNoThrow(try plan.validate(outputDirectory: self.outputDirectory))
    }

    #if os(macOS)
    func testExistingOutputDirectoryAndNonexistentChildUseLexicalContainment() throws {
        let outputDirectory = URL(
            fileURLWithPath: "/private/tmp/product-builder-path-validation-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let finalOutput = outputDirectory.appendingPathComponent("Product.artifact")
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalOutput.path))
        XCTAssertNotEqual(
            outputDirectory.standardizedFileURL.path,
            finalOutput.standardizedFileURL.deletingLastPathComponent().path
        )

        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: "Create artifact",
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [finalOutput]
                ),
            ],
            outputFiles: [finalOutput]
        )

        XCTAssertNoThrow(try plan.validate(outputDirectory: outputDirectory))
    }
    #endif

    func testRejectsPrebuildCommands() throws {
        let plan = ProductBuilderPlan(
            commands: [
                .prebuildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFilesDirectory: self.outputDirectory.appendingPathComponent("generated")
                ),
            ],
            outputFiles: [self.outputDirectory.appendingPathComponent("firmware.uf2")]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.prebuildCommandNotSupported = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsBuildCommandWithoutOutputs() throws {
        let final = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: []
                ),
            ],
            outputFiles: [final]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.commandHasNoOutputs = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsInPlaceMutation() throws {
        let output = self.outputDirectory
            .appendingPathComponent("Firmware.app")
            .appendingPathComponent("Firmware")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: "Sign application in place",
                    executable: self.executable,
                    arguments: [],
                    inputFiles: [output],
                    outputFiles: [output]
                ),
            ],
            outputFiles: [output]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.inputAlsoDeclaredAsOutput(let path) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, output)
        }
    }

    func testRejectsPlanWithoutFinalOutputs() throws {
        let intermediate = self.outputDirectory.appendingPathComponent("firmware.elf")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [intermediate]
                ),
            ]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.noFinalOutputs = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsOutputsOutsideProductDirectory() throws {
        let output = URL(fileURLWithPath: "/tmp/escaped.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [output]
                ),
            ],
            outputFiles: [output]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.outputOutsideOutputDirectory(output) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(output.path, "/tmp/escaped.uf2")
        }
    }

    func testRejectsFinalOutputOutsideProductDirectory() throws {
        let intermediate = self.outputDirectory.appendingPathComponent("firmware.elf")
        let final = URL(fileURLWithPath: "/tmp/escaped.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [intermediate]
                ),
            ],
            outputFiles: [final]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.outputOutsideOutputDirectory(let output) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(output.path, "/tmp/escaped.uf2")
        }
    }

    func testRejectsOutputThatEscapesUsingParentDirectoryComponent() throws {
        let escaped = self.outputDirectory
            .appendingPathComponent("intermediates")
            .appendingPathComponent("../..")
            .appendingPathComponent("escaped.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [escaped]
                ),
            ],
            outputFiles: [escaped]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.outputOutsideOutputDirectory(let output) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(output.path, "/tmp/escaped.uf2")
        }
    }

    func testRejectsMultipleProducers() throws {
        let output = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let command = Command.buildCommand(
            displayName: nil,
            executable: self.executable,
            arguments: [],
            outputFiles: [output]
        )
        let plan = ProductBuilderPlan(
            commands: [command, command],
            outputFiles: [output]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.outputHasMultipleProducers = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsMultipleProducersAfterStandardizingPaths() throws {
        let output = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let equivalentOutput = self.outputDirectory
            .appendingPathComponent("intermediates")
            .appendingPathComponent("..")
            .appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [output]
                ),
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [equivalentOutput]
                ),
            ],
            outputFiles: [output]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.outputHasMultipleProducers(let duplicate) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(duplicate, output.standardized)
        }
    }

    func testRejectsDuplicateFinalFileOutput() throws {
        let output = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [output]
                ),
            ],
            outputFiles: [output, output]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.duplicateFinalOutput(let duplicate) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(duplicate, output.standardized)
        }
    }

    func testMatchesProducerAndFinalOutputAfterStandardizingPaths() throws {
        let producedOutput = self.outputDirectory
            .appendingPathComponent("intermediates")
            .appendingPathComponent("..")
            .appendingPathComponent("firmware.uf2")
        let finalOutput = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [producedOutput]
                ),
            ],
            outputFiles: [finalOutput]
        )

        XCTAssertNoThrow(try plan.validate(outputDirectory: self.outputDirectory))
    }

    func testRejectsFinalOutputWithoutProducer() throws {
        let intermediate = self.outputDirectory.appendingPathComponent("firmware.elf")
        let final = self.outputDirectory.appendingPathComponent("firmware.uf2")
        let plan = ProductBuilderPlan(
            commands: [
                .buildCommand(
                    displayName: nil,
                    executable: self.executable,
                    arguments: [],
                    outputFiles: [intermediate]
                ),
            ],
            outputFiles: [final]
        )

        XCTAssertThrowsError(try plan.validate(outputDirectory: self.outputDirectory)) { error in
            guard case ProductBuilderPlanValidationError.finalOutputHasNoProducer = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}

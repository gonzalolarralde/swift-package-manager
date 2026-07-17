import Foundation

do {
    try IOSAppPackager.run()
} catch {
    FileHandle.standardError.write(Data("error: IOSAppPackager: \(error)\n".utf8))
    exit(1)
}

enum IOSAppPackager {
    static func run() throws {
        let arguments = try PackagerArguments()
        let payload = try JSONDecoder().decode(
            IOSAppBuilderPayload.self,
            from: Data(arguments.payloadJSON.utf8)
        )
        guard payload.schemaVersion == IOSAppBuilderPayload.currentSchemaVersion else {
            throw PackagerError("unsupported payload schema \(payload.schemaVersion)")
        }
        switch arguments.platform {
        case .device:
            guard arguments.targetTriple.contains("apple-ios"),
                  !arguments.targetTriple.contains("simulator")
            else {
                throw PackagerError("expected a device iOS target triple, received \(arguments.targetTriple)")
            }
        case .simulator:
            guard arguments.targetTriple.contains("apple-ios"),
                  arguments.targetTriple.hasSuffix("-simulator")
            else {
                throw PackagerError("expected an iOS Simulator target triple, received \(arguments.targetTriple)")
            }
        }
        guard FileManager.default.fileExists(atPath: arguments.aggregateArchive.path) else {
            throw PackagerError("SwiftPM aggregate archive does not exist at \(arguments.aggregateArchive.path)")
        }

        let configuration = payload.configuration
        let outputRoot = arguments.outputReport.deletingLastPathComponent()
        let work = outputRoot.appendingPathComponent(".ios-app-packager-work", isDirectory: true)
        try resetOutputs(arguments: arguments, work: work)

        let generated = try XcodeProjectGenerator.generate(
            at: work,
            aggregateArchive: arguments.aggregateArchive,
            resourceBundles: arguments.resourceBundles,
            platform: arguments.platform,
            configuration: configuration
        )

        var runner = ProcessRunner()
        try runner.run(
            try ToolLocator.xcodegen(),
            [
                "generate",
                "--spec", work.appendingPathComponent("project.yml").path,
                "--project", work.path,
                "--project-root", work.path,
                "--no-env",
                "--quiet",
            ],
            currentDirectory: work
        )
        guard FileManager.default.fileExists(atPath: generated.project.path) else {
            throw PackagerError("xcodegen did not create \(generated.project.path)")
        }

        let xcodeConfiguration = arguments.configuration.lowercased() == "debug" ? "Debug" : "Release"
        let outputApplication: URL
        switch arguments.platform {
        case .device:
            outputApplication = try buildDeviceApplication(
                arguments: arguments,
                configuration: configuration,
                generated: generated,
                xcodeConfiguration: xcodeConfiguration,
                work: work,
                runner: &runner
            )
        case .simulator:
            outputApplication = try buildSimulatorApplication(
                arguments: arguments,
                generated: generated,
                xcodeConfiguration: xcodeConfiguration,
                work: work,
                runner: &runner
            )
        }

        let isSignedDeviceExport = arguments.platform == .device
            && (configuration.signing.style == .automatic || configuration.signing.style == .manual)
        let installationReadiness: String = switch arguments.platform {
        case .simulator: "simulator-only"
        case .device where isSignedDeviceExport: "xcode-signed-export-completed"
        case .device: "requires-a-valid-Apple-signature-and-provisioning-profile"
        }

        let report = BuildReport(
            schemaVersion: payload.schemaVersion,
            typeIdentifier: IOSAppBuilderPayload.typeIdentifier,
            artifactKind: arguments.platform == .device ? "deviceIPA" : "simulatorApplication",
            targetTriple: arguments.targetTriple,
            swiftPMConfiguration: arguments.configuration,
            bundleIdentifier: configuration.identity.bundleIdentifier,
            displayName: configuration.identity.displayName,
            signingStyle: configuration.signing.style.rawValue,
            signedExport: isSignedDeviceExport,
            installationReadiness: installationReadiness,
            aggregateArchive: arguments.aggregateArchive.path,
            embeddedResourceBundles: generated.copiedResourceBundles.map(\.lastPathComponent),
            outputApplication: outputApplication.path,
            outputArchive: arguments.outputArchive?.path,
            outputIPA: arguments.outputIPA?.path,
            commands: runner.commands
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: arguments.outputReport, options: .atomic)

        print("[IOSAppPackager] application: \(outputApplication.path)")
        if let archive = arguments.outputArchive {
            print("[IOSAppPackager] archive: \(archive.path)")
        }
        if let ipa = arguments.outputIPA {
            print("[IOSAppPackager] IPA: \(ipa.path)")
        }
        print("[IOSAppPackager] signing: \(report.installationReadiness)")
    }

    private static func resetOutputs(arguments: PackagerArguments, work: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: arguments.outputReport.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outputs = [arguments.outputArchive, arguments.outputIPA, arguments.outputApp]
            .compactMap { $0 } + [arguments.outputReport]
        for url in [work] + outputs
            where fileManager.fileExists(atPath: url.path)
        {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    }

    private static func buildDeviceApplication(
        arguments: PackagerArguments,
        configuration: IOSApplicationConfiguration,
        generated: GeneratedXcodeProject,
        xcodeConfiguration: String,
        work: URL,
        runner: inout ProcessRunner
    ) throws -> URL {
        guard let outputArchive = arguments.outputArchive, let outputIPA = arguments.outputIPA else {
            throw PackagerError("device output paths are missing")
        }
        var archiveArguments = [
            "-project", generated.project.path,
            "-scheme", generated.scheme,
            "-configuration", xcodeConfiguration,
            "-destination", "generic/platform=iOS",
            "-archivePath", outputArchive.path,
            "-derivedDataPath", work.appendingPathComponent("DerivedData", isDirectory: true).path,
            "COMPILER_INDEX_STORE_ENABLE=NO",
        ]
        archiveArguments += provisioningArguments(for: configuration.signing)
        archiveArguments.append("archive")
        try runner.run(ToolLocator.xcodebuild, archiveArguments, currentDirectory: work)

        let app = try archivedApplication(in: outputArchive)
        switch configuration.signing.style {
        case .automatic, .manual:
            try exportSignedIPA(
                configuration: configuration,
                archive: outputArchive,
                output: outputIPA,
                work: work,
                runner: &runner
            )
        case .localAdHoc:
            var codesignArguments = ["--force", "--sign", "-", "--deep"]
            if FileManager.default.fileExists(atPath: generated.entitlements.path) {
                codesignArguments += ["--entitlements", generated.entitlements.path]
            }
            codesignArguments.append(app.path)
            try runner.run(ToolLocator.codesign, codesignArguments)
            try packageDirectIPA(app: app, output: outputIPA, work: work, runner: &runner)
        case .unsigned:
            try packageDirectIPA(app: app, output: outputIPA, work: work, runner: &runner)
        }
        return app
    }

    private static func buildSimulatorApplication(
        arguments: PackagerArguments,
        generated: GeneratedXcodeProject,
        xcodeConfiguration: String,
        work: URL,
        runner: inout ProcessRunner
    ) throws -> URL {
        guard let outputApp = arguments.outputApp else {
            throw PackagerError("simulator output path is missing")
        }
        let products = work.appendingPathComponent("SimulatorProducts", isDirectory: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let buildArguments = [
            "-project", generated.project.path,
            "-scheme", generated.scheme,
            "-configuration", xcodeConfiguration,
            "-destination", "generic/platform=iOS Simulator",
            "-sdk", "iphonesimulator",
            "-derivedDataPath", work.appendingPathComponent("DerivedData", isDirectory: true).path,
            "CONFIGURATION_BUILD_DIR=\(products.path)",
            "COMPILER_INDEX_STORE_ENABLE=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
            "build",
        ]
        try runner.run(ToolLocator.xcodebuild, buildArguments, currentDirectory: work)

        let builtApp = products.appendingPathComponent("\(generated.scheme).app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: builtApp.path) else {
            throw PackagerError("xcodebuild did not create the expected Simulator app at \(builtApp.path)")
        }
        try FileManager.default.copyItem(at: builtApp, to: outputApp)
        return outputApp
    }

    private static func provisioningArguments(for signing: IOSSigning) -> [String] {
        var arguments: [String] = []
        if signing.allowProvisioningUpdates {
            arguments.append("-allowProvisioningUpdates")
        }
        if signing.allowDeviceRegistration {
            arguments.append("-allowProvisioningDeviceRegistration")
        }
        return arguments
    }

    private static func archivedApplication(in archive: URL) throws -> URL {
        let applications = archive.appendingPathComponent("Products/Applications", isDirectory: true)
        let candidates = try FileManager.default.contentsOfDirectory(
            at: applications,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "app" }
        guard candidates.count == 1, let app = candidates.first else {
            throw PackagerError("expected exactly one .app in \(applications.path), found \(candidates.count)")
        }
        return app
    }

    private static func exportSignedIPA(
        configuration: IOSApplicationConfiguration,
        archive: URL,
        output: URL,
        work: URL,
        runner: inout ProcessRunner
    ) throws {
        let exportRoot = work.appendingPathComponent("Export", isDirectory: true)
        let exportOptions = work.appendingPathComponent("ExportOptions.plist")
        try PropertyLists.write(try PropertyLists.exportOptions(for: configuration), to: exportOptions)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        var arguments = [
            "-exportArchive",
            "-archivePath", archive.path,
            "-exportPath", exportRoot.path,
            "-exportOptionsPlist", exportOptions.path,
        ]
        arguments += provisioningArguments(for: configuration.signing)
        try runner.run(ToolLocator.xcodebuild, arguments, currentDirectory: work)

        let exported = try FileManager.default.contentsOfDirectory(
            at: exportRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "ipa" }
        guard exported.count == 1, let ipa = exported.first else {
            throw PackagerError("expected exactly one exported IPA, found \(exported.count)")
        }
        try FileManager.default.copyItem(at: ipa, to: output)
    }

    private static func packageDirectIPA(
        app: URL,
        output: URL,
        work: URL,
        runner: inout ProcessRunner
    ) throws {
        let staging = work.appendingPathComponent("UnsignedIPA", isDirectory: true)
        let payload = staging.appendingPathComponent("Payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app, to: payload.appendingPathComponent(app.lastPathComponent))
        try runner.run(
            ToolLocator.zip,
            ["-qryX", output.path, payload.lastPathComponent],
            currentDirectory: staging
        )
    }
}

private struct BuildReport: Codable {
    let schemaVersion: Int
    let typeIdentifier: String
    let artifactKind: String
    let targetTriple: String
    let swiftPMConfiguration: String
    let bundleIdentifier: String
    let displayName: String
    let signingStyle: String
    let signedExport: Bool
    let installationReadiness: String
    let aggregateArchive: String
    let embeddedResourceBundles: [String]
    let outputApplication: String
    let outputArchive: String?
    let outputIPA: String?
    let commands: [[String]]
}

import Foundation
import PackagePlugin

@main
struct IOSAppBuilder: ProductBuilderPlugin {
    func createBuildPlan(
        context: PluginContext,
        input: ProductBuilderInput
    ) async throws -> ProductBuilderPlan {
        guard input.typeIdentifier == IOSAppBuilderPayload.typeIdentifier else {
            throw BuilderError.unsupportedType(input.typeIdentifier)
        }
        guard input.arguments.count == 1 else {
            throw BuilderError.invalidArgumentCount(input.arguments.count)
        }
        guard let platform = IOSBuilderPlatform(targetTriple: input.targetTriple) else {
            throw BuilderError.unsupportedTriple(input.targetTriple)
        }

        let payloadJSON = input.arguments[0]
        let payload = try JSONDecoder().decode(
            IOSAppBuilderPayload.self,
            from: Data(payloadJSON.utf8)
        )
        guard payload.schemaVersion == IOSAppBuilderPayload.currentSchemaVersion else {
            throw BuilderError.unsupportedSchema(payload.schemaVersion)
        }
        try payload.configuration.validate(targetTriple: input.targetTriple, platform: platform)

        let packager = try context.tool(named: "IOSAppPackager")
        let processEnvironment = ProcessInfo.processInfo.environment
        let hostEnvironment = ["HOME", "USER", "LOGNAME"].reduce(into: [String: String]()) {
            if let value = processEnvironment[$1] {
                $0[$1] = value
            }
        }
        var arguments = [
            "--payload-json", payloadJSON,
            "--aggregate-archive", input.aggregateStaticLibraryURL.path,
            "--target-triple", input.targetTriple,
            "--configuration", input.buildConfiguration,
            "--platform", platform.rawValue,
        ]
        for resourceFile in input.resourceURLs {
            arguments += ["--resource-file", resourceFile.path]
        }

        switch platform {
        case .device:
            let archive = input.outputDirectoryURL
                .appendingPathComponent("\(input.product.name).xcarchive", isDirectory: true)
            let ipa = input.outputDirectoryURL.appendingPathComponent("\(input.product.name).ipa")
            let report = input.outputDirectoryURL.appendingPathComponent("\(input.product.name)-build-report.json")
            let archiveOutputs = predictedArchiveOutputs(
                archive: archive,
                configuration: payload.configuration
            )
            let outputs = archiveOutputs + [ipa, report]
            arguments += [
                "--output-archive", archive.path,
                "--output-ipa", ipa.path,
                "--output-report", report.path,
            ]
            return ProductBuilderPlan(
                commands: [
                    .buildCommand(
                        displayName: "Packaging \(input.product.name) as an iOS archive and IPA",
                        executable: packager.url,
                        arguments: arguments,
                        environment: hostEnvironment,
                        inputFiles: [input.aggregateStaticLibraryURL]
                            + input.resourceURLs,
                        outputFiles: outputs
                    ),
                ],
                outputFiles: outputs
            )
        case .simulator:
            let app = input.outputDirectoryURL
                .appendingPathComponent("\(input.product.name)-simulator.app", isDirectory: true)
            let report = input.outputDirectoryURL
                .appendingPathComponent("\(input.product.name)-simulator-build-report.json")
            let outputs = predictedApplicationOutputs(
                app: app,
                configuration: payload.configuration
            ) + [report]
            arguments += [
                "--output-app", app.path,
                "--output-report", report.path,
            ]
            return ProductBuilderPlan(
                commands: [
                    .buildCommand(
                        displayName: "Packaging \(input.product.name) as an iOS Simulator application",
                        executable: packager.url,
                        arguments: arguments,
                        environment: hostEnvironment,
                        inputFiles: [input.aggregateStaticLibraryURL]
                            + input.resourceURLs,
                        outputFiles: outputs
                    ),
                ],
                outputFiles: outputs
            )
        }
    }

    private func predictedArchiveOutputs(
        archive: URL,
        configuration: IOSApplicationConfiguration
    ) -> [URL] {
        let scheme = sanitizedName(
            configuration.identity.executableName ?? configuration.identity.displayName,
            fallback: "SwiftPMIOSApp"
        )
        let app = archive
            .appendingPathComponent("Products/Applications", isDirectory: true)
            .appendingPathComponent("\(scheme).app", isDirectory: true)
        var outputs = [archive.appendingPathComponent("Info.plist")]
            + predictedApplicationOutputs(app: app, configuration: configuration)
        if configuration.build.generateDSYM {
            let dSYM = archive
                .appendingPathComponent("dSYMs", isDirectory: true)
                .appendingPathComponent("\(scheme).app.dSYM", isDirectory: true)
            outputs += [
                dSYM.appendingPathComponent("Contents/Info.plist"),
                dSYM
                    .appendingPathComponent("Contents/Resources/DWARF", isDirectory: true)
                    .appendingPathComponent(configuration.identity.executableName ?? scheme),
            ]
        }
        return outputs
    }

    private func predictedApplicationOutputs(
        app: URL,
        configuration: IOSApplicationConfiguration
    ) -> [URL] {
        let scheme = sanitizedName(
            configuration.identity.executableName ?? configuration.identity.displayName,
            fallback: "SwiftPMIOSApp"
        )
        return [
            app.appendingPathComponent("Info.plist"),
            app.appendingPathComponent(configuration.identity.executableName ?? scheme),
            app.appendingPathComponent("Assets.car"),
        ]
    }

    private func sanitizedName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "_"
        }
        let result = String(scalars)
        return result.isEmpty ? fallback : result
    }
}

private enum BuilderError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case invalidArgumentCount(Int)
    case unsupportedTriple(String)
    case unsupportedSchema(Int)

    var description: String {
        switch self {
        case .unsupportedType(let value):
            return "unsupported artifact product type '\(value)'"
        case .invalidArgumentCount(let count):
            return "expected exactly one Codable JSON payload, received \(count) arguments"
        case .unsupportedTriple(let triple):
            return "iOS app products require an arm64 iphoneos or iphonesimulator destination triple; received '\(triple)'"
        case .unsupportedSchema(let version):
            return "unsupported iOS app payload schema \(version)"
        }
    }
}

private enum IOSBuilderPlatform: String {
    case device
    case simulator

    init?(targetTriple: String) {
        let prefix = "arm64-apple-ios"
        guard targetTriple.hasPrefix(prefix) else { return nil }
        let suffix = String(targetTriple.dropFirst(prefix.count))
        if suffix.hasSuffix("-simulator") {
            let version = suffix.dropLast("-simulator".count)
            guard !version.isEmpty, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
            self = .simulator
        } else {
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
            self = .device
        }
    }
}

private extension IOSApplicationConfiguration {
    func validate(targetTriple: String, platform: IOSBuilderPlatform) throws {
        guard !identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationValidationError("displayName must not be empty")
        }
        let bundleParts = identity.bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard bundleParts.count >= 2,
              bundleParts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) })
        else {
            throw ConfigurationValidationError("'\(identity.bundleIdentifier)' is not a valid reverse-DNS bundle identifier")
        }
        guard !identity.marketingVersion.isEmpty, !identity.buildNumber.isEmpty else {
            throw ConfigurationValidationError("marketingVersion and buildNumber must not be empty")
        }
        if let executableName = identity.executableName {
            guard !executableName.isEmpty,
                  !executableName.contains("/"),
                  executableName != ".",
                  executableName != ".."
            else {
                throw ConfigurationValidationError("executableName must be a nonempty file name")
            }
        }
        guard deployment.architectures == [.arm64] else {
            throw ConfigurationValidationError("the device prototype currently supports exactly the arm64 architecture")
        }
        guard targetTriple.hasPrefix("arm64-apple-ios") else {
            throw ConfigurationValidationError("the configured arm64 architecture does not match '\(targetTriple)'")
        }
        let tripleVersion = targetTriple
            .dropFirst("arm64-apple-ios".count)
            .prefix(while: { $0.isNumber || $0 == "." })
        guard let normalizedTripleVersion = normalizedVersion(String(tripleVersion)),
              let normalizedDeploymentVersion = normalizedVersion(deployment.minimumIOSVersion),
              normalizedTripleVersion == normalizedDeploymentVersion
        else {
            throw ConfigurationValidationError(
                "minimumIOSVersion \(deployment.minimumIOSVersion) does not match destination triple \(targetTriple)"
            )
        }
        guard !deployment.deviceFamilies.isEmpty else {
            throw ConfigurationValidationError("at least one device family is required")
        }
        if interface.launchScreen.kind == .storyboard {
            throw ConfigurationValidationError(
                "storyboard launch screens are reserved by the schema but not yet copied into the main app bundle; use .generated()"
            )
        }
        guard resources.placements.isEmpty else {
            throw ConfigurationValidationError(
                "resource placements require source/destination pairs that the current SwiftPM input API does not expose"
            )
        }
        guard linking.libraries.isEmpty else {
            throw ConfigurationValidationError(
                "library inputs are reserved by the schema but rejected by the current SwiftPM prototype"
            )
        }
        guard platform == .device else { return }

        guard export.destination == .export else {
            throw ConfigurationValidationError("product builders must emit an IPA and therefore do not support upload destinations")
        }
        guard export.method != .validation else {
            throw ConfigurationValidationError("the validation export method does not emit the required IPA")
        }
        guard export.thinning == nil || export.thinning == "<none>" else {
            throw ConfigurationValidationError(
                "this product declares one IPA output and therefore supports only nil or <none> thinning"
            )
        }
        if export.method == .appStoreConnect, assets.appIcon == nil {
            throw ConfigurationValidationError(
                "App Store Connect exports require an explicit app-icon asset catalog with a marketing icon"
            )
        }
        switch signing.style {
        case .automatic:
            guard signing.teamIdentifier?.isEmpty == false else {
                throw ConfigurationValidationError("automatic signing requires a teamIdentifier")
            }
            if export.signingStyle == .manual {
                throw ConfigurationValidationError("automatic archive signing cannot use manual export signing in this prototype")
            }
            if signing.allowDeviceRegistration && !signing.allowProvisioningUpdates {
                throw ConfigurationValidationError(
                    "device registration also requires allowProvisioningUpdates"
                )
            }
        case .manual:
            guard signing.teamIdentifier?.isEmpty == false,
                  signing.identity?.isEmpty == false,
                  signing.provisioningProfile != nil
            else {
                throw ConfigurationValidationError("manual signing requires a team, identity, and provisioning profile")
            }
            if signing.provisioningProfile?.kind == .path {
                throw ConfigurationValidationError(
                    "manual profile paths are not installed implicitly; use a profile name or UUID"
                )
            }
            if export.signingStyle == .automatic {
                throw ConfigurationValidationError("manual archive signing cannot use automatic export signing in this prototype")
            }
        case .localAdHoc, .unsigned:
            break
        }
    }

    func normalizedVersion(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, let integers = try? components.map({ component -> Int in
            guard let value = Int(component) else { throw ConfigurationValidationError("invalid version") }
            return value
        }) else {
            return nil
        }
        var normalized = integers
        while normalized.last == 0 { normalized.removeLast() }
        return normalized
    }
}

private struct ConfigurationValidationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = "invalid iOS application configuration: \(description)"
    }
}

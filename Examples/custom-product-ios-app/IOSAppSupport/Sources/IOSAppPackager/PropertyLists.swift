import Foundation

enum PropertyLists {
    static func infoPlist(for configuration: IOSApplicationConfiguration) -> [String: Any] {
        var plist = configuration.infoPlist.additionalEntries.mapValues(\.foundationValue)
        let identity = configuration.identity
        let interface = configuration.interface

        plist["CFBundleDevelopmentRegion"] = configuration.resources.developmentRegion
        plist["CFBundleDisplayName"] = identity.displayName
        plist["CFBundleExecutable"] = "$(EXECUTABLE_NAME)"
        plist["CFBundleIdentifier"] = "$(PRODUCT_BUNDLE_IDENTIFIER)"
        plist["CFBundleInfoDictionaryVersion"] = "6.0"
        plist["CFBundleName"] = "$(PRODUCT_NAME)"
        plist["CFBundlePackageType"] = "APPL"
        plist["CFBundleShortVersionString"] = "$(MARKETING_VERSION)"
        plist["CFBundleVersion"] = "$(CURRENT_PROJECT_VERSION)"
        plist["LSRequiresIPhoneOS"] = true
        plist["UIApplicationSupportsIndirectInputEvents"] = true
        plist["UIRequiresFullScreen"] = interface.requiresFullScreen
        plist["UISupportedInterfaceOrientations"] = interface.phoneOrientations.map(\.plistName)
        if configuration.deployment.deviceFamilies.contains(.ipad) {
            plist["UISupportedInterfaceOrientations~ipad"] = interface.padOrientations.map(\.plistName)
        }
        plist["UIRequiredDeviceCapabilities"] = configuration.deployment.architectures.map(\.rawValue)

        if configuration.assets.appIcon == nil {
            plist["CFBundleIconFiles"] = ["AppIcon60x60"]
            plist["CFBundleIcons"] = [
                "CFBundlePrimaryIcon": [
                    "CFBundleIconFiles": ["AppIcon60x60"],
                ],
            ]
            if configuration.deployment.deviceFamilies.contains(.ipad) {
                plist["CFBundleIcons~ipad"] = [
                    "CFBundlePrimaryIcon": [
                        "CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76", "AppIcon83.5x83.5"],
                    ],
                ]
            }
        }

        switch interface.launchScreen.kind {
        case .generated:
            var launchScreen: [String: Any] = [:]
            if let color = interface.launchScreen.backgroundColorAsset {
                launchScreen["UIColorName"] = color
            }
            if let image = interface.launchScreen.imageAsset {
                launchScreen["UIImageName"] = image
                launchScreen["UIImageRespectsSafeAreaInsets"] = true
            }
            plist["UILaunchScreen"] = launchScreen
        case .storyboard:
            if let resource = interface.launchScreen.storyboardResource {
                plist["UILaunchStoryboardName"] = URL(fileURLWithPath: resource).deletingPathExtension().lastPathComponent
            }
        }

        if !configuration.infoPlist.backgroundModes.isEmpty {
            plist["UIBackgroundModes"] = configuration.infoPlist.backgroundModes
        }
        if !configuration.infoPlist.urlTypes.isEmpty {
            plist["CFBundleURLTypes"] = configuration.infoPlist.urlTypes.map { type in
                var value: [String: Any] = ["CFBundleURLSchemes": type.schemes]
                if let name = type.name { value["CFBundleURLName"] = name }
                return value
            }
        }
        for (key, value) in configuration.infoPlist.privacyUsageDescriptions {
            plist[key] = value
        }
        if let encryption = configuration.infoPlist.usesNonExemptEncryption {
            plist["ITSAppUsesNonExemptEncryption"] = encryption
        }
        return plist
    }

    static func entitlements(for capabilities: IOSCapabilities) -> [String: Any] {
        var result = capabilities.additionalEntitlements.mapValues(\.foundationValue)
        if !capabilities.applicationGroups.isEmpty {
            result["com.apple.security.application-groups"] = capabilities.applicationGroups
        }
        if !capabilities.associatedDomains.isEmpty {
            result["com.apple.developer.associated-domains"] = capabilities.associatedDomains
        }
        if !capabilities.keychainAccessGroups.isEmpty {
            result["keychain-access-groups"] = capabilities.keychainAccessGroups
        }
        if let environment = capabilities.pushEnvironment {
            result["aps-environment"] = environment.rawValue
        }
        if !capabilities.iCloudContainers.isEmpty {
            result["com.apple.developer.icloud-container-identifiers"] = capabilities.iCloudContainers
        }
        return result
    }

    static func exportOptions(for configuration: IOSApplicationConfiguration) throws -> [String: Any] {
        guard configuration.signing.style == .automatic || configuration.signing.style == .manual else {
            throw PackagerError("unsigned and local ad-hoc builds are packaged directly and cannot use Xcode's signed export step")
        }
        var result: [String: Any] = [
            "destination": configuration.export.destination.rawValue,
            "method": configuration.export.method.rawValue,
            "stripSwiftSymbols": configuration.export.stripSwiftSymbols,
            "uploadSymbols": configuration.export.uploadSymbols,
            "manageAppVersionAndBuildNumber": configuration.export.manageAppVersionAndBuildNumber,
        ]
        if let team = configuration.signing.teamIdentifier { result["teamID"] = team }
        result["signingStyle"] = configuration.export.signingStyle?.rawValue
            ?? (configuration.signing.style == .manual ? "manual" : "automatic")
        if let thinning = configuration.export.thinning { result["thinning"] = thinning }
        if configuration.signing.style == .manual,
           let profile = configuration.signing.provisioningProfile
        {
            guard profile.kind != .path else {
                throw PackagerError("manual profile paths are not installed implicitly; use a profile name or UUID")
            }
            result["provisioningProfiles"] = [configuration.identity.bundleIdentifier: profile.value]
            if let identity = configuration.signing.identity {
                result["signingCertificate"] = identity
            }
        }
        return result
    }

    static func write(_ value: Any, to url: URL) throws {
        guard PropertyListSerialization.propertyList(value, isValidFor: .xml) else {
            throw PackagerError("generated property list is invalid: \(url.lastPathComponent)")
        }
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }
}

private extension IOSInterfaceOrientation {
    var plistName: String {
        switch self {
        case .portrait: "UIInterfaceOrientationPortrait"
        case .portraitUpsideDown: "UIInterfaceOrientationPortraitUpsideDown"
        case .landscapeLeft: "UIInterfaceOrientationLandscapeLeft"
        case .landscapeRight: "UIInterfaceOrientationLandscapeRight"
        }
    }
}

extension PlistValue {
    var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .integer(let value): value
        case .real(let value): value
        case .bool(let value): value
        case .array(let values): values.map(\.foundationValue)
        case .dictionary(let values): values.mapValues(\.foundationValue)
        }
    }
}

// swift-tools-version: 6.3;(experimentalProductBuilders)

import Foundation
import IOSAppProductTypes
import PackageDescription

let environment = ProcessInfo.processInfo.environment

let signing: IOSSigning = {
    switch environment["IOS_DEMO_SIGNING"] ?? "unsigned" {
    case "unsigned":
        return .unsigned
    case "local-ad-hoc":
        return .localAdHoc
    case "automatic":
        guard let team = environment["IOS_DEMO_TEAM_ID"], !team.isEmpty else {
            fatalError("IOS_DEMO_TEAM_ID is required when IOS_DEMO_SIGNING=automatic")
        }
        return .init(
            style: .automatic,
            teamIdentifier: team,
            allowProvisioningUpdates: environment["IOS_DEMO_ALLOW_PROVISIONING_UPDATES"] == "1",
            allowDeviceRegistration: environment["IOS_DEMO_ALLOW_DEVICE_REGISTRATION"] == "1"
        )
    case "manual":
        guard let team = environment["IOS_DEMO_TEAM_ID"],
              let identity = environment["IOS_DEMO_SIGNING_IDENTITY"],
              let profile = environment["IOS_DEMO_PROFILE_NAME"]
        else {
            fatalError(
                "IOS_DEMO_TEAM_ID, IOS_DEMO_SIGNING_IDENTITY, and IOS_DEMO_PROFILE_NAME "
                    + "are required when IOS_DEMO_SIGNING=manual"
            )
        }
        return .manual(
            teamIdentifier: team,
            identity: identity,
            provisioningProfile: .named(profile)
        )
    default:
        fatalError("IOS_DEMO_SIGNING must be unsigned, local-ad-hoc, automatic, or manual")
    }
}()

let package = Package(
    name: "SwiftPMIOSAppDemo",
    platforms: [.iOS(.v17)],
    products: [
        .iOSApplication(
            name: "IOSDemoIPA",
            target: "DemoApp",
            configuration: .init(
                identity: .init(
                    bundleIdentifier: environment["IOS_DEMO_BUNDLE_ID"] ?? "dev.swiftpm.custom-products.ios-demo",
                    displayName: "SwiftPM IPA Demo",
                    marketingVersion: "1.0",
                    buildNumber: "1",
                    executableName: "SwiftPMIPADemo"
                ),
                signing: signing,
                deployment: .init(
                    minimumIOSVersion: "17.0",
                    architectures: [.arm64],
                    deviceFamilies: [.iphone, .ipad]
                ),
                interface: .init(
                    phoneOrientations: [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight],
                    padOrientations: [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight],
                    launchScreen: .generated()
                ),
                assets: .init(
                    appIcon: .init(catalogResource: "AppAssets.xcassets", setName: "AppIcon"),
                    accentColor: .init(catalogResource: "AppAssets.xcassets", setName: "AccentColor")
                ),
                resources: .init(embedAllSwiftPMResources: true),
                linking: .init(
                    frameworks: [.required("SwiftUI"), .required("UIKit")]
                ),
                infoPlist: .init(
                    urlTypes: [.init(name: "SwiftPM IPA Demo", schemes: ["swiftpm-ipa-demo"])],
                    usesNonExemptEncryption: false,
                    additionalEntries: [
                        "DemoBuildPipeline": "SwiftPMProductBuilder",
                    ]
                ),
                build: .init(
                    deadStrip: true,
                    stripSymbols: false,
                    generateDSYM: true,
                    embedSwiftStandardLibraries: true
                ),
                export: .init(method: .debugging, thinning: "<none>")
            )
        ),
    ],
    dependencies: [
        .package(name: "IOSAppSupport", path: "IOSAppSupport"),
    ],
    targets: [
        .target(
            name: "DemoApp",
            resources: [
                .process("Resources"),
                // Preserve the raw catalog for the product builder. SwiftPM's
                // resource bundle is an input; the generated app target owns
                // the actual AppIcon compilation step.
                .copy("AppAssets.xcassets"),
            ]
        ),
    ]
)

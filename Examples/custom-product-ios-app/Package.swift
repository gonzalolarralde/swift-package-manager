// swift-tools-version: 6.3;(experimentalProductBuilders)

import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment

let signing: [String: Any] = {
    switch environment["IOS_DEMO_SIGNING"] ?? "unsigned" {
    case "unsigned":
        return [
            "style": "unsigned",
            "allowProvisioningUpdates": false,
            "allowDeviceRegistration": false,
        ]
    case "local-ad-hoc":
        return [
            "style": "localAdHoc",
            "allowProvisioningUpdates": false,
            "allowDeviceRegistration": false,
        ]
    case "automatic":
        guard let team = environment["IOS_DEMO_TEAM_ID"], !team.isEmpty else {
            fatalError("IOS_DEMO_TEAM_ID is required when IOS_DEMO_SIGNING=automatic")
        }
        return [
            "style": "automatic",
            "teamIdentifier": team,
            "allowProvisioningUpdates": environment["IOS_DEMO_ALLOW_PROVISIONING_UPDATES"] == "1",
            "allowDeviceRegistration": environment["IOS_DEMO_ALLOW_DEVICE_REGISTRATION"] == "1",
        ]
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
        return [
            "style": "manual",
            "teamIdentifier": team,
            "identity": identity,
            "provisioningProfile": [
                "kind": "name",
                "value": profile,
            ],
            "allowProvisioningUpdates": false,
            "allowDeviceRegistration": false,
        ]
    default:
        fatalError("IOS_DEMO_SIGNING must be unsigned, local-ad-hoc, automatic, or manual")
    }
}()

let builderPayloadObject: [String: Any] = [
    "schemaVersion": 1,
    "configuration": [
        "identity": [
            "bundleIdentifier": environment["IOS_DEMO_BUNDLE_ID"]
                ?? "dev.swiftpm.custom-products.ios-demo",
            "displayName": "SwiftPM IPA Demo",
            "marketingVersion": "1.0",
            "buildNumber": "1",
            "executableName": "SwiftPMIPADemo",
        ],
        "signing": signing,
        "deployment": [
            "minimumIOSVersion": "17.0",
            "architectures": ["arm64"],
            "deviceFamilies": ["iphone", "ipad"],
        ],
        "interface": [
            "phoneOrientations": [
                "portrait",
                "portraitUpsideDown",
                "landscapeLeft",
                "landscapeRight",
            ],
            "padOrientations": [
                "portrait",
                "portraitUpsideDown",
                "landscapeLeft",
                "landscapeRight",
            ],
            "requiresFullScreen": false,
            "launchScreen": [
                "kind": "generated",
            ],
        ],
        "assets": [
            "catalogs": [],
            "appIcon": [
                "catalogResource": "AppAssets.xcassets",
                "setName": "AppIcon",
            ],
            "accentColor": [
                "catalogResource": "AppAssets.xcassets",
                "setName": "AccentColor",
            ],
        ],
        "resources": [
            "embedAllSwiftPMResources": true,
            "placements": [],
            "developmentRegion": "en",
        ],
        "linking": [
            "frameworks": [
                ["name": "SwiftUI", "linkage": "required"],
                ["name": "UIKit", "linkage": "required"],
            ],
            "libraries": [],
            "otherLinkerFlags": [],
        ],
        "capabilities": [
            "applicationGroups": [],
            "associatedDomains": [],
            "keychainAccessGroups": [],
            "iCloudContainers": [],
            "additionalEntitlements": [:],
        ],
        "infoPlist": [
            "privacyUsageDescriptions": [:],
            "backgroundModes": [],
            "urlTypes": [
                [
                    "name": "SwiftPM IPA Demo",
                    "schemes": ["swiftpm-ipa-demo"],
                ],
            ],
            "usesNonExemptEncryption": false,
            "additionalEntries": [
                "DemoBuildPipeline": "SwiftPMProductBuilder",
            ],
        ],
        "build": [
            "deadStrip": true,
            "stripSymbols": false,
            "generateDSYM": true,
            "embedSwiftStandardLibraries": true,
        ],
        "export": [
            "method": "debugging",
            "destination": "export",
            "thinning": "<none>",
            "stripSwiftSymbols": true,
            "uploadSymbols": true,
            "manageAppVersionAndBuildNumber": false,
        ],
    ],
]

let builderPayload: String = {
    guard JSONSerialization.isValidJSONObject(builderPayloadObject) else {
        fatalError("iOS builder payload is not valid JSON")
    }
    do {
        let data = try JSONSerialization.data(
            withJSONObject: builderPayloadObject,
            options: [.sortedKeys]
        )
        guard let json = String(data: data, encoding: .utf8) else {
            fatalError("iOS builder payload is not valid UTF-8")
        }
        return json
    } catch {
        fatalError("unable to encode iOS builder payload: \(error)")
    }
}()

let package = Package(
    name: "SwiftPMIOSAppDemo",
    platforms: [.iOS(.v17)],
    products: [
        .artifact(
            name: "IOSDemoIPA",
            typeIdentifier: "pkg:swift/github.com/example/IOSAppSupport",
            targets: ["DemoApp"],
            builderPlugin: .pluginItem(
                name: "IOSAppBuilder",
                package: "IOSAppSupport"
            ),
            arguments: [builderPayload]
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

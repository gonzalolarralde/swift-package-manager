import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct GeneratedXcodeProject {
    let root: URL
    let project: URL
    let scheme: String
    let entitlements: URL
    let copiedResourceBundles: [URL]
}

enum XcodeProjectGenerator {
    static func generate(
        at root: URL,
        aggregateArchive: URL,
        resourceBundles: [URL],
        platform: PackagerPlatform,
        configuration: IOSApplicationConfiguration
    ) throws -> GeneratedXcodeProject {
        let fileManager = FileManager.default
        let generated = root.appendingPathComponent("Generated", isDirectory: true)
        let inputs = root.appendingPathComponent("Inputs", isDirectory: true)
        let copiedBundlesRoot = inputs.appendingPathComponent("ResourceBundles", isDirectory: true)
        try fileManager.createDirectory(at: generated, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: copiedBundlesRoot, withIntermediateDirectories: true)

        let productArchive = inputs.appendingPathComponent("Product.a")
        try fileManager.copyItem(at: aggregateArchive, to: productArchive)
        try "enum SwiftPMProductBuilderLinkAnchor {}\n".write(
            to: generated.appendingPathComponent("LinkAnchor.swift"),
            atomically: true,
            encoding: .utf8
        )

        var copiedBundles: [URL] = []
        var seenBundleNames = Set<String>()
        if configuration.resources.embedAllSwiftPMResources {
            for bundle in resourceBundles.sorted(by: { $0.path < $1.path }) {
                guard seenBundleNames.insert(bundle.lastPathComponent).inserted else {
                    throw PackagerError("multiple SwiftPM resource bundles are named \(bundle.lastPathComponent)")
                }
                let destination = copiedBundlesRoot.appendingPathComponent(bundle.lastPathComponent, isDirectory: true)
                try fileManager.copyItem(at: bundle, to: destination)
                copiedBundles.append(destination)
            }
        }

        guard configuration.linking.libraries.isEmpty else {
            throw PackagerError("linked library inputs are modeled but not exposed by the current SwiftPM prototype")
        }

        let infoPlist = generated.appendingPathComponent("Info.plist")
        let entitlements = generated.appendingPathComponent("App.entitlements")
        try PropertyLists.write(PropertyLists.infoPlist(for: configuration), to: infoPlist)
        let entitlementValues = PropertyLists.entitlements(for: configuration.capabilities)
        try PropertyLists.write(entitlementValues, to: entitlements)

        let catalogs = try prepareAssetCatalogs(
            in: generated,
            resourceBundles: resourceBundles,
            configuration: configuration
        )

        let scheme = sanitizedName(
            configuration.identity.executableName ?? configuration.identity.displayName,
            fallback: "SwiftPMIOSApp"
        )
        let resourcePaths = catalogs.map { relativePath(of: $0, under: root) }
            + copiedBundles.map { relativePath(of: $0, under: root) }
        let projectSpec = try makeProjectSpec(
            name: scheme,
            platform: platform,
            configuration: configuration,
            resourcePaths: resourcePaths,
            hasEntitlements: !entitlementValues.isEmpty
        )
        let specURL = root.appendingPathComponent("project.yml")
        let specData = try JSONSerialization.data(
            withJSONObject: projectSpec,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try specData.write(to: specURL, options: .atomic)

        return GeneratedXcodeProject(
            root: root,
            project: root.appendingPathComponent("\(scheme).xcodeproj", isDirectory: true),
            scheme: scheme,
            entitlements: entitlements,
            copiedResourceBundles: copiedBundles
        )
    }

    private static func prepareAssetCatalogs(
        in generated: URL,
        resourceBundles: [URL],
        configuration: IOSApplicationConfiguration
    ) throws -> [URL] {
        let fileManager = FileManager.default
        let catalogsRoot = generated.appendingPathComponent("AssetCatalogs", isDirectory: true)
        try fileManager.createDirectory(at: catalogsRoot, withIntermediateDirectories: true)

        let requested = Set(
            configuration.assets.catalogs
                + [configuration.assets.appIcon?.catalogResource, configuration.assets.accentColor?.catalogResource]
                    .compactMap { $0 }
        )
        var prepared = try requested.sorted().map { name in
            guard let source = findResource(named: name, beneath: resourceBundles) else {
                throw PackagerError(
                    "asset catalog '\(name)' was not found in a SwiftPM resource bundle; declare it with .copy so raw catalog contents survive"
                )
            }
            let destination = catalogsRoot.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
        if configuration.assets.appIcon == nil {
            prepared += try makeDefaultAppIcons(
                at: generated.appendingPathComponent("AppIcons", isDirectory: true)
            )
        }
        return prepared
    }

    private static func findResource(named name: String, beneath roots: [URL]) -> URL? {
        let fileManager = FileManager.default
        for root in roots {
            if root.lastPathComponent == name { return root }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let candidate as URL in enumerator where candidate.lastPathComponent == name {
                return candidate
            }
        }
        return nil
    }

    private static func makeDefaultAppIcons(at directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let variants = [
            ("AppIcon60x60@2x.png", 120),
            ("AppIcon60x60@3x.png", 180),
            ("AppIcon76x76@2x.png", 152),
            ("AppIcon83.5x83.5@2x.png", 167),
        ]
        return try variants.map { name, size in
            let url = directory.appendingPathComponent(name)
            try writeDefaultIcon(to: url, size: size)
            return url
        }
    }

    private static func writeDefaultIcon(to url: URL, size: Int) throws {
        let width = size
        let height = size
        let scale = CGFloat(size) / 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PackagerError("unable to create the generated app icon context")
        }

        let colors = [
            CGColor(red: 0.08, green: 0.22, blue: 0.56, alpha: 1),
            CGColor(red: 0.34, green: 0.12, blue: 0.72, alpha: 1),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: width, y: height),
            options: []
        )
        context.setFillColor(CGColor(gray: 1, alpha: 0.94))
        context.fillEllipse(in: CGRect(x: 210 * scale, y: 210 * scale, width: 604 * scale, height: 604 * scale))
        context.setFillColor(CGColor(red: 0.20, green: 0.31, blue: 0.74, alpha: 1))
        context.fill(CGRect(x: 330 * scale, y: 472 * scale, width: 364 * scale, height: 80 * scale))
        context.fill(CGRect(x: 472 * scale, y: 330 * scale, width: 80 * scale, height: 364 * scale))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw PackagerError("unable to create the generated app icon destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PackagerError("unable to write the generated app icon")
        }
    }

    private static func makeProjectSpec(
        name: String,
        platform: PackagerPlatform,
        configuration: IOSApplicationConfiguration,
        resourcePaths: [String],
        hasEntitlements: Bool
    ) throws -> [String: Any] {
        var linkerFlags = ["$(inherited)", "-force_load", "$(PROJECT_DIR)/Inputs/Product.a"]
        for framework in configuration.linking.frameworks {
            linkerFlags += [framework.linkage == .weak ? "-weak_framework" : "-framework", framework.name]
        }
        linkerFlags += configuration.linking.otherLinkerFlags

        let deviceFamilies = configuration.deployment.deviceFamilies.map { family in
            switch family {
            case .iphone: "1"
            case .ipad: "2"
            }
        }.joined(separator: ",")

        var settings: [String: Any] = [
            "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": configuration.build.embedSwiftStandardLibraries ? "YES" : "NO",
            "ARCHS": configuration.deployment.architectures.map(\.rawValue),
            "COPY_PHASE_STRIP": configuration.build.stripSymbols ? "YES" : "NO",
            "CURRENT_PROJECT_VERSION": configuration.identity.buildNumber,
            "DEAD_CODE_STRIPPING": configuration.build.deadStrip ? "YES" : "NO",
            "DEBUG_INFORMATION_FORMAT": configuration.build.generateDSYM ? "dwarf-with-dsym" : "dwarf",
            "EXECUTABLE_NAME": configuration.identity.executableName ?? "$(PRODUCT_NAME)",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Generated/Info.plist",
            "IPHONEOS_DEPLOYMENT_TARGET": configuration.deployment.minimumIOSVersion,
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "MACH_O_TYPE": "mh_execute",
            "MARKETING_VERSION": configuration.identity.marketingVersion,
            "ONLY_ACTIVE_ARCH": "NO",
            "OTHER_LDFLAGS": linkerFlags,
            "PRODUCT_BUNDLE_IDENTIFIER": configuration.identity.bundleIdentifier,
            "PRODUCT_NAME": name,
            "SDKROOT": platform.sdkRoot,
            "SKIP_INSTALL": "NO",
            "STRIP_INSTALLED_PRODUCT": configuration.build.stripSymbols ? "YES" : "NO",
            "SUPPORTED_PLATFORMS": platform.supportedPlatforms,
            "SUPPORTS_MACCATALYST": "NO",
            "SWIFT_VERSION": "6.0",
            "TARGETED_DEVICE_FAMILY": deviceFamilies,
        ]
        if hasEntitlements && platform == .device {
            settings["CODE_SIGN_ENTITLEMENTS"] = "Generated/App.entitlements"
        }
        if let accent = configuration.assets.accentColor {
            settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = accent.setName
        }
        if let appIcon = configuration.assets.appIcon {
            settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = appIcon.setName
        }
        if platform == .simulator {
            settings["CODE_SIGNING_ALLOWED"] = "NO"
            settings["CODE_SIGNING_REQUIRED"] = "NO"
        } else {
            applySigningSettings(configuration.signing, to: &settings)
        }

        let sources: [[String: Any]] = [["path": "Generated/LinkAnchor.swift"]]
            + resourcePaths.map { ["path": $0, "buildPhase": "resources"] }
        let target: [String: Any] = [
            "type": "application",
            "platform": "iOS",
            "deploymentTarget": configuration.deployment.minimumIOSVersion,
            "sources": sources,
            "settings": ["base": settings],
        ]
        return [
            "name": name,
            "options": [
                "deploymentTarget": ["iOS": configuration.deployment.minimumIOSVersion],
            ],
            "settings": ["base": ["SDKROOT": platform.sdkRoot]],
            "targets": [name: target],
            "schemes": [
                name: [
                    "build": ["targets": [name: "all"]],
                    "archive": ["config": "Release"],
                ],
            ],
        ]
    }

    private static func applySigningSettings(_ signing: IOSSigning, to settings: inout [String: Any]) {
        switch signing.style {
        case .unsigned, .localAdHoc:
            settings["CODE_SIGNING_ALLOWED"] = "NO"
            settings["CODE_SIGNING_REQUIRED"] = "NO"
        case .automatic:
            settings["CODE_SIGN_STYLE"] = "Automatic"
            if let teamIdentifier = signing.teamIdentifier {
                settings["DEVELOPMENT_TEAM"] = teamIdentifier
            }
        case .manual:
            settings["CODE_SIGN_STYLE"] = "Manual"
            if let teamIdentifier = signing.teamIdentifier {
                settings["DEVELOPMENT_TEAM"] = teamIdentifier
            }
            if let identity = signing.identity {
                settings["CODE_SIGN_IDENTITY"] = identity
            }
            if let profile = signing.provisioningProfile {
                switch profile.kind {
                case .name:
                    settings["PROVISIONING_PROFILE_SPECIFIER"] = profile.value
                case .uuid:
                    settings["PROVISIONING_PROFILE"] = profile.value
                case .path:
                    break
                }
            }
        }
    }

    private static func relativePath(of child: URL, under root: URL) -> String {
        let prefix = root.standardizedFileURL.path + "/"
        return String(child.standardizedFileURL.path.dropFirst(prefix.count))
    }

    private static func sanitizedName(_ value: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars)
        return result.isEmpty ? fallback : result
    }

    private static func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

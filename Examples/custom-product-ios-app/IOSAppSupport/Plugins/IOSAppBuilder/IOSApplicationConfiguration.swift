import Foundation

/// The stable, versioned wire envelope shared by the manifest definition
/// library and the product-builder plug-in.
public struct IOSAppBuilderPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let typeIdentifier = "pkg:swift/github.com/example/IOSAppSupport"

    public var schemaVersion: Int
    public var configuration: IOSApplicationConfiguration

    public init(
        schemaVersion: Int = IOSAppBuilderPayload.currentSchemaVersion,
        configuration: IOSApplicationConfiguration
    ) {
        self.schemaVersion = schemaVersion
        self.configuration = configuration
    }
}

/// A composable description of the pieces that make up an installable iOS app.
public struct IOSApplicationConfiguration: Codable, Equatable, Sendable {
    public var identity: IOSBundleIdentity
    public var signing: IOSSigning
    public var deployment: IOSDeployment
    public var interface: IOSInterfaceConfiguration
    public var assets: IOSAssets
    public var resources: IOSResources
    public var linking: IOSLinking
    public var capabilities: IOSCapabilities
    public var infoPlist: IOSInfoPlist
    public var build: IOSBuildOptions
    public var export: IOSExportOptions

    public init(
        identity: IOSBundleIdentity,
        signing: IOSSigning,
        deployment: IOSDeployment = .init(),
        interface: IOSInterfaceConfiguration = .init(),
        assets: IOSAssets = .init(),
        resources: IOSResources = .init(),
        linking: IOSLinking = .init(),
        capabilities: IOSCapabilities = .init(),
        infoPlist: IOSInfoPlist = .init(),
        build: IOSBuildOptions = .init(),
        export: IOSExportOptions = .init()
    ) {
        self.identity = identity
        self.signing = signing
        self.deployment = deployment
        self.interface = interface
        self.assets = assets
        self.resources = resources
        self.linking = linking
        self.capabilities = capabilities
        self.infoPlist = infoPlist
        self.build = build
        self.export = export
    }
}

public struct IOSBundleIdentity: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    public var marketingVersion: String
    public var buildNumber: String
    public var executableName: String?

    public init(
        bundleIdentifier: String,
        displayName: String,
        marketingVersion: String = "1.0",
        buildNumber: String = "1",
        executableName: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
        self.executableName = executableName
    }
}

public struct IOSDeployment: Codable, Equatable, Sendable {
    public var minimumIOSVersion: String
    public var architectures: [IOSArchitecture]
    public var deviceFamilies: [IOSDeviceFamily]

    public init(
        minimumIOSVersion: String = "17.0",
        architectures: [IOSArchitecture] = [.arm64],
        deviceFamilies: [IOSDeviceFamily] = [.iphone]
    ) {
        self.minimumIOSVersion = minimumIOSVersion
        self.architectures = architectures
        self.deviceFamilies = deviceFamilies
    }
}

public enum IOSArchitecture: String, Codable, Equatable, Sendable {
    case arm64
}

public enum IOSDeviceFamily: String, Codable, Equatable, Sendable {
    case iphone
    case ipad
}

public struct IOSInterfaceConfiguration: Codable, Equatable, Sendable {
    public var phoneOrientations: [IOSInterfaceOrientation]
    public var padOrientations: [IOSInterfaceOrientation]
    public var requiresFullScreen: Bool
    public var launchScreen: IOSLaunchScreen

    public init(
        phoneOrientations: [IOSInterfaceOrientation] = [.portrait],
        padOrientations: [IOSInterfaceOrientation] = [
            .portrait,
            .portraitUpsideDown,
            .landscapeLeft,
            .landscapeRight,
        ],
        requiresFullScreen: Bool = false,
        launchScreen: IOSLaunchScreen = .generated()
    ) {
        self.phoneOrientations = phoneOrientations
        self.padOrientations = padOrientations
        self.requiresFullScreen = requiresFullScreen
        self.launchScreen = launchScreen
    }
}

public enum IOSInterfaceOrientation: String, Codable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

public struct IOSLaunchScreen: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case generated
        case storyboard
    }

    public var kind: Kind
    public var storyboardResource: String?
    public var backgroundColorAsset: String?
    public var imageAsset: String?

    public init(
        kind: Kind,
        storyboardResource: String? = nil,
        backgroundColorAsset: String? = nil,
        imageAsset: String? = nil
    ) {
        self.kind = kind
        self.storyboardResource = storyboardResource
        self.backgroundColorAsset = backgroundColorAsset
        self.imageAsset = imageAsset
    }

    public static func generated(
        backgroundColorAsset: String? = nil,
        imageAsset: String? = nil
    ) -> Self {
        .init(
            kind: .generated,
            backgroundColorAsset: backgroundColorAsset,
            imageAsset: imageAsset
        )
    }

    public static func storyboard(_ resource: String) -> Self {
        .init(kind: .storyboard, storyboardResource: resource)
    }
}

public struct IOSAssets: Codable, Equatable, Sendable {
    /// Resource input names for asset catalogs that the builder should compile.
    public var catalogs: [String]
    public var appIcon: IOSAssetCatalogItem?
    public var accentColor: IOSAssetCatalogItem?

    public init(
        catalogs: [String] = [],
        appIcon: IOSAssetCatalogItem? = nil,
        accentColor: IOSAssetCatalogItem? = nil
    ) {
        self.catalogs = catalogs
        self.appIcon = appIcon
        self.accentColor = accentColor
    }
}

public struct IOSAssetCatalogItem: Codable, Equatable, Sendable {
    public var catalogResource: String
    public var setName: String

    public init(catalogResource: String, setName: String) {
        self.catalogResource = catalogResource
        self.setName = setName
    }
}

public struct IOSResources: Codable, Equatable, Sendable {
    /// Embed all resource files supplied by SwiftPM.
    public var embedAllSwiftPMResources: Bool
    /// Optional remappings, matched against an input's last path component.
    public var placements: [IOSResourcePlacement]
    public var developmentRegion: String

    public init(
        embedAllSwiftPMResources: Bool = true,
        placements: [IOSResourcePlacement] = [],
        developmentRegion: String = "en"
    ) {
        self.embedAllSwiftPMResources = embedAllSwiftPMResources
        self.placements = placements
        self.developmentRegion = developmentRegion
    }
}

public struct IOSResourcePlacement: Codable, Equatable, Sendable {
    public var inputName: String
    public var bundleSubpath: String

    public init(inputName: String, bundleSubpath: String) {
        self.inputName = inputName
        self.bundleSubpath = bundleSubpath
    }
}

public struct IOSLinking: Codable, Equatable, Sendable {
    public var frameworks: [IOSFramework]
    public var libraries: [IOSLibrary]
    public var otherLinkerFlags: [String]

    public init(
        frameworks: [IOSFramework] = [
            .required("SwiftUI"),
            .required("UIKit"),
        ],
        libraries: [IOSLibrary] = [],
        otherLinkerFlags: [String] = []
    ) {
        self.frameworks = frameworks
        self.libraries = libraries
        self.otherLinkerFlags = otherLinkerFlags
    }
}

public struct IOSFramework: Codable, Equatable, Sendable {
    public enum Linkage: String, Codable, Equatable, Sendable {
        case required
        case weak
    }

    public var name: String
    public var linkage: Linkage

    public init(name: String, linkage: Linkage = .required) {
        self.name = name
        self.linkage = linkage
    }

    public static func required(_ name: String) -> Self {
        .init(name: name, linkage: .required)
    }

    public static func weaklyLinked(_ name: String) -> Self {
        .init(name: name, linkage: .weak)
    }
}

public struct IOSLibrary: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case staticArchive
        case framework
        case xcframework
    }

    public var inputName: String
    public var kind: Kind
    public var embed: Bool

    public init(inputName: String, kind: Kind, embed: Bool = false) {
        self.inputName = inputName
        self.kind = kind
        self.embed = embed
    }
}

public struct IOSCapabilities: Codable, Equatable, Sendable {
    public var applicationGroups: [String]
    public var associatedDomains: [String]
    public var keychainAccessGroups: [String]
    public var pushEnvironment: IOSPushEnvironment?
    public var iCloudContainers: [String]
    public var additionalEntitlements: [String: PlistValue]

    public init(
        applicationGroups: [String] = [],
        associatedDomains: [String] = [],
        keychainAccessGroups: [String] = [],
        pushEnvironment: IOSPushEnvironment? = nil,
        iCloudContainers: [String] = [],
        additionalEntitlements: [String: PlistValue] = [:]
    ) {
        self.applicationGroups = applicationGroups
        self.associatedDomains = associatedDomains
        self.keychainAccessGroups = keychainAccessGroups
        self.pushEnvironment = pushEnvironment
        self.iCloudContainers = iCloudContainers
        self.additionalEntitlements = additionalEntitlements
    }
}

public enum IOSPushEnvironment: String, Codable, Equatable, Sendable {
    case development
    case production
}

public struct IOSInfoPlist: Codable, Equatable, Sendable {
    /// Keys such as `NSCameraUsageDescription`, mapped to their user-facing text.
    public var privacyUsageDescriptions: [String: String]
    public var backgroundModes: [String]
    public var urlTypes: [IOSURLType]
    public var usesNonExemptEncryption: Bool?
    public var additionalEntries: [String: PlistValue]

    public init(
        privacyUsageDescriptions: [String: String] = [:],
        backgroundModes: [String] = [],
        urlTypes: [IOSURLType] = [],
        usesNonExemptEncryption: Bool? = nil,
        additionalEntries: [String: PlistValue] = [:]
    ) {
        self.privacyUsageDescriptions = privacyUsageDescriptions
        self.backgroundModes = backgroundModes
        self.urlTypes = urlTypes
        self.usesNonExemptEncryption = usesNonExemptEncryption
        self.additionalEntries = additionalEntries
    }
}

public struct IOSURLType: Codable, Equatable, Sendable {
    public var name: String?
    public var schemes: [String]

    public init(name: String? = nil, schemes: [String]) {
        self.name = name
        self.schemes = schemes
    }
}

public struct IOSBuildOptions: Codable, Equatable, Sendable {
    public var deadStrip: Bool
    public var stripSymbols: Bool
    public var generateDSYM: Bool
    public var embedSwiftStandardLibraries: Bool

    public init(
        deadStrip: Bool = true,
        stripSymbols: Bool = false,
        generateDSYM: Bool = true,
        embedSwiftStandardLibraries: Bool = true
    ) {
        self.deadStrip = deadStrip
        self.stripSymbols = stripSymbols
        self.generateDSYM = generateDSYM
        self.embedSwiftStandardLibraries = embedSwiftStandardLibraries
    }
}

public struct IOSSigning: Codable, Equatable, Sendable {
    public enum Style: String, Codable, Equatable, Sendable {
        case automatic
        case manual
        /// A local ad-hoc code signature for inspection only; not Apple ad-hoc distribution.
        case localAdHoc
        case unsigned
    }

    public var style: Style
    public var teamIdentifier: String?
    public var identity: String?
    public var provisioningProfile: IOSProvisioningProfileReference?
    public var allowProvisioningUpdates: Bool
    public var allowDeviceRegistration: Bool

    public init(
        style: Style,
        teamIdentifier: String? = nil,
        identity: String? = nil,
        provisioningProfile: IOSProvisioningProfileReference? = nil,
        allowProvisioningUpdates: Bool = false,
        allowDeviceRegistration: Bool = false
    ) {
        self.style = style
        self.teamIdentifier = teamIdentifier
        self.identity = identity
        self.provisioningProfile = provisioningProfile
        self.allowProvisioningUpdates = allowProvisioningUpdates
        self.allowDeviceRegistration = allowDeviceRegistration
    }

    public static func automatic(
        teamIdentifier: String,
        allowProvisioningUpdates: Bool = false,
        allowDeviceRegistration: Bool = false
    ) -> Self {
        .init(
            style: .automatic,
            teamIdentifier: teamIdentifier,
            allowProvisioningUpdates: allowProvisioningUpdates,
            allowDeviceRegistration: allowDeviceRegistration
        )
    }

    public static func manual(
        teamIdentifier: String,
        identity: String,
        provisioningProfile: IOSProvisioningProfileReference
    ) -> Self {
        .init(
            style: .manual,
            teamIdentifier: teamIdentifier,
            identity: identity,
            provisioningProfile: provisioningProfile
        )
    }

    public static var localAdHoc: Self {
        .init(style: .localAdHoc)
    }

    public static var unsigned: Self {
        .init(style: .unsigned)
    }
}

public struct IOSProvisioningProfileReference: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case name
        case uuid
        case path
    }

    public var kind: Kind
    public var value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public static func named(_ name: String) -> Self {
        .init(kind: .name, value: name)
    }

    public static func uuid(_ identifier: String) -> Self {
        .init(kind: .uuid, value: identifier)
    }

    public static func path(_ path: String) -> Self {
        .init(kind: .path, value: path)
    }
}

public struct IOSExportOptions: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Equatable, Sendable {
        case appStoreConnect = "app-store-connect"
        case releaseTesting = "release-testing"
        case enterprise
        case debugging
        case validation
    }

    public enum Destination: String, Codable, Equatable, Sendable {
        case export
        case upload
    }

    public enum SigningStyle: String, Codable, Equatable, Sendable {
        case automatic
        case manual
    }

    public var method: Method
    public var destination: Destination
    public var signingStyle: SigningStyle?
    public var thinning: String?
    public var stripSwiftSymbols: Bool
    public var uploadSymbols: Bool
    public var manageAppVersionAndBuildNumber: Bool

    public init(
        method: Method = .debugging,
        destination: Destination = .export,
        signingStyle: SigningStyle? = nil,
        thinning: String? = nil,
        stripSwiftSymbols: Bool = true,
        uploadSymbols: Bool = true,
        manageAppVersionAndBuildNumber: Bool = false
    ) {
        self.method = method
        self.destination = destination
        self.signingStyle = signingStyle
        self.thinning = thinning
        self.stripSwiftSymbols = stripSwiftSymbols
        self.uploadSymbols = uploadSymbols
        self.manageAppVersionAndBuildNumber = manageAppVersionAndBuildNumber
    }
}

/// A property-list value encoded directly as its natural JSON representation.
///
/// For example, `.dictionary(["Enabled": .bool(true)])` is encoded as
/// `{ "Enabled": true }` instead of an enum discriminator object. The literal
/// conformances also allow the shorter `["Enabled": true]` spelling wherever
/// `PlistValue` provides the contextual type.
public indirect enum PlistValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case real(Double)
    case bool(Bool)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "property lists do not support null values"
            )
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .real(value)
        } else if let value = try? container.decode([PlistValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PlistValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported property-list value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .real(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

extension PlistValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension PlistValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension PlistValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

extension PlistValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension PlistValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: PlistValue...) {
        self = .array(elements)
    }
}

extension PlistValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, PlistValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

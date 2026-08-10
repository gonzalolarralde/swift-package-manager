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

internal import ConstExpr
internal import CompilerPluginSupport
@_spi(ConstExprManifest) import PackageDescription

/// The complete PackageDescription registry is immutable and shared by every
/// manifest evaluation. `ConstExprRegistry` retains its lazily compiled index,
/// so composing this value once also avoids rebuilding the declaration and
/// structural-type indexes for each manifest.
let packageDescriptionRegistry = generatedPackageDescriptionRegistry.appending(
    contentsOf: contextRegistrations + manualRegistrations
)

private enum PackageDescriptionEvaluationContext {
    @TaskLocal static var current: PackageDescriptionConstExprContext?
}

func withPackageDescriptionEvaluationContext<Result>(
    _ context: PackageDescriptionConstExprContext,
    operation: () throws -> Result
) rethrows -> Result {
    try PackageDescriptionEvaluationContext.$current.withValue(
        context,
        operation: operation
    )
}

/// Filled by direct `@ConstExpr(registrationAccess: .package)` peers in
/// PackageDescription. Context registrations are composed with these peers
/// once, while their per-evaluation values remain task-local.
let generatedPackageDescriptionRegistry = #constExprRegistry(
    Package.init(
        name:defaultLocalization:platforms:pkgConfig:providers:products:dependencies:targets:swiftLanguageModes:cLanguageStandard:cxxLanguageStandard:
    ),
    Package.init(
        name:defaultLocalization:platforms:pkgConfig:providers:products:traits:dependencies:targets:swiftLanguageModes:cLanguageStandard:cxxLanguageStandard:
    ),
    Product.library(name:type:targets:),
    Product.executable(name:targets:),
    Product.plugin(name:targets:),
    Product.Library.LibraryType.self,
    Target.target(
        name:dependencies:path:exclude:sources:resources:publicHeadersPath:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:
    ),
    Target.executableTarget(
        name:dependencies:path:exclude:sources:resources:publicHeadersPath:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:
    ),
    Target.testTarget(
        name:dependencies:path:exclude:sources:resources:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:
    ),
    Target.systemLibrary(name:path:pkgConfig:providers:),
    Target.binaryTarget(name:url:checksum:),
    Target.binaryTarget(name:path:),
    Target.plugin(name:capability:dependencies:path:exclude:sources:packageAccess:),
    Target.macro(
        name:dependencies:path:exclude:sources:packageAccess:swiftSettings:linkerSettings:plugins:
    ),
    Target.PluginCapability.buildTool as () -> Target.PluginCapability,
    Target.PluginUsage.plugin(name:),
    Target.PluginUsage.init(stringLiteral:),
    Target.PluginUsage.self,
    Target.Dependency.self,
    Target.Dependency.target(name:condition:),
    Target.Dependency.product(name:package:moduleAliases:condition:),
    Target.Dependency.byName(name:condition:),
    Target.Dependency.init(stringLiteral:),
    Package.Dependency.package(path:),
    Package.Dependency.package(path:traits:),
    Package.Dependency.package(name:path:),
    Package.Dependency.package(name:path:traits:),
    Package.Dependency.package(url:from:),
    Package.Dependency.package(url:from:traits:),
    Package.Dependency.package(url:_:) as (String, Range<Version>) -> Package.Dependency,
    Package.Dependency.package(url:_:traits:)
        as (String, Range<Version>, Set<Package.Dependency.Trait>) -> Package.Dependency,
    Package.Dependency.package(url:_:) as (String, ClosedRange<Version>) -> Package.Dependency,
    Package.Dependency.package(url:_:traits:)
        as (String, ClosedRange<Version>, Set<Package.Dependency.Trait>) -> Package.Dependency,
    Package.Dependency.package(url:branch:),
    Package.Dependency.package(url:branch:traits:),
    Package.Dependency.package(url:revision:),
    Package.Dependency.package(url:revision:traits:),
    Package.Dependency.package(url:exact:),
    Package.Dependency.package(url:exact:traits:),
    Package.Dependency.package(id:from:),
    Package.Dependency.package(id:from:traits:),
    Package.Dependency.package(id:exact:),
    Package.Dependency.package(id:exact:traits:),
    Package.Dependency.package(id:_:) as (String, Range<Version>) -> Package.Dependency,
    Package.Dependency.package(id:_:traits:)
        as (String, Range<Version>, Set<Package.Dependency.Trait>) -> Package.Dependency,
    Package.Dependency.package(id:_:) as (String, ClosedRange<Version>) -> Package.Dependency,
    Package.Dependency.package(id:_:traits:)
        as (String, ClosedRange<Version>, Set<Package.Dependency.Trait>) -> Package.Dependency,
    Package.Dependency.Trait.defaults,
    Package.Dependency.Trait.Condition.when(traits:),
    Package.Dependency.Trait.init(name:condition:),
    Package.Dependency.Trait.init(stringLiteral:),
    Package.Dependency.Trait.trait(name:condition:),
    Version.init(stringLiteral:),
    LanguageTag.init(stringLiteral:),
    CLanguageStandard.self,
    CXXLanguageStandard.self,
    SwiftLanguageMode.self,
    SystemPackageProvider.brew(_:),
    SystemPackageProvider.apt(_:),
    SystemPackageProvider.yum(_:),
    Platform.custom(_:),
    Platform.macOS,
    Platform.macCatalyst,
    Platform.iOS,
    Platform.tvOS,
    Platform.watchOS,
    Platform.visionOS,
    Platform.driverKit,
    Platform.linux,
    Platform.windows,
    Platform.android,
    Platform.wasi,
    Platform.openbsd,
    SupportedPlatform.macOS(_:) as (SupportedPlatform.MacOSVersion) -> SupportedPlatform,
    SupportedPlatform.macOS(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.iOS(_:) as (SupportedPlatform.IOSVersion) -> SupportedPlatform,
    SupportedPlatform.iOS(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.macCatalyst(_:) as (SupportedPlatform.MacCatalystVersion) -> SupportedPlatform,
    SupportedPlatform.macCatalyst(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.tvOS(_:) as (SupportedPlatform.TVOSVersion) -> SupportedPlatform,
    SupportedPlatform.tvOS(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.watchOS(_:) as (SupportedPlatform.WatchOSVersion) -> SupportedPlatform,
    SupportedPlatform.watchOS(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.visionOS(_:) as (SupportedPlatform.VisionOSVersion) -> SupportedPlatform,
    SupportedPlatform.visionOS(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.driverKit(_:) as (SupportedPlatform.DriverKitVersion) -> SupportedPlatform,
    SupportedPlatform.driverKit(_:) as (String) -> SupportedPlatform,
    SupportedPlatform.custom(_:versionString:),
    SupportedPlatform.MacOSVersion.self,
    SupportedPlatform.IOSVersion.self,
    SupportedPlatform.TVOSVersion.self,
    SupportedPlatform.MacCatalystVersion.self,
    SupportedPlatform.WatchOSVersion.self,
    SupportedPlatform.VisionOSVersion.self,
    SupportedPlatform.DriverKitVersion.self,
    Resource.process(_:localization:),
    Resource.copy(_:),
    Resource.embedInCode(_:),
    Resource.Localization.self,
    Trait.default(enabledTraits:),
    Trait.init(name:description:enabledTraits:),
    Trait.init(stringLiteral:),
    Trait.trait(name:description:enabledTraits:),
    BuildConfiguration.debug,
    BuildConfiguration.release,
    BuildSettingCondition.when(platforms:) as ([Platform]) -> BuildSettingCondition,
    BuildSettingCondition.when(platforms:configuration:)
        as ([Platform], BuildConfiguration) -> BuildSettingCondition,
    BuildSettingCondition.when(configuration:),
    CSetting.headerSearchPath(_:_:),
    CSetting.define(_:to:_:),
    CSetting.unsafeFlags(_:_:),
    CXXSetting.headerSearchPath(_:_:),
    CXXSetting.define(_:to:_:),
    CXXSetting.unsafeFlags(_:_:),
    SwiftSetting.define(_:_:),
    SwiftSetting.unsafeFlags(_:_:),
    SwiftSetting.enableUpcomingFeature(_:_:),
    SwiftSetting.enableExperimentalFeature(_:_:),
    SwiftSetting.strictMemorySafety(_:),
    SwiftSetting.defaultIsolation(_:_:),
    SwiftSetting.InteroperabilityMode.self,
    SwiftSetting.interoperabilityMode(_:_:),
    SwiftSetting.swiftLanguageMode(_:_:),
    LinkerSetting.linkedLibrary(_:_:),
    LinkerSetting.linkedFramework(_:_:),
    LinkerSetting.unsafeFlags(_:_:),
    TargetDependencyCondition.when(platforms:) as ([Platform]) -> TargetDependencyCondition?,
    TargetDependencyCondition.when(platforms:traits:),
    TargetDependencyCondition.when(traits:),
    \GitInformation.currentTag,
    \GitInformation.currentCommit,
    \GitInformation.hasUncommittedChanges
)

private let contextRegistrations: [ConstExprRegistration] = [
    ConstExprRegistration(
        moduleName: "PackageDescription",
        name: "packageDirectory",
        kind: .staticProperty,
        ownerType: Context.self,
        resultType: String.self,
        declarationID: "PackageDescription.Context.packageDirectory"
    ) { receiver, arguments in
        guard receiver == nil, arguments.isEmpty else {
            throw ContextAdapterError.invalidInvocation
        }
        guard let context = PackageDescriptionEvaluationContext.current else {
            throw ContextAdapterError.missingEvaluationContext
        }
        return ConstExprValue(context.packageDirectory)
    },
    ConstExprRegistration(
        moduleName: "PackageDescription",
        name: "environment",
        kind: .staticProperty,
        ownerType: Context.self,
        resultType: [String: String].self,
        declarationID: "PackageDescription.Context.environment"
    ) { receiver, arguments in
        guard receiver == nil, arguments.isEmpty else {
            throw ContextAdapterError.invalidInvocation
        }
        guard let context = PackageDescriptionEvaluationContext.current else {
            throw ContextAdapterError.missingEvaluationContext
        }
        return ConstExprValue(context.environment)
    },
    ConstExprRegistration(
        moduleName: "PackageDescription",
        name: "gitInformation",
        kind: .staticProperty,
        ownerType: Context.self,
        resultType: GitInformation?.self,
        declarationID: "PackageDescription.Context.gitInformation"
    ) { receiver, arguments in
        guard receiver == nil, arguments.isEmpty else {
            throw ContextAdapterError.invalidInvocation
        }
        guard let context = PackageDescriptionEvaluationContext.current else {
            throw ContextAdapterError.missingEvaluationContext
        }
        let value = context.gitInformation.map {
            GitInformation(
                currentTag: $0.currentTag,
                currentCommit: $0.currentCommit,
                hasUncommittedChanges: $0.hasUncommittedChanges
            )
        }
        return ConstExprValue(value)
    },
]

private let manualRegistrations: [ConstExprRegistration] = [
    legacyPackageInitializerRegistration,
    versionRangeRegistration(
        name: "upToNextMajor",
        transform: { version in
            version..<Version(version.major + 1, 0, 0)
        }
    ),
    versionRangeRegistration(
        name: "upToNextMinor",
        transform: { version in
            version..<Version(version.major, version.minor + 1, 0)
        }
    ),
    .infixOperator(
        "..<",
        left: Version.self,
        right: Version.self,
        result: Range<Version>.self
    ) { $0..<$1 },
    .infixOperator(
        "...",
        left: Version.self,
        right: Version.self,
        result: ClosedRange<Version>.self
    ) { $0...$1 },
    buildSettingConditionRegistration(
        parameterLabels: ["traits"],
        parameterTypes: [Set<String>.self]
    ),
    buildSettingConditionRegistration(
        parameterLabels: ["platforms", "traits"],
        parameterTypes: [[Platform].self, Set<String>.self]
    ),
    buildSettingConditionRegistration(
        parameterLabels: ["configuration", "traits"],
        parameterTypes: [BuildConfiguration.self, Set<String>.self]
    ),
    buildSettingConditionRegistration(
        parameterLabels: ["platforms", "configuration", "traits"],
        parameterTypes: [[Platform].self, BuildConfiguration.self, Set<String>.self]
    ),
]

/// PackageDescription 5.3 through 5.10 expose the legacy
/// `swiftLanguageVersions:` initializer. Calling that deprecated declaration
/// from this host module would itself produce a warning, so this adapter
/// preserves its source signature while constructing the equivalent current
/// model through `swiftLanguageModes:`.
private let legacyPackageInitializerRegistration = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "Package",
    kind: .initializer,
    ownerType: Package.self,
    parameterLabels: [
        "name",
        "defaultLocalization",
        "platforms",
        "pkgConfig",
        "providers",
        "products",
        "dependencies",
        "targets",
        "swiftLanguageVersions",
        "cLanguageStandard",
        "cxxLanguageStandard",
    ],
    parameterTypes: [
        String.self,
        LanguageTag?.self,
        [SupportedPlatform]?.self,
        String?.self,
        [SystemPackageProvider]?.self,
        [Product].self,
        [Package.Dependency].self,
        [Target].self,
        [SwiftLanguageMode]?.self,
        CLanguageStandard?.self,
        CXXLanguageStandard?.self,
    ],
    parameterTypeDescriptors: [
        .inferred(String.self),
        .inferred(LanguageTag?.self),
        .inferred([SupportedPlatform]?.self),
        .inferred(String?.self),
        .inferred([SystemPackageProvider]?.self),
        .inferred([Product].self),
        .inferred([Package.Dependency].self),
        .inferred([Target].self),
        .optional(.array(.inferred(
            SwiftLanguageMode.self,
            sourceName: "PackageDescription.SwiftVersion"
        ))),
        .inferred(CLanguageStandard?.self),
        .inferred(CXXLanguageStandard?.self),
    ],
    defaultedParameters: Set(1...10),
    resultType: Package.self,
    availability: [
        .init(
            domain: "_PackageDescription",
            introduced: .init(major: 5, minor: 3),
            deprecated: .init(major: 6)
        ),
    ],
    isDisfavoredOverload: true,
    declarationID: "PackageDescription.Package.init(name:defaultLocalization:platforms:pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:cLanguageStandard:cxxLanguageStandard:)"
) { receiver, arguments in
    guard receiver == nil else { throw ContextAdapterError.invalidInvocation }
    return ConstExprValue(Package(
        name: try arguments.require("name", as: String.self),
        defaultLocalization: try arguments.optional(
            "defaultLocalization",
            as: LanguageTag?.self
        ) ?? nil,
        platforms: try arguments.optional("platforms", as: [SupportedPlatform]?.self) ?? nil,
        pkgConfig: try arguments.optional("pkgConfig", as: String?.self) ?? nil,
        providers: try arguments.optional(
            "providers",
            as: [SystemPackageProvider]?.self
        ) ?? nil,
        products: try arguments.optional("products", as: [Product].self) ?? [],
        dependencies: try arguments.optional(
            "dependencies",
            as: [Package.Dependency].self
        ) ?? [],
        targets: try arguments.optional("targets", as: [Target].self) ?? [],
        swiftLanguageModes: try arguments.optional(
            "swiftLanguageVersions",
            as: [SwiftLanguageMode]?.self
        ) ?? nil,
        cLanguageStandard: try arguments.optional(
            "cLanguageStandard",
            as: CLanguageStandard?.self
        ) ?? nil,
        cxxLanguageStandard: try arguments.optional(
            "cxxLanguageStandard",
            as: CXXLanguageStandard?.self
        ) ?? nil
    ))
}

private func versionRangeRegistration(
    name: String,
    transform: @escaping @Sendable (Version) -> Range<Version>
) -> ConstExprRegistration {
    .labelKeyed(
        moduleName: "PackageDescription",
        name: name,
        kind: .staticMethod,
        ownerType: Range<Version>.self,
        parameterLabels: ["from"],
        parameterTypes: [Version.self],
        resultType: Range<Version>.self,
        declarationID: "PackageDescription.Range<Version>.\(name)(from:)"
    ) { receiver, arguments in
        guard receiver == nil else { throw ContextAdapterError.invalidInvocation }
        let version = try arguments.require("from", as: Version.self)
        return ConstExprValue(transform(version))
    }
}

/// The 6.1 condition has three defaulted optionals, while the current API also
/// keeps narrower overloads for source compatibility. Register only omission
/// shapes that contain `traits`; this prevents those shapes from obscuring the
/// exact older overload selected by ordinary platform/configuration calls.
private func buildSettingConditionRegistration(
    parameterLabels: [String?],
    parameterTypes: [Any.Type]
) -> ConstExprRegistration {
    .labelKeyed(
        moduleName: "PackageDescription",
        name: "when",
        kind: .staticMethod,
        ownerType: BuildSettingCondition.self,
        parameterLabels: parameterLabels,
        parameterTypes: parameterTypes,
        resultType: BuildSettingCondition.self,
        availability: [
            .init(
                domain: "_PackageDescription",
                introduced: .init(major: 6, minor: 1)
            ),
        ],
        declarationID: "PackageDescription.BuildSettingCondition.when(\(parameterLabels.map { ($0 ?? "_") + ":" }.joined()))"
    ) { receiver, arguments in
        guard receiver == nil else { throw ContextAdapterError.invalidInvocation }
        let labels = Set(parameterLabels.compactMap { $0 })
        let platforms = labels.contains("platforms")
            ? try arguments.require("platforms", as: [Platform].self)
            : nil
        let configuration = labels.contains("configuration")
            ? try arguments.require("configuration", as: BuildConfiguration.self)
            : nil
        let traits = labels.contains("traits")
            ? try arguments.require("traits", as: Set<String>.self)
            : nil
        return ConstExprValue(BuildSettingCondition.when(
            platforms: platforms,
            configuration: configuration,
            traits: traits
        ))
    }
}

private enum ContextAdapterError: Error {
    case invalidInvocation
    case missingEvaluationContext
}

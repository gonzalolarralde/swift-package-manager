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
    Product.self,
    Product.Library.LibraryType.self,
    Target.self,
    Target.macro(
        name:dependencies:path:exclude:sources:packageAccess:swiftSettings:linkerSettings:plugins:
    ),
    Target.PluginCapability.self,
    Target.PluginCapability.buildTool as () -> Target.PluginCapability,
    PluginCommandIntent.self,
    PluginPermission.self,
    PluginNetworkPermissionScope.self,
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
    Package.Dependency.Trait.self,
    Package.Dependency.Trait.Condition.when(traits:),
    Version.init(stringLiteral:),
    LanguageTag.init(stringLiteral:),
    CLanguageStandard.self,
    CXXLanguageStandard.self,
    SwiftLanguageMode.self,
    SystemPackageProvider.self,
    Platform.self,
    SupportedPlatform.self,
    SupportedPlatform.MacOSVersion.self,
    SupportedPlatform.IOSVersion.self,
    SupportedPlatform.TVOSVersion.self,
    SupportedPlatform.MacCatalystVersion.self,
    SupportedPlatform.WatchOSVersion.self,
    SupportedPlatform.VisionOSVersion.self,
    SupportedPlatform.DriverKitVersion.self,
    Resource.self,
    Resource.Localization.self,
    Trait.self,
    BuildConfiguration.self,
    BuildSettingCondition.self,
    CSetting.self,
    CXXSetting.self,
    SwiftSetting.self,
    SwiftSetting.InteroperabilityMode.self,
    LinkerSetting.self,
    TargetDependencyCondition.self,
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

private let manualRegistrations: [ConstExprRegistration] =
    legacyPackageRegistrations
    + legacyTargetRegistrations
    + legacyDependencyRegistrations
    + rawRepresentableRegistrations
    + [
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

private let rawRepresentableRegistrations: [ConstExprRegistration] = [
    stringRawRepresentableInitializer(CLanguageStandard.self),
    stringRawRepresentableInitializer(CXXLanguageStandard.self),
]

private func stringRawRepresentableInitializer<Value>(
    _ type: Value.Type
) -> ConstExprRegistration where Value: RawRepresentable, Value.RawValue == String {
    let reflectedName = String(reflecting: type)
    let sourceName = reflectedName.split(separator: ".").last.map(String.init)
        ?? reflectedName
    return ConstExprRegistration(
        moduleName: "PackageDescription",
        name: sourceName,
        kind: .initializer,
        ownerType: type,
        parameterLabels: ["rawValue"],
        parameterTypes: [String.self],
        resultType: Value?.self,
        declarationID: "PackageDescription.\(sourceName).init(rawValue:)"
    ) { receiver, arguments in
        guard receiver == nil,
              arguments.count == 1,
              let rawValue = arguments[0]
        else {
            throw ContextAdapterError.invalidInvocation
        }
        return ConstExprValue(Value(rawValue: try rawValue.require(String.self)))
    }
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

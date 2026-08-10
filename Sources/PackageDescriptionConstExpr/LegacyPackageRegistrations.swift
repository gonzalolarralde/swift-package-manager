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
@_spi(ConstExprManifest) import PackageDescription

let legacyPackageRegistrations: [ConstExprRegistration] = [
    packageInitializerFiveZero,
    packageInitializerFiveThree,
]

/// PackageDescription 5.0 through 5.2 use a Package initializer without
/// `defaultLocalization`. The host constructs its equivalent current model so
/// the unavailable historical declaration is never referenced.
private let packageInitializerFiveZero = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "Package",
    kind: .initializer,
    ownerType: Package.self,
    parameterLabels: [
        "name",
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
        .inferred([SupportedPlatform]?.self),
        .inferred(String?.self),
        .inferred([SystemPackageProvider]?.self),
        .inferred([Product].self),
        .inferred([Package.Dependency].self),
        .inferred([Target].self),
        swiftVersionArrayDescriptor,
        .inferred(CLanguageStandard?.self),
        .inferred(CXXLanguageStandard?.self),
    ],
    defaultedParameters: Set(1...9),
    resultType: Package.self,
    availability: [
        .init(
            domain: "_PackageDescription",
            introduced: .init(major: 5),
            obsoleted: .init(major: 5, minor: 3)
        ),
    ],
    declarationID: "PackageDescription.Package.init@5.0"
) { receiver, arguments in
    guard receiver == nil else { throw LegacyPackageAdapterError.invalidInvocation }
    return ConstExprValue(Package(
        name: try arguments.require("name", as: String.self),
        platforms: try arguments.optional("platforms", as: [SupportedPlatform]?.self) ?? nil,
        pkgConfig: try arguments.optional("pkgConfig", as: String?.self) ?? nil,
        providers: try arguments.optional("providers", as: [SystemPackageProvider]?.self) ?? nil,
        products: try arguments.optional("products", as: [Product].self) ?? [],
        dependencies: try arguments.optional("dependencies", as: [Package.Dependency].self) ?? [],
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

/// PackageDescription 5.3 through 5.10 expose the legacy
/// `swiftLanguageVersions:` initializer. Calling that deprecated declaration
/// from this host module would itself produce a warning, so this adapter
/// preserves its source signature while constructing the equivalent current
/// model through `swiftLanguageModes:`.
private let packageInitializerFiveThree = ConstExprRegistration.labelKeyed(
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
        swiftVersionArrayDescriptor,
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
    declarationID: "PackageDescription.Package.init@5.3"
) { receiver, arguments in
    guard receiver == nil else { throw LegacyPackageAdapterError.invalidInvocation }
    return ConstExprValue(Package(
        name: try arguments.require("name", as: String.self),
        defaultLocalization: try arguments.optional(
            "defaultLocalization",
            as: LanguageTag?.self
        ) ?? nil,
        platforms: try arguments.optional("platforms", as: [SupportedPlatform]?.self) ?? nil,
        pkgConfig: try arguments.optional("pkgConfig", as: String?.self) ?? nil,
        providers: try arguments.optional("providers", as: [SystemPackageProvider]?.self) ?? nil,
        products: try arguments.optional("products", as: [Product].self) ?? [],
        dependencies: try arguments.optional("dependencies", as: [Package.Dependency].self) ?? [],
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

private let swiftVersionArrayDescriptor = ConstExprStaticTypeDescriptor.optional(
    .array(.inferred(
        SwiftLanguageMode.self,
        sourceName: "PackageDescription.SwiftVersion"
    ))
)

private enum LegacyPackageAdapterError: Error {
    case invalidInvocation
}

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

let legacyDependencyRegistrations: [ConstExprRegistration] =
    legacyRequirementRegistrations
    + legacyDependencyFactoryRegistrations
    + legacyTargetDependencyRegistrations
    + [legacyBuildSettingCondition, legacyTargetDependencyCondition]

private enum LegacyRequirement: Sendable {
    case exact(Version)
    case range(Range<Version>)
    case revision(String)
    case branch(String)
}

private let legacyRequirementSourceName =
    "PackageDescription.Package.Dependency.Requirement"

private let legacyRequirementDescriptor = ConstExprStaticTypeDescriptor.inferred(
    LegacyRequirement.self,
    sourceName: legacyRequirementSourceName
)

private let legacyRequirementAvailability: [ConstExprAvailability] = [
    .init(
        domain: "_PackageDescription",
        deprecated: .init(major: 5, minor: 6)
    ),
]

private let legacyRequirementRegistrations: [ConstExprRegistration] = [
    legacyRequirementFactory(
        name: "exact",
        label: nil,
        parameterType: Version.self,
        declarationID: "PackageDescription.Package.Dependency.Requirement.exact"
    ) { value in
        .exact(try value.require(Version.self))
    },
    legacyRequirementFactory(
        name: "revision",
        label: nil,
        parameterType: String.self,
        declarationID: "PackageDescription.Package.Dependency.Requirement.revision"
    ) { value in
        .revision(try value.require(String.self))
    },
    legacyRequirementFactory(
        name: "branch",
        label: nil,
        parameterType: String.self,
        declarationID: "PackageDescription.Package.Dependency.Requirement.branch"
    ) { value in
        .branch(try value.require(String.self))
    },
]

private func legacyRequirementFactory(
    name: String,
    label: String?,
    parameterType: Any.Type,
    declarationID: String,
    transform: @escaping @Sendable (ConstExprValue) throws -> LegacyRequirement
) -> ConstExprRegistration {
    ConstExprRegistration(
        moduleName: "PackageDescription",
        name: name,
        kind: .staticMethod,
        ownerType: LegacyRequirement.self,
        ownerName: legacyRequirementSourceName,
        parameterLabels: [label],
        parameterTypes: [parameterType],
        resultType: LegacyRequirement.self,
        resultTypeDescriptor: legacyRequirementDescriptor,
        availability: legacyRequirementAvailability,
        isDisfavoredOverload: false,
        declarationID: declarationID
    ) { receiver, arguments in
        guard receiver == nil, arguments.count == 1, let value = arguments[0] else {
            throw LegacyDependencyAdapterError.invalidInvocation
        }
        return ConstExprValue(try transform(value))
    }
}

private let legacyDependencyFactoryRegistrations: [ConstExprRegistration] = [
    legacyRequirementPackageFactory(named: false),
    legacyRequirementPackageFactory(named: true),
    namedDependencyFactory(
        labels: ["name", "url", "from"],
        valueType: Version.self,
        introduced: (5, 2),
        declarationID: "PackageDescription.Package.Dependency.package(name:url:from:)"
    ) { name, url, value in
        let version = try value.require(Version.self)
        return ._constExprPackage(
            name: name,
            url: url,
            range: version..<Version(version.major + 1, 0, 0)
        )
    },
    namedDependencyFactory(
        labels: ["name", "url", nil],
        valueType: Range<Version>.self,
        introduced: (5, 2),
        declarationID: "PackageDescription.Package.Dependency.package(name:url:range:)"
    ) { name, url, value in
        ._constExprPackage(
            name: name,
            url: url,
            range: try value.require(Range<Version>.self)
        )
    },
    namedDependencyFactory(
        labels: ["name", "url", nil],
        valueType: ClosedRange<Version>.self,
        introduced: (5, 2),
        declarationID: "PackageDescription.Package.Dependency.package(name:url:closedRange:)"
    ) { name, url, value in
        let range = try value.require(ClosedRange<Version>.self)
        return ._constExprPackage(
            name: name,
            url: url,
            range: range.lowerBound..<nextPatch(after: range.upperBound)
        )
    },
    namedDependencyFactory(
        labels: ["name", "url", "branch"],
        valueType: String.self,
        introduced: (5, 5),
        declarationID: "PackageDescription.Package.Dependency.package(name:url:branch:)"
    ) { name, url, value in
        ._constExprPackage(name: name, url: url, branch: try value.require(String.self))
    },
    namedDependencyFactory(
        labels: ["name", "url", "revision"],
        valueType: String.self,
        introduced: (5, 5),
        declarationID: "PackageDescription.Package.Dependency.package(name:url:revision:)"
    ) { name, url, value in
        ._constExprPackage(name: name, url: url, revision: try value.require(String.self))
    },
]

private func legacyRequirementPackageFactory(named: Bool) -> ConstExprRegistration {
    let labels: [String?] = named ? ["name", "url", nil] : ["url", nil]
    let types: [Any.Type] = named
        ? [String?.self, String.self, LegacyRequirement.self]
        : [String.self, LegacyRequirement.self]
    let descriptors: [ConstExprStaticTypeDescriptor] = named
        ? [.inferred(String?.self), .inferred(String.self), legacyRequirementDescriptor]
        : [.inferred(String.self), legacyRequirementDescriptor]
    return ConstExprRegistration(
        moduleName: "PackageDescription",
        name: "package",
        kind: .staticMethod,
        ownerType: Package.Dependency.self,
        parameterLabels: labels,
        parameterTypes: types,
        parameterTypeDescriptors: descriptors,
        resultType: Package.Dependency.self,
        availability: [
            .init(
                domain: "_PackageDescription",
                introduced: named ? .init(major: 5, minor: 2) : nil,
                deprecated: .init(major: 5, minor: 6)
            ),
        ],
        declarationID: named
            ? "PackageDescription.Package.Dependency.package(name:url:requirement:)"
            : "PackageDescription.Package.Dependency.package(url:requirement:)"
    ) { receiver, arguments in
        guard receiver == nil,
              arguments.count == (named ? 3 : 2),
              let urlValue = arguments[named ? 1 : 0],
              let requirementValue = arguments[named ? 2 : 1]
        else {
            throw LegacyDependencyAdapterError.invalidInvocation
        }
        let name: String?
        if named {
            guard let nameValue = arguments[0] else {
                throw LegacyDependencyAdapterError.invalidInvocation
            }
            name = try nameValue.require(String?.self)
        } else {
            name = nil
        }
        return ConstExprValue(try makeDependency(
            name: name,
            url: urlValue.require(String.self),
            requirement: requirementValue.require(LegacyRequirement.self)
        ))
    }
}

private func namedDependencyFactory(
    labels: [String?],
    valueType: Any.Type,
    introduced: (Int, Int),
    declarationID: String,
    transform: @escaping @Sendable (String, String, ConstExprValue) throws -> Package.Dependency
) -> ConstExprRegistration {
    ConstExprRegistration(
        moduleName: "PackageDescription",
        name: "package",
        kind: .staticMethod,
        ownerType: Package.Dependency.self,
        parameterLabels: labels,
        parameterTypes: [String.self, String.self, valueType],
        resultType: Package.Dependency.self,
        availability: [
            .init(
                domain: "_PackageDescription",
                introduced: .init(major: introduced.0, minor: introduced.1),
                deprecated: .init(major: 5, minor: 6)
            ),
        ],
        declarationID: declarationID
    ) { receiver, arguments in
        guard receiver == nil,
              arguments.count == 3,
              let name = arguments[0],
              let url = arguments[1],
              let value = arguments[2]
        else {
            throw LegacyDependencyAdapterError.invalidInvocation
        }
        return ConstExprValue(try transform(
            name.require(String.self),
            url.require(String.self),
            value
        ))
    }
}

private let legacyTargetDependencyRegistrations: [ConstExprRegistration] = [
    targetDependencyFactory(name: "target", labels: ["name"], introduced: nil, obsoleted: (5, 3)) {
        .targetItem(name: $0[0], condition: nil)
    },
    targetDependencyFactory(name: "byName", labels: ["name"], introduced: nil, obsoleted: (5, 3)) {
        .byNameItem(name: $0[0], condition: nil)
    },
    targetDependencyFactory(
        name: "product",
        labels: ["name", "package"],
        introduced: nil,
        obsoleted: (5, 2),
        packageIsOptional: true
    ),
    targetDependencyFactory(
        name: "product",
        labels: ["name", "package"],
        introduced: (5, 2),
        obsoleted: (5, 3)
    ),
    legacyConditionalProductDependency,
]

private func targetDependencyFactory(
    name: String,
    labels: [String?],
    introduced: (Int, Int)?,
    obsoleted: (Int, Int),
    packageIsOptional: Bool = false,
    transform: (@Sendable ([String]) -> Target.Dependency)? = nil
) -> ConstExprRegistration {
    let types: [Any.Type] = labels.indices.map { index in
        index == 1 && packageIsOptional ? String?.self : String.self
    }
    return .labelKeyed(
        moduleName: "PackageDescription",
        name: name,
        kind: .staticMethod,
        ownerType: Target.Dependency.self,
        parameterLabels: labels,
        parameterTypes: types,
        defaultedParameters: packageIsOptional ? [1] : [],
        resultType: Target.Dependency.self,
        availability: [
            .init(
                domain: "_PackageDescription",
                introduced: introduced.map { .init(major: $0.0, minor: $0.1) },
                obsoleted: .init(major: obsoleted.0, minor: obsoleted.1)
            ),
        ],
        declarationID: "PackageDescription.Target.Dependency.\(name)@legacy-\(obsoleted.0).\(obsoleted.1)"
    ) { receiver, arguments in
        guard receiver == nil else { throw LegacyDependencyAdapterError.invalidInvocation }
        if let transform {
            return ConstExprValue(transform([
                try arguments.require("name", as: String.self),
            ]))
        }
        return ConstExprValue(Target.Dependency.productItem(
            name: try arguments.require("name", as: String.self),
            package: packageIsOptional
                ? try arguments.optional("package", as: String?.self) ?? nil
                : try arguments.require("package", as: String.self),
            moduleAliases: nil,
            condition: nil
        ))
    }
}

private let legacyConditionalProductDependency = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "product",
    kind: .staticMethod,
    ownerType: Target.Dependency.self,
    parameterLabels: ["name", "package", "condition"],
    parameterTypes: [String.self, String.self, TargetDependencyCondition?.self],
    defaultedParameters: [2],
    resultType: Target.Dependency.self,
    availability: [
        .init(
            domain: "_PackageDescription",
            introduced: .init(major: 5, minor: 3),
            obsoleted: .init(major: 5, minor: 7)
        ),
    ],
    isDisfavoredOverload: true,
    declarationID: "PackageDescription.Target.Dependency.product@5.3"
) { receiver, arguments in
    guard receiver == nil else { throw LegacyDependencyAdapterError.invalidInvocation }
    return ConstExprValue(Target.Dependency.productItem(
        name: try arguments.require("name", as: String.self),
        package: try arguments.require("package", as: String.self),
        moduleAliases: nil,
        condition: try arguments.optional("condition", as: TargetDependencyCondition?.self) ?? nil
    ))
}

private let legacyBuildSettingCondition = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "when",
    kind: .staticMethod,
    ownerType: BuildSettingCondition.self,
    parameterLabels: ["platforms", "configuration"],
    parameterTypes: [[Platform]?.self, BuildConfiguration?.self],
    defaultedParameters: [0, 1],
    resultType: BuildSettingCondition.self,
    availability: [
        .init(domain: "_PackageDescription", deprecated: .init(major: 5, minor: 7)),
    ],
    declarationID: "PackageDescription.BuildSettingCondition.when@legacy"
) { receiver, arguments in
    guard receiver == nil else { throw LegacyDependencyAdapterError.invalidInvocation }
    let platforms = try arguments.optional("platforms", as: [Platform]?.self) ?? nil
    let configuration = try arguments.optional(
        "configuration",
        as: BuildConfiguration?.self
    ) ?? nil
    switch (platforms, configuration) {
    case let (.some(platforms), .some(configuration)):
        return ConstExprValue(BuildSettingCondition.when(
            platforms: platforms,
            configuration: configuration
        ))
    case let (.some(platforms), .none):
        return ConstExprValue(BuildSettingCondition.when(platforms: platforms))
    case let (.none, .some(configuration)):
        return ConstExprValue(BuildSettingCondition.when(configuration: configuration))
    case (.none, .none):
        throw LegacyDependencyAdapterError.invalidInvocation
    }
}

private let legacyTargetDependencyCondition = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "when",
    kind: .staticMethod,
    ownerType: TargetDependencyCondition.self,
    parameterLabels: ["platforms"],
    parameterTypes: [[Platform]?.self],
    defaultedParameters: [0],
    resultType: TargetDependencyCondition.self,
    availability: [
        .init(domain: "_PackageDescription", obsoleted: .init(major: 5, minor: 7)),
    ],
    isDisfavoredOverload: true,
    declarationID: "PackageDescription.TargetDependencyCondition.when@legacy"
) { receiver, arguments in
    guard receiver == nil,
          let platforms = try arguments.optional("platforms", as: [Platform]?.self) ?? nil
    else {
        throw LegacyDependencyAdapterError.invalidInvocation
    }
    return ConstExprValue(TargetDependencyCondition._constExprLegacyWhen(platforms: platforms))
}

private func makeDependency(
    name: String?,
    url: String,
    requirement: LegacyRequirement
) -> Package.Dependency {
    switch requirement {
    case .exact(let version):
        ._constExprPackage(name: name, url: url, exact: version)
    case .range(let range):
        ._constExprPackage(name: name, url: url, range: range)
    case .revision(let revision):
        ._constExprPackage(name: name, url: url, revision: revision)
    case .branch(let branch):
        ._constExprPackage(name: name, url: url, branch: branch)
    }
}

private func nextPatch(after version: Version) -> Version {
    Version(
        version.major,
        version.minor,
        version.patch + 1,
        prereleaseIdentifiers: version.prereleaseIdentifiers,
        buildMetadataIdentifiers: version.buildMetadataIdentifiers
    )
}

private enum LegacyDependencyAdapterError: Error {
    case invalidInvocation
}

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

let legacyTargetRegistrations: [ConstExprRegistration] = [
    targetFactory(
        .target,
        introduced: (5, 0),
        obsoleted: (5, 3),
        includesResources: false,
        includesPlugins: false
    ),
    targetFactory(
        .target,
        introduced: (5, 3),
        obsoleted: (5, 5),
        includesResources: true,
        includesPlugins: false
    ),
    targetFactory(
        .target,
        introduced: (5, 5),
        obsoleted: (5, 9),
        includesResources: true,
        includesPlugins: true
    ),
    targetFactory(
        .executable,
        introduced: (5, 4),
        obsoleted: (5, 5),
        includesResources: true,
        includesPlugins: false
    ),
    targetFactory(
        .executable,
        introduced: (5, 5),
        obsoleted: (5, 9),
        includesResources: true,
        includesPlugins: true
    ),
    targetFactory(
        .test,
        introduced: (5, 0),
        obsoleted: (5, 3),
        includesResources: false,
        includesPlugins: false
    ),
    targetFactory(
        .test,
        introduced: (5, 3),
        obsoleted: (5, 5),
        includesResources: true,
        includesPlugins: false
    ),
    targetFactory(
        .test,
        introduced: (5, 5),
        obsoleted: (5, 9),
        includesResources: true,
        includesPlugins: true
    ),
    legacyPluginTargetFactory,
]

private enum LegacyTargetFactoryKind: Sendable {
    case target
    case executable
    case test

    var sourceName: String {
        switch self {
        case .target: "target"
        case .executable: "executableTarget"
        case .test: "testTarget"
        }
    }

    var targetType: Target.TargetType {
        switch self {
        case .target: .regular
        case .executable: .executable
        case .test: .test
        }
    }

    var includesPublicHeaders: Bool {
        self != .test
    }
}

private func targetFactory(
    _ kind: LegacyTargetFactoryKind,
    introduced: (Int, Int),
    obsoleted: (Int, Int),
    includesResources: Bool,
    includesPlugins: Bool
) -> ConstExprRegistration {
    var labels: [String?] = ["name", "dependencies", "path", "exclude", "sources"]
    var types: [Any.Type] = [
        String.self,
        [Target.Dependency].self,
        String?.self,
        [String].self,
        [String]?.self,
    ]
    if includesResources {
        labels.append("resources")
        types.append([Resource]?.self)
    }
    if kind.includesPublicHeaders {
        labels.append("publicHeadersPath")
        types.append(String?.self)
    }
    labels += ["cSettings", "cxxSettings", "swiftSettings", "linkerSettings"]
    types += [
        [CSetting]?.self,
        [CXXSetting]?.self,
        [SwiftSetting]?.self,
        [LinkerSetting]?.self,
    ]
    if includesPlugins {
        labels.append("plugins")
        types.append([Target.PluginUsage]?.self)
    }

    return .labelKeyed(
        moduleName: "PackageDescription",
        name: kind.sourceName,
        kind: .staticMethod,
        ownerType: Target.self,
        parameterLabels: labels,
        parameterTypes: types,
        defaultedParameters: Set(types.indices.dropFirst()),
        resultType: Target.self,
        availability: [
            .init(
                domain: "_PackageDescription",
                introduced: .init(major: introduced.0, minor: introduced.1),
                obsoleted: .init(major: obsoleted.0, minor: obsoleted.1)
            ),
        ],
        declarationID: "PackageDescription.Target.\(kind.sourceName)@\(introduced.0).\(introduced.1)"
    ) { receiver, arguments in
        guard receiver == nil else { throw LegacyTargetAdapterError.invalidInvocation }
        return ConstExprValue(Target._constExprTarget(
            name: try arguments.require("name", as: String.self),
            dependencies: try arguments.optional(
                "dependencies",
                as: [Target.Dependency].self
            ) ?? [],
            path: try arguments.optional("path", as: String?.self) ?? nil,
            exclude: try arguments.optional("exclude", as: [String].self) ?? [],
            sources: try arguments.optional("sources", as: [String]?.self) ?? nil,
            resources: includesResources
                ? try arguments.optional("resources", as: [Resource]?.self) ?? nil
                : nil,
            publicHeadersPath: kind.includesPublicHeaders
                ? try arguments.optional("publicHeadersPath", as: String?.self) ?? nil
                : nil,
            type: kind.targetType,
            cSettings: try arguments.optional("cSettings", as: [CSetting]?.self) ?? nil,
            cxxSettings: try arguments.optional("cxxSettings", as: [CXXSetting]?.self) ?? nil,
            swiftSettings: try arguments.optional("swiftSettings", as: [SwiftSetting]?.self) ?? nil,
            linkerSettings: try arguments.optional("linkerSettings", as: [LinkerSetting]?.self) ?? nil,
            plugins: includesPlugins
                ? try arguments.optional("plugins", as: [Target.PluginUsage]?.self) ?? nil
                : nil
        ))
    }
}

private let legacyPluginTargetFactory = ConstExprRegistration.labelKeyed(
    moduleName: "PackageDescription",
    name: "plugin",
    kind: .staticMethod,
    ownerType: Target.self,
    parameterLabels: ["name", "capability", "dependencies", "path", "exclude", "sources"],
    parameterTypes: [
        String.self,
        Target.PluginCapability.self,
        [Target.Dependency].self,
        String?.self,
        [String].self,
        [String]?.self,
    ],
    defaultedParameters: Set(2...5),
    resultType: Target.self,
    availability: [
        .init(
            domain: "_PackageDescription",
            introduced: .init(major: 5, minor: 5),
            obsoleted: .init(major: 5, minor: 9)
        ),
    ],
    declarationID: "PackageDescription.Target.plugin@5.5"
) { receiver, arguments in
    guard receiver == nil else { throw LegacyTargetAdapterError.invalidInvocation }
    return ConstExprValue(Target._constExprPluginTarget(
        name: try arguments.require("name", as: String.self),
        capability: try arguments.require("capability", as: Target.PluginCapability.self),
        dependencies: try arguments.optional("dependencies", as: [Target.Dependency].self) ?? [],
        path: try arguments.optional("path", as: String?.self) ?? nil,
        exclude: try arguments.optional("exclude", as: [String].self) ?? [],
        sources: try arguments.optional("sources", as: [String]?.self) ?? nil
    ))
}

private enum LegacyTargetAdapterError: Error {
    case invalidInvocation
}

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

#if SWIFTPM_CONSTEXPR_MANIFESTS

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Foundation
#else
import Foundation
#endif

final class ConstExprManifestSession: @unchecked Sendable {
    private let lock = NSLock()
    private var initializerCount = 0

    var packageInitializerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return initializerCount
    }

    func recordPackageInitializer() {
        lock.lock()
        defer { lock.unlock() }
        initializerCount += 1
    }
}

enum ConstExprManifestSessionScope {
    @TaskLocal static var current: ConstExprManifestSession?
}

private let constExprManifestSessionLock = NSRecursiveLock()

extension Package {
    /// Serializes this value through the exact versioned wire format consumed
    /// by SwiftPM's existing manifest JSON parser.
    @_spi(ConstExprManifest)
    public func _constExprManifestJSON() -> String {
        constExprManifestToJSON(self)
    }

    /// Isolates PackageDescription's process-global compatibility diagnostics
    /// and records how many Package roots speculative evaluation constructed.
    @_spi(ConstExprManifest)
    public static func _withConstExprManifestEvaluation<Result>(
        _ operation: () throws -> Result
    ) rethrows -> (result: Result, packageInitializerCount: Int) {
        constExprManifestSessionLock.lock()
        defer { constExprManifestSessionLock.unlock() }

        let previousErrors = errors
        let session = ConstExprManifestSession()
        errors = []
        defer { errors = previousErrors }

        return try ConstExprManifestSessionScope.$current.withValue(session) {
            (try operation(), session.packageInitializerCount)
        }
    }
}

extension Target {
    /// Constructs the current target model for a historical factory whose
    /// declaration is unavailable to the host-side adapter at tools version
    /// 999. The adapter supplies the exact defaults for its source API era.
    @_spi(ConstExprManifest)
    public static func _constExprTarget(
        name: String,
        dependencies: [Dependency],
        path: String?,
        exclude: [String],
        sources: [String]?,
        resources: [Resource]?,
        publicHeadersPath: String?,
        type: TargetType,
        cSettings: [CSetting]?,
        cxxSettings: [CXXSetting]?,
        swiftSettings: [SwiftSetting]?,
        linkerSettings: [LinkerSetting]?,
        plugins: [PluginUsage]?
    ) -> Target {
        Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            resources: resources,
            publicHeadersPath: publicHeadersPath,
            type: type,
            packageAccess: false,
            cSettings: cSettings,
            cxxSettings: cxxSettings,
            swiftSettings: swiftSettings,
            linkerSettings: linkerSettings,
            plugins: plugins
        )
    }

    @_spi(ConstExprManifest)
    public static func _constExprPluginTarget(
        name: String,
        capability: PluginCapability,
        dependencies: [Dependency],
        path: String?,
        exclude: [String],
        sources: [String]?
    ) -> Target {
        Target(
            name: name,
            dependencies: dependencies,
            path: path,
            exclude: exclude,
            sources: sources,
            publicHeadersPath: nil,
            type: .plugin,
            packageAccess: false,
            pluginCapability: capability
        )
    }
}

extension Package.Dependency {
    @_spi(ConstExprManifest)
    public static func _constExprPackage(
        name: String?,
        url: String,
        range: Range<Version>
    ) -> Package.Dependency {
        .init(name: name, location: url, requirement: .range(range), traits: nil)
    }

    @_spi(ConstExprManifest)
    public static func _constExprPackage(
        name: String?,
        url: String,
        exact version: Version
    ) -> Package.Dependency {
        .init(name: name, location: url, requirement: .exact(version), traits: nil)
    }

    @_spi(ConstExprManifest)
    public static func _constExprPackage(
        name: String?,
        url: String,
        branch: String
    ) -> Package.Dependency {
        .init(name: name, location: url, requirement: .branch(branch), traits: nil)
    }

    @_spi(ConstExprManifest)
    public static func _constExprPackage(
        name: String?,
        url: String,
        revision: String
    ) -> Package.Dependency {
        .init(name: name, location: url, requirement: .revision(revision), traits: nil)
    }
}

#endif

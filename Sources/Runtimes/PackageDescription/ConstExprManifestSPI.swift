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

#endif

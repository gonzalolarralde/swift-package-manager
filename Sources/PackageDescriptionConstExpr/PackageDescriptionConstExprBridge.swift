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
import SwiftSyntax

package struct PackageDescriptionConstExprContext: Sendable {
    package struct Version: Sendable {
        package let major: Int
        package let minor: Int
        package let patch: Int

        package init(major: Int, minor: Int, patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }
    }

    package struct GitInformation: Sendable {
        package let currentTag: String?
        package let currentCommit: String
        package let hasUncommittedChanges: Bool

        package init(currentTag: String?, currentCommit: String, hasUncommittedChanges: Bool) {
            self.currentTag = currentTag
            self.currentCommit = currentCommit
            self.hasUncommittedChanges = hasUncommittedChanges
        }
    }

    package let packageDirectory: String
    package let environment: [String: String]
    package let gitInformation: GitInformation?
    package let packageDescriptionVersion: Version
    package let enableSignposts: Bool

    package init(
        packageDirectory: String,
        environment: [String: String],
        gitInformation: GitInformation? = nil,
        packageDescriptionVersion: Version,
        enableSignposts: Bool = false
    ) {
        self.packageDirectory = packageDirectory
        self.environment = environment
        self.gitInformation = gitInformation
        self.packageDescriptionVersion = packageDescriptionVersion
        self.enableSignposts = enableSignposts
    }
}

package struct PackageDescriptionConstExprFallback: Sendable, Equatable {
    package let reasonCode: String
    package let detail: String
    package let line: Int?
    package let column: Int?

    package init(
        reasonCode: String,
        detail: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.reasonCode = reasonCode
        self.detail = detail
        self.line = line
        self.column = column
    }
}

package enum PackageDescriptionConstExprEvaluation: Sendable, Equatable {
    case success(manifestJSON: String)
    case fallback(PackageDescriptionConstExprFallback)
}

package enum PackageDescriptionConstExprBridge {
    package static func evaluateManifest(
        sourceFile: SourceFileSyntax,
        fileName: String = "<memory>",
        context: PackageDescriptionConstExprContext
    ) -> PackageDescriptionConstExprEvaluation {
        let version = context.packageDescriptionVersion
        let runner = ConstExprRunner(
            registry: packageDescriptionRegistry,
            options: .init(
                enableSignposts: context.enableSignposts,
                availabilityContext: .init(versions: [
                    "_PackageDescription": .init(
                        major: version.major,
                        minor: version.minor,
                        patch: version.patch
                    ),
                ])
            )
        )
        let session = Package._withConstExprManifestEvaluation {
            let result = withPackageDescriptionEvaluationContext(context) {
                runner.evaluate(
                    sourceFile: sourceFile,
                    binding: "package",
                    as: Package.self,
                    policy: .certifying,
                    fileName: fileName
                )
            }
            return result.map { $0._constExprManifestJSON() }
        }

        switch session.result {
        case .success(let manifestJSON):
            guard session.packageInitializerCount == 1 else {
                return .fallback(.init(
                    reasonCode: "package-initializer-count",
                    detail: "expected exactly one Package initializer, observed \(session.packageInitializerCount)"
                ))
            }
            return .success(manifestJSON: manifestJSON)
        case .fallback(let fallback):
            let diagnostics = fallback.diagnostics.map {
                "\($0.code): \($0.message)"
            }.joined(separator: "; ")
            return .fallback(.init(
                reasonCode: fallback.reason.rawValue,
                detail: diagnostics.isEmpty
                    ? fallback.message
                    : "\(fallback.message) [\(diagnostics)]",
                line: fallback.location?.line,
                column: fallback.location?.column
            ))
        }
    }
}

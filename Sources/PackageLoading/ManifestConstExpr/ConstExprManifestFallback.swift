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

/// A stable, non-diagnostic explanation for declining the manifest fast path.
/// Normal SwiftPM operation catches this value silently and compiles the
/// untouched manifest so the Swift compiler remains the diagnostic authority.
package struct ConstExprManifestFallback: Error, Sendable, Codable, Equatable {
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

extension ConstExprManifestFallback: CustomStringConvertible {
    package var description: String {
        let location = if let line, let column { " at \(line):\(column)" } else { "" }
        return "ConstExpr manifest fast path declined [\(reasonCode)]\(location): \(detail)"
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if SWIFTPM_CONSTEXPR_MANIFESTS
internal import ConstExpr
#endif

extension Package.Dependency {
    /// An enabled trait of a dependency.
    @available(_PackageDescription, introduced: 6.1)
    public struct Trait: Hashable, Sendable, ExpressibleByStringLiteral {
        /// Enables all default traits of the dependency.
        #if SWIFTPM_CONSTEXPR_MANIFESTS
        @ConstExpr(registrationAccess: .package)
        public static let defaults: Trait = Self.init(name: "default")
        #else
        public static let defaults = Self.init(name: "default")
        #endif

        /// A condition that limits the application of a trait for a dependency.
        public struct Condition: Hashable, Sendable {
            /// The set of traits that enable the dependencies trait.
            let traits: Set<String>?

            /// Creates a package dependency trait condition.
            ///
            /// If the depending package enables any of the traits you provide, the package manager enables the dependency to which this condition applies.
            ///
            /// - Parameter traits: The set of traits that enable the dependencies trait.
            #if SWIFTPM_CONSTEXPR_MANIFESTS
            @ConstExpr(registrationAccess: .package)
            #endif
            public static func when(
                traits: Set<String>
            ) -> Self? {
                return !traits.isEmpty ? Self(traits: traits) : nil
            }
        }

        /// The name of the enabled trait.
        public var name: String

        /// The condition under which the package manager enables the dependency.
        public var condition: Condition?

        /// Creates a new enabled trait.
        ///
        /// - Parameters:
        ///   - name: The name of the enabled trait.
        ///   - condition: The condition under which the trait is enabled.
        #if SWIFTPM_CONSTEXPR_MANIFESTS
        @ConstExpr(registrationAccess: .package)
        #endif
        public init(
            name: String,
            condition: Condition? = nil
        ) {
            self.name = name
            self.condition = condition
        }

        /// Creates a new enabled trait.
        ///
        /// - Parameter value: The name of the enabled trait.
        #if SWIFTPM_CONSTEXPR_MANIFESTS
        @ConstExpr(registrationAccess: .package)
        #endif
        public init(stringLiteral value: StringLiteralType) {
            self.init(name: value)
        }

        /// Creates a new enabled trait.
        ///
        /// - Parameters:
        ///   - name: The name of the enabled trait.
        ///   - condition: The condition under which the trait is enabled.
        #if SWIFTPM_CONSTEXPR_MANIFESTS
        @ConstExpr(registrationAccess: .package)
        #endif
        public static func trait(
            name: String,
            condition: Condition? = nil
        ) -> Trait {
            self.init(
                name: name,
                condition: condition
            )
        }
    }
}

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

import SwiftDiagnostics
import SwiftIfConfig
import SwiftParser
import SwiftSyntax

enum ConstExprManifestSource {
    static func prepare(
        _ source: String,
        fileName: String,
        configuration: StaticBuildConfiguration
    ) throws -> SourceFileSyntax {
        let parsed = Parser.parse(source: source)
        let configuredRegions = parsed.configuredRegions(in: configuration)
        if let diagnostic = configuredRegions.diagnostics.first {
            throw fallback(
                code: "if-config",
                detail: diagnostic.message,
                node: diagnostic.node,
                fileName: fileName
            )
        }

        let active = configuredRegions.removingInactive(from: parsed).cast(SourceFileSyntax.self)
        if let issue = StrictManifestAudit.audit(active) {
            throw fallback(
                code: issue.code,
                detail: issue.detail,
                node: issue.node,
                fileName: fileName
            )
        }
        return active
    }

    static func usesContextGitInformation(_ sourceFile: SourceFileSyntax) -> Bool {
        let visitor = ContextGitInformationVisitor()
        visitor.walk(sourceFile)
        return visitor.foundReference
    }

    /// Convenience for the focused syntax test. Production callers pass the
    /// already configured active syntax tree through the overload above.
    static func usesContextGitInformation(in source: String) -> Bool {
        usesContextGitInformation(Parser.parse(source: source))
    }

    private static func fallback(
        code: String,
        detail: String,
        node: some SyntaxProtocol,
        fileName: String
    ) -> ConstExprManifestFallback {
        let converter = SourceLocationConverter(fileName: fileName, tree: node.root)
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return ConstExprManifestFallback(
            reasonCode: code,
            detail: detail,
            line: location.line,
            column: location.column
        )
    }
}

private final class ContextGitInformationVisitor: SyntaxVisitor {
    var foundReference = false

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.declName.baseName.text == "gitInformation",
              let base = node.base,
              Self.isContextType(base)
        else {
            return .visitChildren
        }
        foundReference = true
        return .skipChildren
    }

    private static func isContextType(_ expression: ExprSyntax) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "Context"
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "Context",
              let base = member.base?.as(DeclReferenceExprSyntax.self)
        else {
            return false
        }
        return base.baseName.text == "PackageDescription"
    }
}

private enum StrictManifestAudit {
    struct Issue {
        let code: String
        let detail: String
        let node: Syntax
    }

    static func audit(_ sourceFile: SourceFileSyntax) -> Issue? {
        var bindingNames: Set<String> = []
        var importsPackageDescription = false

        for item in sourceFile.statements {
            if let importDecl = item.item.as(ImportDeclSyntax.self) {
                switch auditImport(importDecl) {
                case .packageDescription:
                    importsPackageDescription = true
                case .allowed:
                    break
                case .unsupported(let detail):
                    return Issue(code: "unsupported-import", detail: detail, node: Syntax(importDecl))
                }
                continue
            }

            guard let variable = item.item.as(VariableDeclSyntax.self) else {
                return Issue(
                    code: "unsupported-top-level",
                    detail: "the fast path admits only imports and immutable global bindings",
                    node: Syntax(item)
                )
            }
            guard variable.attributes.isEmpty,
                  variable.modifiers.isEmpty,
                  variable.bindingSpecifier.tokenKind == .keyword(.let),
                  variable.bindings.count == 1,
                  let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer?.value,
                  binding.accessorBlock == nil
            else {
                return Issue(
                    code: "unsupported-global-binding",
                    detail: "global bindings must have the form 'let name = expression'",
                    node: Syntax(variable)
                )
            }

            let name = identifier.identifier.text
            guard bindingNames.insert(name).inserted else {
                return Issue(
                    code: "duplicate-global-binding",
                    detail: "global binding '\(name)' is declared more than once",
                    node: Syntax(variable)
                )
            }
            let deferred = DeferredSemanticCollector()
            deferred.walk(initializer)
            if deferred.requiresCompilerValidation {
                return Issue(
                    code: "deferred-expression-semantics",
                    detail: "lazy or branching expression semantics require compiler validation",
                    node: Syntax(initializer)
                )
            }
        }

        guard importsPackageDescription else {
            return Issue(
                code: "missing-package-description-import",
                detail: "an explicit 'import PackageDescription' is required",
                node: Syntax(sourceFile)
            )
        }
        guard bindingNames.contains("package") else {
            return Issue(
                code: "missing-package-binding",
                detail: "a global 'let package = ...' binding is required",
                node: Syntax(sourceFile)
            )
        }

        return nil
    }

    private enum ImportDisposition {
        case packageDescription
        case allowed
        case unsupported(String)
    }

    private static func auditImport(_ declaration: ImportDeclSyntax) -> ImportDisposition {
        guard declaration.attributes.isEmpty,
              declaration.modifiers.isEmpty,
              declaration.path.count == 1,
              let component = declaration.path.first,
              let identifier = component.name.identifier
        else {
            return .unsupported("import attributes, modifiers, and scoped imports are not supported")
        }
        return switch identifier.name {
        case "PackageDescription": .packageDescription
        case "Foundation", "CompilerPluginSupport": .allowed
        default: .unsupported("module '\(identifier.name)' is outside the sealed fast-path registry")
        }
    }

    private final class DeferredSemanticCollector: SyntaxVisitor {
        var requiresCompilerValidation = false

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
            requireCompiler()
        }

        override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
            requireCompiler()
        }

        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
            requireCompiler()
        }

        override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
            requireCompiler()
        }

        override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
            requireCompiler()
        }

        override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
            if ["&&", "||", "??"].contains(node.operator.text) {
                requiresCompilerValidation = true
            }
            return .visitChildren
        }

        private func requireCompiler() -> SyntaxVisitorContinueKind {
            requiresCompilerValidation = true
            return .skipChildren
        }
    }
}

import Foundation
import PackageDescription

@available(_PackageDescription, introduced: 6.3)
public extension Product {
    /// Defines an iOS application whose final app bundle, archive, and IPA are
    /// produced by the `IOSAppBuilder` product-builder plug-in.
    static func iOSApplication(
        name: String,
        target: String,
        configuration: IOSApplicationConfiguration
    ) -> Product {
        let payload = IOSAppBuilderPayload(configuration: configuration)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            preconditionFailure("unable to encode iOS application configuration: \(error)")
        }

        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("unable to encode iOS application configuration as UTF-8")
        }

        return .custom(
            name: name,
            typeIdentifier: IOSAppBuilderPayload.typeIdentifier,
            targets: [target],
            builderPlugin: "IOSAppBuilder",
            builderPluginPackage: "IOSAppSupport",
            arguments: [json]
        )
    }
}

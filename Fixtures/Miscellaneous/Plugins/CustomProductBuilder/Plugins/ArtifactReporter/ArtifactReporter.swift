import Foundation
import PackagePlugin

@main
struct ArtifactReporter: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let result = try packageManager.build(
            .product("ArtifactFixture"),
            parameters: .init()
        )
        print("build-succeeded: \(result.succeeded)")
        for artifact in result.builtArtifacts.sorted(by: { $0.url.path < $1.url.path }) {
            print("artifact: \(artifact.kind.rawValue)|\(artifact.url.path)")
        }
    }
}

// swift-tools-version: 6.3;(experimentalProductBuilders)

import PackageDescription

// A support module imported by the manifest could provide this typed wrapper.
// The fixture keeps it local so it only exercises product-builder behavior.
extension Product {
    @available(_PackageDescription, introduced: 6.3)
    static func picoUF2(name: String, target: String, board: String) -> Product {
        .custom(
            name: name,
            typeIdentifier: "dev.swiftpm.example.pico-uf2",
            targets: [target],
            builderPlugin: "FirmwareBuilder",
            builderPluginPackage: "RP2350Support",
            arguments: ["--board", board]
        )
    }
}

let package = Package(
    name: "CustomProductBuilder",
    products: [
        .picoUF2(name: "Firmware", target: "FirmwareCore", board: "pico2"),
        .custom(
            name: "ArtifactFixture",
            typeIdentifier: "dev.swiftpm.example.pico-uf2",
            targets: ["FirmwareCore"],
            builderPlugin: "FirmwareBuilder",
            builderPluginPackage: "RP2350Support",
            arguments: ["--board", "pico2", "--emit-debug-directory"]
        ),
    ],
    dependencies: [
        .package(name: "RP2350Support", path: "RP2350Support"),
    ],
    targets: [
        .target(
            name: "FirmwareCore",
            resources: [.copy("board.txt")]
        ),
        .plugin(
            name: "ArtifactReporter",
            capability: .command(
                intent: .custom(
                    verb: "report-product-artifacts",
                    description: "Build the artifact fixture and report its final artifacts"
                )
            )
        ),
    ]
)

// swift-tools-version: 6.3;(experimentalProductBuilders)

import PackageDescription

// This typed convenience is defined directly in the manifest. It lowers the
// domain-specific spelling to the proposal's low-level artifact primitive.
extension Product {
    @available(_PackageDescription, introduced: 6.3)
    static func picoUF2(name: String, target: String, board: String) -> Product {
        .artifact(
            name: name,
            typeIdentifier: "pkg:swift/github.com/example/RP2350Support",
            targets: [target],
            builderPlugin: .pluginItem(
                name: "FirmwareBuilder",
                package: "RP2350Support"
            ),
            arguments: ["--board", board]
        )
    }
}

let package = Package(
    name: "CustomProductBuilder",
    products: [
        .picoUF2(name: "Firmware", target: "FirmwareCore", board: "pico2"),
        .artifact(
            name: "ArtifactFixture",
            typeIdentifier: "pkg:swift/github.com/example/RP2350Support",
            targets: ["FirmwareCore"],
            builderPlugin: .pluginItem(
                name: "FirmwareBuilder",
                package: "RP2350Support"
            ),
            arguments: ["--board", "pico2", "--emit-debug-metadata"]
        ),
    ],
    dependencies: [
        .package(name: "RP2350Support", path: "RP2350Support"),
    ],
    targets: [
        .target(
            name: "FirmwareCore",
            dependencies: ["FirmwareC"],
            resources: [
                .copy("board.txt"),
                .copy("Assets"),
                .process("Resources/config.json"),
            ]
        ),
        .target(name: "FirmwareC"),
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

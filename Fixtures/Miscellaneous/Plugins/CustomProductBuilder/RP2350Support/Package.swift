// swift-tools-version: 6.3;(experimentalProductBuilders)

import PackageDescription

let package = Package(
    name: "RP2350Support",
    products: [
        .plugin(name: "FirmwareBuilder", targets: ["FirmwareBuilder"]),
    ],
    targets: [
        .executableTarget(name: "FirmwareFinalizer"),
        .plugin(
            name: "FirmwareBuilder",
            capability: .productBuilder(),
            dependencies: ["FirmwareFinalizer"]
        ),
    ]
)

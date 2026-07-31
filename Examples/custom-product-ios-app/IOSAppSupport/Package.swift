// swift-tools-version: 6.3;(experimentalProductBuilders)

import PackageDescription

let package = Package(
    name: "IOSAppSupport",
    platforms: [.macOS(.v15)],
    products: [
        .plugin(name: "IOSAppBuilder", targets: ["IOSAppBuilder"]),
    ],
    targets: [
        .executableTarget(name: "IOSAppPackager"),
        .plugin(
            name: "IOSAppBuilder",
            capability: .productBuilder(),
            dependencies: ["IOSAppPackager"]
        ),
    ]
)

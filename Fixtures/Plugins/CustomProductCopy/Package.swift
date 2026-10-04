// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CustomProductCopy",
    targets: [
        .target(name: "Artifacts", plugins: [.plugin(name: "Producer")]),
        .plugin(name: "Producer", capability: .buildTool()),
    ]
)

# Experimental Custom Products and Product-Builder Plug-ins

This prototype adds a generic custom-product declaration and a new plug-in
capability that turns an aggregate static archive into one or more final
artifacts. It deliberately does not solve distribution or automatic loading of
manifest API modules yet.

## Manifest API

The generic entry point is exposed on this fork's PackageDescription 6.3
runtime and requires an explicit experimental tools-version opt-in:

```swift
// swift-tools-version: 6.3;(experimentalProductBuilders)
```

```swift
.custom(
    name: "Firmware",
    typeIdentifier: "dev.example.pico-uf2",
    targets: ["FirmwareCore"],
    builderPlugin: "RP2350Builder",
    builderPluginPackage: "RP2350Support",
    arguments: ["--board", "pico2"]
)
```

A definition library can layer a typed spelling over that entry point:

```swift
import PackageDescription

public extension Product {
    @available(_PackageDescription, introduced: 6.3)
    static func picoUF2(name: String, target: String, board: String) -> Product {
        .custom(
            name: name,
            typeIdentifier: "dev.example.pico-uf2",
            targets: [target],
            builderPlugin: "RP2350Builder",
            builderPluginPackage: "RP2350Support",
            arguments: ["--board", board]
        )
    }
}
```

Until SwiftPM can resolve and build manifest API modules, a prebuilt definition
library can be injected manually with repeated `-Xbuild-tools-swiftc` options
for its `-I`, `-L`, link, and runtime-search paths. Manifest cache invalidation
for changes inside such a manually injected module is not implemented.

## Builder API

The plug-in target declares `.productBuilder()` and conforms to
`ProductBuilderPlugin`:

```swift
@main
struct RP2350Builder: ProductBuilderPlugin {
    func createBuildPlan(
        context: PluginContext,
        input: ProductBuilderInput
    ) async throws -> ProductBuilderPlan {
        // Declare explicit-input, explicit-output build commands here.
    }
}
```

`ProductBuilderInput` contains the custom type identifier, product and target
graph, predicted aggregate archive URL, exact copied/processed resource URLs,
resource-bundle roots, opaque manifest arguments, owned output directory,
destination configuration, and destination triple.

The plug-in callback runs while SwiftPM plans the build, before the archive
exists. It must return commands that consume those paths. The native build graph
then executes:

```text
target objects + copied resources
              |
              v
      aggregate static archive
              |
              v
      builder command graph
              |
              v
 declared final files/directories
```

All builder commands must have declared outputs. Prebuild commands are rejected.
Every output must be below SwiftPM's product output directory, every final output
must have exactly one producer, and at least one final output is required.

## Current limits

- Only the native build system is supported; use `--build-system native`.
- Custom products cannot be consumed as ordinary target dependencies yet.
- The input closure currently supports the aggregate static target closure and
  embedded/copied resources. Dynamic and binary-library dependencies are
  rejected until the plug-in input can represent them honestly.
- Custom products are internally lowered to static libraries to reuse SwiftPM's
  existing object aggregation and archive planning. The custom descriptor, not
  that placeholder type, is authoritative.
- Automatic discovery, building, linking, and cache tracking of imported
  manifest definition libraries remains future work.
- Product-builder planning currently covers every reachable root product when
  SwiftPM creates its shared build plan, even if a narrower product subset is
  selected for execution.

See `Fixtures/Miscellaneous/Plugins/CustomProductBuilder` for an executable
example whose builder is vended by a local support-package dependency. It emits
ELF, BIN, and UF2-shaped outputs and rebuilds when its copied resource changes.

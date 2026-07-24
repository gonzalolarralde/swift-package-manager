# Experimental Artifact Products and Product-Builder Plug-ins

This prototype adds a generic artifact-product declaration and a new plug-in
capability that turns an aggregate static archive and processed resources into
one or more final artifacts. It deliberately does not solve distribution or
automatic loading of manifest API modules.

## Intended manifest experience

A definition module should eventually provide a typed API:

```swift
import PackageDescription
import RP2350Support

let package = Package(
    name: "FirmwarePackage",
    products: [
        .picoUF2(
            name: "Firmware",
            target: "FirmwareCore",
            board: .pico2
        ),
    ],
    targets: [
        .target(name: "FirmwareCore"),
    ]
)
```

SwiftPM cannot yet resolve and build a dependency for import into a package
manifest. The prototype can manually inject a prebuilt definition module, or
the typed wrapper can temporarily be defined in `Package.swift`.

The generic API beneath that typed experience is exposed by the experimental
PackageDescription 6.3 runtime:

```swift
// swift-tools-version: 6.3;(experimentalProductBuilders)

.artifact(
    name: "Firmware",
    typeIdentifier: "dev.example.pico-uf2",
    targets: ["FirmwareCore"],
    builderPlugin: "RP2350Builder",
    builderPluginPackage: "RP2350Support",
    arguments: ["--board", "pico2"]
)
```

`.artifact` is a lowering mechanism, not the primary motivation for the
feature. A definition library can encode a versioned `Codable` configuration
and lower its typed helper to this primitive.

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

`ProductBuilderInput` contains:

- the stable type identifier and opaque arguments;
- the product and target graph;
- the predicted aggregate static archive URL;
- exact copied and processed resource URLs and bundle roots;
- the destination triple and configuration; and
- a builder-owned output directory.

The callback runs during PIF planning, before the archive and resources exist.
It must not inspect those predicted paths. Its commands run only after their
declared inputs and host tools exist.

Every command must declare an output. Prebuild commands and in-place mutation
are rejected. Signing, stripping, or similar transformations must happen inside
the command that owns the final output, or use distinct input and output staging
paths.

## Swift Build lowering

SwiftPM owns semantic graph resolution and invokes the planning callback. It
lowers each reachable artifact product to:

1. a hidden standard target that constructs one aggregate static archive; and
2. a public aggregate finalizer target containing the builder commands as
   custom tasks.

The finalizer depends on the archive, resource bundles, builder plug-in target,
and its host tools. Swift Build owns command scheduling, signatures, recursive
directory tracking, missing-output detection, and target completion.

```text
Swift/C/C++ targets ──> hidden static archive ──┐
                                                ├──> builder tasks
processed resources ────────────────────────────┤         |
host tools ─────────────────────────────────────┘         v
                                                  final artifacts
```

An unchanged second build is null. Source-derived archive changes, nested
resource changes, manifest arguments, command signatures, or host-tool changes
rerun the producer. Removing a declared file or directory output also reruns it.

`swift build --product Firmware` selects the finalizer. Build result reporting
returns the declared final files and directories and omits the hidden archive.

## Version-one linkage boundary

The supported input is one aggregate static archive:

- Swift, C, and C++ source targets contribute compiled objects.
- Headers are compilation inputs and are not passed to the finalizer.
- SwiftPM does not pass through its executable or library linker command.
- The builder owns final linkage, runtime and SDK selection, packaging, and
  signing.

SwiftPM diagnoses closures with system-library targets, dynamic-library
products, binary libraries, explicit linked libraries or frameworks, or target
linker flags. Those require a richer future model of linkable inputs.

Only the Swift Build backend supports artifact product execution. The native
and Xcode backends emit an unsupported diagnostic.

## Example

`Fixtures/Miscellaneous/Plugins/CustomProductBuilder` contains a mixed Swift/C
fixture with copied and processed resources. Its support-package dependency
vends a builder and host-side finalizer tool that emit ELF-, BIN-, and UF2-shaped
outputs.

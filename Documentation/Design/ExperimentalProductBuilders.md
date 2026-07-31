# Experimental Artifact Products and Product-Builder Plug-ins

This prototype adds a generic artifact-product declaration and a new plug-in
capability that turns an aggregate static archive and processed resources into
one or more final artifacts. It deliberately does not solve distribution or
automatic loading of manifest API modules.

## Intended manifest experience

The consuming package defines a typed helper in its manifest:

```swift
import PackageDescription

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

The generic API beneath that typed experience is exposed by the experimental
PackageDescription 6.3 runtime:

```swift
// swift-tools-version: 6.3;(experimentalProductBuilders)

.artifact(
    name: "Firmware",
    typeIdentifier: "pkg:swift/github.com/example/RP2350Support",
    targets: ["FirmwareCore"],
    builderPlugin: .pluginItem(
        name: "RP2350Builder",
        package: "RP2350Support"
    ),
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
- exhaustive copied and processed resource file URLs;
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
makes the compiled target closure available as an implicit, private aggregate
archive and adds the returned commands as product-completion work.

Swift Build orders the commands after the archive, resource-copy targets,
builder plug-in target, and host tools. It owns command scheduling, signatures,
missing-output detection, and target completion.

```text
Swift/C/C++ targets ──> implicit private archive ──┐
                                                   ├──> builder tasks
resource-copy completion ──────────────────────────┤         |
host tools ────────────────────────────────────────┘         v
                                                     output files
```

The plug-in API exposes exhaustive resource file paths, and all builder outputs
are files. Builders create parent directories beneath their owned output
directory. The aggregate finalizer depends on the targets that copy the resource
bundles, which orders its tasks after resource processing. The PIF adapter adds
the original resource files to each task signature so nested changes invalidate
the finalizer without treating a directory as a custom-task input. This does
not require directory fields in the custom-task PIF model or expose directories
to the plug-in.

An unchanged second build is null. Source-derived archive changes,
resource-file changes, manifest arguments, command signatures, or host-tool
changes rerun the producer. Removing a declared output file also reruns it.

`swift build --product Firmware` selects the product-completion work. The
implicit archive is not separately named, selected, or vended.

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

The implicit archive is the prototype's ergonomic default: it avoids requiring
package authors to vend and name an intermediate static-library product. An
alternative under discussion is allowing builders to consume explicit library
or executable products, or advanced per-target object-file inputs.

Only the Swift Build backend supports artifact product execution. The native
and Xcode backends emit an unsupported diagnostic.

## Example

`Fixtures/Miscellaneous/Plugins/CustomProductBuilder` contains a mixed Swift/C
fixture with copied and processed resources. Its support-package dependency
vends a builder and host-side finalizer tool that emit ELF-, BIN-, and UF2-shaped
outputs.

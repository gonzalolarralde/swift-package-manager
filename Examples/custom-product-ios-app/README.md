# SwiftPM artifact iOS application product demo

> [!IMPORTANT]
> This example is committed only on the demonstration branch so the prototype
> can be exercised and discussed end to end. It is not intended to be included
> in an eventual mergeable Swift Package Manager implementation or test PR.

This package exercises the experimental artifact-product/product-builder work
in this SwiftPM checkout. `Package.swift` declares the low-level
`.artifact(...)` product directly and passes the builder a versioned JSON
configuration. SwiftPM plans the product, Swift Build creates its aggregate
archive and resources for `arm64-apple-ios`, and an externally vended
product-builder plug-in turns those inputs into an Xcode archive and IPA.

The default build is deliberately unsigned. It produces a real device Mach-O,
`.app`, `.xcarchive`, and IPA-shaped zip that can be inspected end to end, but
the IPA cannot be installed until it is exported with a matching Apple signing
identity and provisioning profile.

## Run it

Requirements:

- macOS with Xcode and the iPhoneOS SDK
- XcodeGen (`brew install xcodegen`, or set `XCODEGEN` to its executable)
- this SwiftPM checkout built once from its repository root, or explicit
  `SWIFTPM_ROOT` and `SWIFT_BUILD` environment variables
- an installed iOS Simulator runtime for the Simulator run command

Use the wrappers below for the example itself rather than invoking stock
`swift build` in this directory. They select this checkout's SwiftPM build,
the Swift Build backend, SDK, destination triple, and product-builder sandbox
mode. They are demonstration harnesses, not part of the proposed product-builder
API, and they do not perform the application packaging themselves:

- `build-demo.sh` invokes the device build with the prototype-specific command
  line and reports the generated IPA.
- `run-simulator-demo.sh` selects the Simulator destination, verifies the
  resulting `.app`, and optionally installs and launches it.
- `prepare-local-runtime.sh` gives the self-built SwiftPM executable its
  matching experimental `PackageDescription` and `PackagePlugin` runtimes. The
  two build wrappers call it automatically.
- `check-model-sync.sh` is an automatic preflight that prevents the plug-in and
  its host-side packaging tool from decoding different configuration schemas.
- `inspect-artifacts.sh`, `export-swift-build-diagnostics.sh`, and
  `validate-archive.sh` are optional post-build inspection, graph-export, and
  App Store validation tools.

```sh
# From the SwiftPM repository root:
swift build
cd Examples/custom-product-ios-app
./Scripts/build-demo.sh
./Scripts/inspect-artifacts.sh
```

If the repository's `.swift-version` is not installed through Swiftly, use
`xcrun swift build` for the first command to select Xcode's Swift toolchain.

The example build wrapper prepares an ignored runtime layout for the
self-built SwiftPM libraries, then invokes this checkout's `swift-build` with
the Swift Build backend for `arm64-apple-ios17.0`. It prints the exact IPA and
JSON build-report paths. This runtime selection is needed because the
experimental manifest and plug-in APIs are not installed in Xcode's toolchain;
it is unrelated to typed product-definition modules.

Unchanged builds are incremental: Swift Build sees that the archive, resources,
command signature, host-side tool, and declared final outputs are current, so
it does not invoke Xcode again.

To inspect how SwiftPM's model becomes Swift Build work after any device build:

```sh
./Scripts/export-swift-build-diagnostics.sh
```

The ignored `.demo-runtime/swift-build-diagnostics` directory contains the raw
PIF, build request, configured-target graph, complete llbuild manifest, all
planned tasks as JSON and CSV, the product-builder task and its data edges, and
historical command timing from `build.db`. It also exports the nested device and
Simulator Xcode build descriptions under `nested-builds/`. Those inner graphs
are separate: the outer Swift Build graph sees `IOSAppPackager` as one custom
task, not the Xcode compilation, asset, signing, and archive tasks it launches.

In Swift Build terminology, the PIF is the project model supplied by SwiftPM.
Swift Build configures its targets, uses task producers to create `PlannedTask`
values, and serializes those tasks as llbuild commands. The numerous `phony`
commands in the export are ordering gates, not subprocesses;
`executable-tasks.json` filters those out.

To compile the same SwiftPM target for the iOS Simulator, install the declared
Simulator `.app` into a booted device, and launch it:

```sh
./Scripts/run-simulator-demo.sh
```

Set `IOS_DEMO_SIMULATOR_BUILD_ONLY=1` to stop after producing the app, or
`IOS_DEMO_SIMULATOR_DEVICE=DEVICE_UDID` to use a specific Simulator. This is a
separate `arm64-apple-ios17.0-simulator` build: a device IPA contains an
`iphoneos` executable and cannot run on Simulator.

## Validation performed

- The generated archive opens in Xcode Organizer as an **iOS App Archive** with
  the expected `arm64` architecture, version, and bundle identifier. As
  expected, Xcode reports `No Team Found in Archive` if **Validate App** is run
  against the default unsigned build.
- An automatically signed build was exercised end to end. Xcode archived and
  exported a debugging IPA, the application signature and embedded profile
  matched, and App Store Connect validation accepted version `1.0 (1)`.
- `Scripts/inspect-artifacts.sh` checks the device platform load command,
  archive and application property lists, IPA zip integrity, matching app/dSYM
  UUIDs, bundle metadata, copied SwiftPM resources, and compiled `AppIcon` and
  `AccentColor` renditions.
- A direct `simctl install` of the device IPA can unpack the bundle, but
  SpringBoard denies launch because its executable reports `platform IOS`.
  `Scripts/run-simulator-demo.sh` instead generates an executable reporting
  `platform IOSSIMULATOR`; that application was installed, launched, navigated,
  and relaunched from its custom home-screen icon on an iOS Simulator.

Signed builds deliberately remove their declared outputs before building
because keychain identities and provisioning profiles are ambient rather than
ordinary file inputs. After changing an external Xcode/XcodeGen installation in
unsigned mode, set
`IOS_DEMO_FORCE_REPACKAGE=1` once to refresh the wrapper artifacts.

## The manifest API

The example deliberately uses the proposal's low-level primitive. The manifest
constructs a JSON object with `Foundation.JSONSerialization` and passes the
versioned payload as an opaque argument:

```swift
import PackageDescription

let builderPayload = /* sorted JSON containing schemaVersion + configuration */

.artifact(
    name: "IOSDemoIPA",
    typeIdentifier: "pkg:swift/github.com/example/IOSAppSupport",
    targets: ["DemoApp"],
    builderPlugin: .pluginItem(
        name: "IOSAppBuilder",
        package: "IOSAppSupport"
    ),
    arguments: [builderPayload]
)
```

`IOSAppBuilder` decodes that payload into its typed Codable configuration and
validates it during planning. The same Codable schema is copied into the
planning plug-in and executable packager; `Scripts/check-model-sync.sh`
prevents those two copies from silently drifting. A production package could
define a typed convenience later in its own manifest that wraps
`.artifact(...)`, without changing the underlying product-builder protocol.

The split takes its shape from the referenced
[`bluffy.spec`](https://github.com/Sympatito/bluffy/blob/master/editor/bluffy.spec): bundle identity
and versions correspond to `BUNDLE`; architectures/linking/build options to
`EXE`; resources to `Analysis.datas`/`COLLECT`; and signing plus entitlements to
the code-sign configuration. PyInstaller itself is not used because it does not
link, provision, or export iOS applications.

## What the builder does

1. SwiftPM compiles `DemoApp` and creates `libIOSDemoIPA.a`, including the
   SwiftUI `@main` entry point.
2. SwiftPM processes `SampleContent.json` into the target's resource bundle.
3. `IOSAppBuilder` decodes and validates the manifest JSON while planning. It
   declares one host-tool command whose inputs are the aggregate archive and
   individual resource files. Its outputs are the IPA, report, and the stable
   leaf files inside the generated `.xcarchive`/`.app`; the packager creates
   their parent directories.
4. `IOSAppPackager` copies those inputs into an owned work directory, creates
   Info.plist, entitlements, an empty Swift link anchor, and an XcodeGen
   project. The demo's raw `AppAssets.xcassets` is a copied target resource;
   the generated application target compiles its `AppIcon` and `AccentColor`.
5. The generated application target force-loads SwiftPM's archive, embeds the
   resource bundle unchanged (so `Bundle.module` still works), and lets Xcode
   stamp platform metadata and embed the Swift runtime as needed.
6. Xcode archives the device app. Signed modes use `xcodebuild -exportArchive`;
   unsigned/local-ad-hoc smoke-test modes create the `Payload/*.app` IPA layout
   directly. For a Simulator triple, Xcode instead emits a declared Simulator
   `.app`; the wrapper installs and launches it with `simctl`. The JSON report
   labels the artifact kind and installation readiness explicitly.

The configuration schema also models privacy strings, URL types, orientations,
launch screens, raw Info.plist entries, application groups, associated domains,
push/iCloud/keychain entitlements, weak/required frameworks, raw asset catalogs,
manual profiles, build stripping/dSYM choices, and current Xcode export methods.

## Producing an installable IPA

A device-installable IPA requires a certificate and provisioning profile that
both match the bundle identifier, team, and device, as described in Apple's
[registered-device distribution workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices). For automatic signing:

```sh
IOS_DEMO_SIGNING=automatic \
IOS_DEMO_TEAM_ID=YOUR_TEAM_ID \
IOS_DEMO_BUNDLE_ID=com.yourcompany.swiftpm-demo \
./Scripts/build-demo.sh
```

That first tries already-installed signing material. To explicitly authorize
Xcode to contact the developer service and download or create profiles, add:

```sh
IOS_DEMO_ALLOW_PROVISIONING_UPDATES=1
```

Registering a connected device is a separate, broader mutation and requires a
second explicit opt-in (together with provisioning updates):

```sh
IOS_DEMO_ALLOW_PROVISIONING_UPDATES=1 \
IOS_DEMO_ALLOW_DEVICE_REGISTRATION=1
```

The script disables SwiftPM's plug-in sandbox for the Xcode-backed finalizer.
In addition to signing access, Xcode's asset compiler consults CoreSimulator
services even while compiling an `iphoneos` app-icon catalog; those XPC calls
are not admitted by SwiftPM's current plug-in sandbox profile.

Manual signing uses `IOS_DEMO_SIGNING=manual` plus `IOS_DEMO_TEAM_ID`,
`IOS_DEMO_SIGNING_IDENTITY`, `IOS_DEMO_PROFILE_NAME`, and a matching
`IOS_DEMO_BUNDLE_ID`.

### Validate the signed archive with App Store Connect

App Store validation is deliberately a post-archive operation rather than a
product-builder output. The validation export method uses destination `upload`,
contacts Apple's validation service, and emits no IPA. The artifact product
continues to emit its installable `debugging` IPA while the validation script
consumes the same signed `.xcarchive`:

```sh
IOS_DEMO_SIGNING=automatic \
IOS_DEMO_TEAM_ID=YOUR_TEAM_ID \
IOS_DEMO_BUNDLE_ID=com.example.swiftpm-custom-product-demo \
IOS_DEMO_ALLOW_PROVISIONING_UPDATES=1 \
./Scripts/build-demo.sh

IOS_DEMO_TEAM_ID=YOUR_TEAM_ID ./Scripts/validate-archive.sh
```

Before running the second command, App Store Connect must contain an iOS app
record whose bundle ID exactly matches the archive. Apple documents that
requirement in [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

`validate-archive.sh` refuses unsigned, mismatched-team, and mismatched-bundle
archives before contacting Apple. It regenerates
`.demo-runtime/ValidationExportOptions.plist` with the current Xcode
`method=validation`, `destination=upload`, and automatic signing options, then
runs `xcodebuild -exportArchive` with `-allowProvisioningUpdates`. No Apple
Account password, API key, certificate, or private key is written to disk; Xcode
uses the account already logged in through its Accounts settings.

Each attempt keeps its console log under
`.demo-runtime/app-store-validation/<run-id>/xcodebuild.log`. A successful run
writes `VALIDATION_SUCCEEDED` beside that log and refreshes
`.demo-runtime/app-store-validation/LATEST_SUCCESS`. A failed attempt removes
the latest-success marker and exits nonzero while preserving its diagnostic
log. Invoking this script explicitly authorizes Xcode to contact Apple and to
create or download managed provisioning assets as needed.

## Prototype limits

- Product builders run through Swift Build. The native and Xcode backends reject
  artifact products in this prototype.
- The current SwiftPM input API rejects dynamic and binary-library dependencies.
  The JSON schema reserves those concepts, but the packager fails clearly if
  asked to use a library input SwiftPM cannot expose yet.
- Storyboard launch screens and arbitrary resource placements are similarly
  reserved in the versioned schema but rejected during planning until SwiftPM
  exposes the source/destination resource pairs needed to implement them.
- Custom raw asset catalogs must survive in a copied SwiftPM resource. The
  default path generates classic icon PNG variants so this demo does not depend
  on an installed Simulator runtime just to compile an icon catalog.
- The generated Xcode project is an implementation detail under the builder's
  output directory, not source of truth checked into the package.
- External Xcode/XcodeGen versions and keychain contents are not first-class
  product-builder inputs yet. The demo script forces signed repackaging and
  offers `IOS_DEMO_FORCE_REPACKAGE=1`; a production API should model toolchain
  identities and signing-state invalidation explicitly.

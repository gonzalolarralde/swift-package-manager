# Custom product copy reproduction

This macOS fixture requires the custom-target and `BuildProduct` APIs from
SwiftPM PR #10374, including its PackagePlugin runtime. It cannot be run on main
without that PR. It requires only Xcode command-line tools, not PicoSDK or an
embedded toolchain.

With `SWIFT_BUILD` pointing to the freshly built executable, run from this
directory:

```sh
"$SWIFT_BUILD" --build-system swiftbuild --target Artifacts -c release
bin_path=$("$SWIFT_BUILD" --build-system swiftbuild -c release --show-bin-path)
cmp .build/plugins/outputs/customproductcopy/Artifacts/destination/Producer/Release/libArtifacts.a \
    "$bin_path/libArtifacts.a"
```

The plugin creates a native static archive containing debug information and
publishes it through `productFiles`. Before the fix, Release's copy phase strips
the archive and `cmp` fails. After the fix, the published archive is byte-for-byte
identical to the producer's output. The same comparison must also pass in Debug
(replace `release`/`Release` with `debug`/`Debug`).

Use a fresh scratch directory when switching binaries. The PIF regression test
also checks that Release uses release-specific settings instead of Debug's.

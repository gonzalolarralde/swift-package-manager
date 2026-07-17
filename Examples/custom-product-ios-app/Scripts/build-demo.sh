#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$(cd "$DEMO_ROOT/../.." && pwd)}"
SWIFT_BUILD="${SWIFT_BUILD:-$SWIFTPM_ROOT/.build/debug/swift-build}"
SWIFTC="$(xcrun --find swiftc)"
SDK_ROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
MACOS_SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
HOST_ARCH="$(uname -m)"
BUILD_CONFIGURATION="${IOS_DEMO_CONFIGURATION:-release}"
RUNTIME_ROOT="$DEMO_ROOT/.demo-runtime"
MANIFEST_API="$RUNTIME_ROOT/ManifestAPI"
PLUGIN_API="$RUNTIME_ROOT/PluginAPI"
DEFINITION_MODULE="$RUNTIME_ROOT/IOSAppProductTypes"
PACKAGE_DESCRIPTION_LIBRARY="$SWIFTPM_ROOT/.build/debug/libPackageDescription.dylib"
PACKAGE_PLUGIN_LIBRARY="$SWIFTPM_ROOT/.build/debug/libPackagePlugin.dylib"
PACKAGE_DESCRIPTION_MODULE="$SWIFTPM_ROOT/.build/debug/Modules/PackageDescription.swiftmodule"
PACKAGE_PLUGIN_MODULE="$SWIFTPM_ROOT/.build/debug/Modules/PackagePlugin.swiftmodule"

# Native SwiftPM builds place modules under `Modules/`; the Xcode-backed test
# build places them directly in the products directory.
if [[ ! -e "$PACKAGE_DESCRIPTION_MODULE" ]]; then
    PACKAGE_DESCRIPTION_MODULE="$SWIFTPM_ROOT/.build/debug/PackageDescription.swiftmodule"
fi
if [[ ! -e "$PACKAGE_PLUGIN_MODULE" ]]; then
    PACKAGE_PLUGIN_MODULE="$SWIFTPM_ROOT/.build/debug/PackagePlugin.swiftmodule"
fi

if [[ ! -x "$SWIFT_BUILD" ]]; then
    echo "error: custom swift-build was not found at $SWIFT_BUILD" >&2
    echo "Build the SwiftPM fork first or set SWIFT_BUILD and SWIFTPM_ROOT." >&2
    exit 1
fi
if [[ ! -f "$PACKAGE_DESCRIPTION_LIBRARY" ]] ||
   [[ ! -f "$PACKAGE_PLUGIN_LIBRARY" ]] ||
   [[ ! -e "$PACKAGE_DESCRIPTION_MODULE" ]] ||
   [[ ! -e "$PACKAGE_PLUGIN_MODULE" ]]; then
    echo "error: the fork's PackageDescription and PackagePlugin runtimes are not built" >&2
    exit 1
fi
if [[ -n "${XCODEGEN:-}" ]] && [[ -x "$XCODEGEN" ]]; then
    XCODEGEN_BIN="$XCODEGEN"
else
    XCODEGEN_BIN="$(command -v xcodegen || true)"
fi
if [[ -z "$XCODEGEN_BIN" ]]; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

"$DEMO_ROOT/Scripts/check-model-sync.sh"

mkdir -p "$MANIFEST_API" "$PLUGIN_API" "$DEFINITION_MODULE"
ln -sfn "$PACKAGE_DESCRIPTION_LIBRARY" "$MANIFEST_API/libPackageDescription.dylib"
ln -sfn "$PACKAGE_DESCRIPTION_MODULE" "$MANIFEST_API/PackageDescription.swiftmodule"
ln -sfn "$PACKAGE_PLUGIN_LIBRARY" "$PLUGIN_API/libPackagePlugin.dylib"
ln -sfn "$PACKAGE_PLUGIN_MODULE" "$PLUGIN_API/PackagePlugin.swiftmodule"

DEFINITION_LIBRARY="$DEFINITION_MODULE/libIOSAppProductTypes.dylib"
DEFINITION_MODEL="$DEMO_ROOT/IOSAppProductTypes/Sources/IOSAppProductTypes/IOSApplicationConfiguration.swift"
DEFINITION_PRODUCT="$DEMO_ROOT/IOSAppProductTypes/Sources/IOSAppProductTypes/Product+IOSApplication.swift"
if [[ ! -f "$DEFINITION_LIBRARY" ]] ||
   [[ ! -f "$DEFINITION_MODULE/IOSAppProductTypes.swiftmodule" ]] ||
   [[ "$DEFINITION_MODEL" -nt "$DEFINITION_LIBRARY" ]] ||
   [[ "$DEFINITION_PRODUCT" -nt "$DEFINITION_LIBRARY" ]] ||
   [[ "$PACKAGE_DESCRIPTION_LIBRARY" -nt "$DEFINITION_LIBRARY" ]]; then
    "$SWIFTC" \
        -emit-library \
        -emit-module \
        -module-name IOSAppProductTypes \
        -package-description-version 999.0 \
        -sdk "$MACOS_SDK_ROOT" \
        -target "$HOST_ARCH-apple-macosx15.0" \
        -I "$MANIFEST_API" \
        -L "$MANIFEST_API" \
        -lPackageDescription \
        -Xlinker -rpath \
        -Xlinker "$MANIFEST_API" \
        -emit-module-path "$DEFINITION_MODULE/IOSAppProductTypes.swiftmodule" \
        -o "$DEFINITION_LIBRARY" \
        "$DEFINITION_MODEL" \
        "$DEFINITION_PRODUCT"
fi

MANIFEST_FLAGS=(
    -Xbuild-tools-swiftc -I
    -Xbuild-tools-swiftc "$DEFINITION_MODULE"
    -Xbuild-tools-swiftc -L
    -Xbuild-tools-swiftc "$DEFINITION_MODULE"
    -Xbuild-tools-swiftc -lIOSAppProductTypes
    -Xbuild-tools-swiftc -Xlinker
    -Xbuild-tools-swiftc -rpath
    -Xbuild-tools-swiftc -Xlinker
    -Xbuild-tools-swiftc "$DEFINITION_MODULE"
)

export SWIFTPM_CUSTOM_LIBS_DIR="$RUNTIME_ROOT"
export XCODEGEN="$XCODEGEN_BIN"

# Certificates, profiles, and external XcodeGen/Xcode installations are not
# ordinary SwiftPM file inputs. Signed builds always re-run the finalizer; the
# same behavior is available explicitly for unsigned toolchain changes.
AGGREGATE_ARCHIVE="$DEMO_ROOT/.build/arm64-apple-ios/$BUILD_CONFIGURATION/libIOSDemoIPA.a"
if [[ "${IOS_DEMO_SIGNING:-unsigned}" == "automatic" ]] ||
   [[ "${IOS_DEMO_SIGNING:-unsigned}" == "manual" ]] ||
   [[ "${IOS_DEMO_FORCE_REPACKAGE:-0}" == "1" ]]; then
    if [[ -f "$AGGREGATE_ARCHIVE" ]]; then
        touch "$AGGREGATE_ARCHIVE"
    fi
fi

BUILD_ARGUMENTS=(
    --package-path "$DEMO_ROOT"
    --scratch-path "$DEMO_ROOT/.build"
    --build-system native
    --manifest-cache none
    --configuration "$BUILD_CONFIGURATION"
    --sdk "$SDK_ROOT"
    --triple arm64-apple-ios17.0
    --product IOSDemoIPA
)
# Xcode's asset compiler consults CoreSimulator services even for an iphoneos
# archive. Those XPC lookups are outside SwiftPM's current plug-in sandbox, so
# this Xcode-backed demo must run its finalizer unsandboxed.
BUILD_ARGUMENTS+=(--disable-sandbox)
BUILD_ARGUMENTS+=("${MANIFEST_FLAGS[@]}")

# Product-builder plans capture the planning plug-in and manifest-supplied
# environment. Refresh that plan only when those inputs change; always deleting
# it would relink the host tool and defeat finalizer incrementality.
PLAN_FILE="$DEMO_ROOT/.build/$BUILD_CONFIGURATION.yaml"
PLAN_STATE="$RUNTIME_ROOT/$BUILD_CONFIGURATION-product-builder-plan.sha256"
PLAN_SOURCE_HASH="$({
    shasum -a 256 \
        "$DEMO_ROOT/Package.swift" \
        "$DEMO_ROOT/IOSAppSupport/Package.swift" \
        "$DEMO_ROOT/IOSAppProductTypes/Sources/IOSAppProductTypes/"*.swift \
        "$DEMO_ROOT/IOSAppSupport/Plugins/IOSAppBuilder/"*.swift
    stat -f '%m:%z' \
        "$SWIFT_BUILD" \
        "$PACKAGE_DESCRIPTION_LIBRARY" \
        "$PACKAGE_PLUGIN_LIBRARY" \
        "$PACKAGE_DESCRIPTION_MODULE" \
        "$PACKAGE_PLUGIN_MODULE"
} | shasum -a 256 | awk '{print $1}')"
PLAN_ENVIRONMENT="device|$BUILD_CONFIGURATION|${IOS_DEMO_SIGNING:-unsigned}|${IOS_DEMO_TEAM_ID:-}|${IOS_DEMO_BUNDLE_ID:-}|${IOS_DEMO_SIGNING_IDENTITY:-}|${IOS_DEMO_PROFILE_NAME:-}|${IOS_DEMO_ALLOW_PROVISIONING_UPDATES:-0}|${IOS_DEMO_ALLOW_DEVICE_REGISTRATION:-0}"
PLAN_FINGERPRINT="$(printf '%s\n%s\n' "$PLAN_SOURCE_HASH" "$PLAN_ENVIRONMENT" | shasum -a 256 | awk '{print $1}')"
if [[ ! -f "$PLAN_STATE" ]] || [[ "$(<"$PLAN_STATE")" != "$PLAN_FINGERPRINT" ]]; then
    rm -f "$PLAN_FILE"
fi

"$SWIFT_BUILD" "${BUILD_ARGUMENTS[@]}"
printf '%s\n' "$PLAN_FINGERPRINT" > "$PLAN_STATE"

REPORT_PATH="$DEMO_ROOT/.build/arm64-apple-ios/$BUILD_CONFIGURATION/IOSDemoIPA.product/product-builder/outputs/IOSDemoIPA-build-report.json"
if [[ ! -f "$REPORT_PATH" ]]; then
    echo "error: build completed without the declared IPA/report outputs" >&2
    exit 1
fi
IPA_PATH="$(plutil -extract outputIPA raw -o - "$REPORT_PATH")"
if [[ ! -f "$IPA_PATH" ]]; then
    echo "error: build report points to a missing IPA: $IPA_PATH" >&2
    exit 1
fi

echo
echo "IPA: $IPA_PATH"
echo "Report: $REPORT_PATH"

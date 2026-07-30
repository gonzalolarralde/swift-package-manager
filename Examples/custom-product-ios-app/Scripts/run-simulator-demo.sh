#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$(cd "$DEMO_ROOT/../.." && pwd)}"
SWIFT_BUILD="${SWIFT_BUILD:-$SWIFTPM_ROOT/.build/debug/swift-build}"
SDK_ROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"
BUILD_CONFIGURATION="${IOS_DEMO_CONFIGURATION:-debug}"
SIMULATOR_DEVICE="${IOS_DEMO_SIMULATOR_DEVICE:-booted}"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "error: this prototype currently builds only an arm64 iOS Simulator application" >&2
    exit 1
fi
if [[ ! -x "$SWIFT_BUILD" ]]; then
    echo "error: custom swift-build was not found at $SWIFT_BUILD" >&2
    echo "Build the SwiftPM fork first or set SWIFT_BUILD and SWIFTPM_ROOT." >&2
    exit 1
fi
SWIFTPM_RUNTIME_ROOT="$("$DEMO_ROOT/Scripts/prepare-local-runtime.sh" "$SWIFTPM_ROOT")"
export SWIFTPM_CUSTOM_LIBS_DIR="$SWIFTPM_RUNTIME_ROOT"
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
export XCODEGEN="$XCODEGEN_BIN"
# Simulator applications do not use device certificates or provisioning.
export IOS_DEMO_SIGNING=unsigned

OUTPUT_DIR="$DEMO_ROOT/.build/plugins/outputs/custom-product-ios-app/IOSDemoIPA/destination/arm64-apple-ios17.0-simulator/$BUILD_CONFIGURATION/IOSAppBuilder/outputs"
if [[ "${IOS_DEMO_FORCE_REPACKAGE:-0}" == "1" ]]; then
    rm -rf "$OUTPUT_DIR"
fi

"$SWIFT_BUILD" \
    --package-path "$DEMO_ROOT" \
    --scratch-path "$DEMO_ROOT/.build" \
    --build-system swiftbuild \
    --manifest-cache none \
    --configuration "$BUILD_CONFIGURATION" \
    --sdk "$SDK_ROOT" \
    --triple arm64-apple-ios17.0-simulator \
    --product IOSDemoIPA \
    --disable-sandbox

REPORT_PATH="$OUTPUT_DIR/IOSDemoIPA-simulator-build-report.json"
if [[ ! -f "$REPORT_PATH" ]]; then
    echo "error: build completed without the declared Simulator app/report outputs" >&2
    exit 1
fi
APP_PATH="$(plutil -extract outputApplication raw -o - "$REPORT_PATH")"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build report points to a missing Simulator app: $APP_PATH" >&2
    exit 1
fi
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP_PATH/Info.plist")"
plutil -lint "$APP_PATH/Info.plist"
xcrun vtool -show-build "$APP_PATH/$EXECUTABLE_NAME" | grep -q IOSSIMULATOR
if [[ ! -f "$APP_PATH/Assets.car" ]]; then
    echo "error: Simulator app does not contain the compiled target asset catalog" >&2
    exit 1
fi
ASSET_INFO="$(xcrun assetutil --info "$APP_PATH/Assets.car")"
grep -q '"Name" : "AppIcon"' <<< "$ASSET_INFO"
grep -q '"Name" : "AccentColor"' <<< "$ASSET_INFO"
if ! find "$APP_PATH" -name SampleContent.json -print -quit | grep -q .; then
    echo "error: Simulator app does not contain the SwiftPM JSON resource" >&2
    exit 1
fi
if [[ "$(plutil -extract artifactKind raw -o - "$REPORT_PATH")" != "simulatorApplication" ]]; then
    echo "error: build report does not identify a Simulator application" >&2
    exit 1
fi

if [[ "${IOS_DEMO_SIMULATOR_BUILD_ONLY:-0}" != "1" ]]; then
    if [[ "$SIMULATOR_DEVICE" == "booted" ]] &&
       ! xcrun simctl list devices booted | grep -q '(Booted)'; then
        echo "error: no iOS Simulator is booted; boot one or set IOS_DEMO_SIMULATOR_DEVICE to a device UDID" >&2
        exit 1
    fi
    xcrun simctl bootstatus "$SIMULATOR_DEVICE" -b
    # A fresh install avoids SpringBoard retaining an icon from an earlier
    # version of the generated bundle while iterating on target assets.
    xcrun simctl terminate "$SIMULATOR_DEVICE" \
        "${IOS_DEMO_BUNDLE_ID:-dev.swiftpm.custom-products.ios-demo}" 2>/dev/null || true
    xcrun simctl uninstall "$SIMULATOR_DEVICE" \
        "${IOS_DEMO_BUNDLE_ID:-dev.swiftpm.custom-products.ios-demo}" 2>/dev/null || true
    xcrun simctl install "$SIMULATOR_DEVICE" "$APP_PATH"
    xcrun simctl launch --terminate-running-process "$SIMULATOR_DEVICE" \
        "${IOS_DEMO_BUNDLE_ID:-dev.swiftpm.custom-products.ios-demo}"
fi

echo
echo "Simulator app: $APP_PATH"
echo "Report: $REPORT_PATH"

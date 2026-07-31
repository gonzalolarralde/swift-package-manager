#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$(cd "$DEMO_ROOT/../.." && pwd)}"
SWIFT_BUILD="${SWIFT_BUILD:-$SWIFTPM_ROOT/.build/debug/swift-build}"
SDK_ROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
BUILD_CONFIGURATION="${IOS_DEMO_CONFIGURATION:-release}"

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

# Certificates, profiles, and external XcodeGen/Xcode installations are not
# ordinary file inputs. Signed builds remove their declared final outputs so
# Swift Build schedules the producer again; the same behavior is available
# explicitly for unsigned toolchain changes.
OUTPUT_DIR="$DEMO_ROOT/.build/plugins/outputs/custom-product-ios-app/IOSDemoIPA/destination/arm64-apple-ios17.0/$BUILD_CONFIGURATION/IOSAppBuilder/outputs"
if [[ "${IOS_DEMO_SIGNING:-unsigned}" == "automatic" ]] ||
   [[ "${IOS_DEMO_SIGNING:-unsigned}" == "manual" ]] ||
   [[ "${IOS_DEMO_FORCE_REPACKAGE:-0}" == "1" ]]; then
    rm -rf "$OUTPUT_DIR"
fi

BUILD_ARGUMENTS=(
    --package-path "$DEMO_ROOT"
    --scratch-path "$DEMO_ROOT/.build"
    --build-system swiftbuild
    --manifest-cache none
    --configuration "$BUILD_CONFIGURATION"
    --sdk "$SDK_ROOT"
    --triple arm64-apple-ios17.0
    --product IOSDemoIPA
    --disable-sandbox
)

"$SWIFT_BUILD" "${BUILD_ARGUMENTS[@]}"

REPORT_PATH="$OUTPUT_DIR/IOSDemoIPA-build-report.json"
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

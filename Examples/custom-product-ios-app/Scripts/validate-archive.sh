#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONFIGURATION="${IOS_DEMO_CONFIGURATION:-release}"
TEAM_ID="${IOS_DEMO_TEAM_ID:-}"
RUNTIME_ROOT="$DEMO_ROOT/.demo-runtime"
OUTPUT_DIR="$DEMO_ROOT/.build/plugins/outputs/custom-product-ios-app/IOSDemoIPA/destination/arm64-apple-ios17.0/$BUILD_CONFIGURATION/IOSAppBuilder/outputs"
REPORT="$OUTPUT_DIR/IOSDemoIPA-build-report.json"
OPTIONS_PLIST="$RUNTIME_ROOT/ValidationExportOptions.plist"
VALIDATION_ROOT="$RUNTIME_ROOT/app-store-validation"

if [[ -z "$TEAM_ID" ]]; then
    echo "error: IOS_DEMO_TEAM_ID is required for App Store validation" >&2
    echo "example: IOS_DEMO_TEAM_ID=YOUR_TEAM_ID ./Scripts/validate-archive.sh" >&2
    exit 1
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "error: IOS_DEMO_TEAM_ID must be a 10-character Apple Developer team identifier" >&2
    exit 1
fi
if [[ ! -f "$REPORT" ]]; then
    echo "error: build report not found at $REPORT" >&2
    echo "Create an automatically signed device archive with Scripts/build-demo.sh first." >&2
    exit 1
fi

ARCHIVE="$(plutil -extract outputArchive raw -o - "$REPORT")"
APP="$(plutil -extract outputApplication raw -o - "$REPORT")"
BUNDLE_ID="$(plutil -extract bundleIdentifier raw -o - "$REPORT")"
SIGNED_EXPORT="$(plutil -extract signedExport raw -o - "$REPORT")"
SIGNING_STYLE="$(plutil -extract signingStyle raw -o - "$REPORT")"

if [[ ! -d "$ARCHIVE" || ! -f "$ARCHIVE/Info.plist" ]]; then
    echo "error: build report points to a missing archive: $ARCHIVE" >&2
    exit 1
fi
if [[ ! -d "$APP" || ! -f "$APP/Info.plist" ]]; then
    echo "error: build report points to a missing archived application: $APP" >&2
    exit 1
fi
if [[ "$SIGNED_EXPORT" != "true" || "$SIGNING_STYLE" != "automatic" ]]; then
    echo "error: validation requires an automatically signed archive" >&2
    echo "Rebuild with IOS_DEMO_SIGNING=automatic and IOS_DEMO_ALLOW_PROVISIONING_UPDATES=1." >&2
    exit 1
fi

ARCHIVE_TEAM="$(plutil -extract ApplicationProperties.Team raw -o - "$ARCHIVE/Info.plist" 2>/dev/null || true)"
ARCHIVE_BUNDLE_ID="$(plutil -extract ApplicationProperties.CFBundleIdentifier raw -o - "$ARCHIVE/Info.plist" 2>/dev/null || true)"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")"
if [[ -z "$ARCHIVE_TEAM" ]]; then
    echo "error: archive does not record a signing team" >&2
    exit 1
fi
if [[ "$ARCHIVE_TEAM" != "$TEAM_ID" ]]; then
    echo "error: archive team $ARCHIVE_TEAM does not match IOS_DEMO_TEAM_ID=$TEAM_ID" >&2
    exit 1
fi
if [[ "$ARCHIVE_BUNDLE_ID" != "$BUNDLE_ID" || "$APP_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "error: archive, application, and build report bundle identifiers do not match" >&2
    exit 1
fi
if [[ ! -f "$APP/embedded.mobileprovision" ]]; then
    echo "error: archived application does not contain an embedded provisioning profile" >&2
    exit 1
fi
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
    echo "error: archived application does not have a valid local code signature" >&2
    exit 1
fi

mkdir -p "$RUNTIME_ROOT" "$VALIDATION_ROOT"
rm -f "$OPTIONS_PLIST"
plutil -create xml1 "$OPTIONS_PLIST"
plutil -insert destination -string upload "$OPTIONS_PLIST"
plutil -insert method -string validation "$OPTIONS_PLIST"
plutil -insert signingStyle -string automatic "$OPTIONS_PLIST"
plutil -insert teamID -string "$TEAM_ID" "$OPTIONS_PLIST"
plutil -insert manageAppVersionAndBuildNumber -bool false "$OPTIONS_PLIST"
plutil -insert stripSwiftSymbols -bool true "$OPTIONS_PLIST"
plutil -insert uploadSymbols -bool true "$OPTIONS_PLIST"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RUN_ROOT="$VALIDATION_ROOT/$RUN_ID"
EXPORT_PATH="$RUN_ROOT/Export"
LOG_PATH="$RUN_ROOT/xcodebuild.log"
SUCCESS_MARKER="$RUN_ROOT/VALIDATION_SUCCEEDED"
LATEST_SUCCESS="$VALIDATION_ROOT/LATEST_SUCCESS"
mkdir -p "$EXPORT_PATH"
rm -f "$LATEST_SUCCESS"

echo "Validating $BUNDLE_ID from $ARCHIVE"
echo "Team: $TEAM_ID"
echo "Xcode options: $OPTIONS_PLIST"
echo "Validation log: $LOG_PATH"
echo

if /usr/bin/xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$OPTIONS_PLIST" \
    -allowProvisioningUpdates \
    2>&1 | tee "$LOG_PATH"; then
    VALIDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'APP_STORE_VALIDATION_SUCCEEDED\nbundleIdentifier=%s\nteamID=%s\nvalidatedAt=%s\narchive=%s\nlog=%s\n' \
        "$BUNDLE_ID" "$TEAM_ID" "$VALIDATED_AT" "$ARCHIVE" "$LOG_PATH" \
        | tee "$SUCCESS_MARKER" "$LATEST_SUCCESS" \
        | tee -a "$LOG_PATH"
    echo
    echo "Validation succeeded. Marker: $SUCCESS_MARKER"
else
    STATUS=$?
    echo >&2
    echo "error: App Store validation failed; no success marker was written" >&2
    echo "Validation log: $LOG_PATH" >&2
    echo "Confirm that App Store Connect contains an app record for $BUNDLE_ID." >&2
    exit "$STATUS"
fi

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONFIGURATION="${IOS_DEMO_CONFIGURATION:-release}"
OUTPUT_DIR="$ROOT/.build/plugins/outputs/custom-product-ios-app/IOSDemoIPA/destination/arm64-apple-ios17.0/$BUILD_CONFIGURATION/IOSAppBuilder/outputs"
REPORT="$OUTPUT_DIR/IOSDemoIPA-build-report.json"

if [[ ! -f "$REPORT" ]]; then
    echo "error: build the demo first with Scripts/build-demo.sh" >&2
    exit 1
fi

IPA="$(plutil -extract outputIPA raw -o - "$REPORT")"
ARCHIVE="$(plutil -extract outputArchive raw -o - "$REPORT")"
APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "error: archive does not contain an application" >&2
    exit 1
fi
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Info.plist")"
SIGNED_EXPORT="$(plutil -extract signedExport raw -o - "$REPORT")"

fail() {
    echo "error: $*" >&2
    exit 1
}

profile_application_identifier_matches() {
    local profile_team="$1"
    local profile_application_identifier="$2"
    local bundle_identifier="$3"
    local team_prefix="${profile_team}."
    local bundle_pattern
    local pattern_length
    local wildcard_prefix

    if [[ "$profile_application_identifier" != "$team_prefix"* ]]; then
        return 1
    fi

    bundle_pattern="${profile_application_identifier#"$team_prefix"}"
    if [[ "$bundle_pattern" == "$bundle_identifier" || "$bundle_pattern" == "*" ]]; then
        return 0
    fi

    # Apple wildcard profiles may end in `.*` (for example,
    # `TEAMID.com.example.*`). Do not treat an asterisk in any other position
    # as a wildcard.
    pattern_length="${#bundle_pattern}"
    if (( pattern_length < 2 )) ||
       [[ "${bundle_pattern:$((pattern_length - 2))}" != ".*" ]]; then
        return 1
    fi
    wildcard_prefix="${bundle_pattern:0:$((pattern_length - 1))}"
    if [[ "${wildcard_prefix//\*/}" != "$wildcard_prefix" ]]; then
        return 1
    fi
    [[ "${bundle_identifier:0:${#wildcard_prefix}}" == "$wildcard_prefix" ]] &&
        (( ${#bundle_identifier} > ${#wildcard_prefix} ))
}

inspect_signing() {
    local inspected_app="$1"
    local label="$2"
    local inspection_directory="$3"
    local signing_details
    local signing_identifier
    local signing_team
    local bundle_identifier
    local profile
    local profile_plist
    local profile_name
    local profile_uuid
    local profile_team_name
    local profile_team
    local profile_application_identifier
    local profile_get_task_allow
    local profile_expiration
    local profile_expiration_epoch
    local signed_entitlements
    local signed_application_identifier
    local signed_entitlements_team
    local certificate_prefix
    local leaf_certificate
    local leaf_fingerprint
    local profile_certificate_base64
    local profile_certificate_der
    local profile_certificate_fingerprint
    local profile_certificate_count=0
    local certificate_matches_profile=false

    echo "$label"
    if ! codesign --verify --deep --strict --verbose=2 "$inspected_app"; then
        if [[ "$SIGNED_EXPORT" == "true" ]]; then
            fail "$label is marked as a signed export but its code signature is invalid"
        fi
        echo "Not signed for installation (expected for unsigned mode)."
        return 0
    fi

    signing_details="$(codesign -dvvv "$inspected_app" 2>&1)"
    signing_identifier="$(awk -F= '/^Identifier=/{print substr($0, index($0, "=") + 1); exit}' <<< "$signing_details")"
    signing_team="$(awk -F= '/^TeamIdentifier=/{print substr($0, index($0, "=") + 1); exit}' <<< "$signing_details")"
    bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$inspected_app/Info.plist")"

    if [[ "$signing_identifier" != "$bundle_identifier" ]]; then
        fail "$label code-signing identifier '$signing_identifier' does not match CFBundleIdentifier '$bundle_identifier'"
    fi

    echo "  Identifier: $signing_identifier"
    echo "  TeamIdentifier: ${signing_team:-not set}"
    echo "  Authority chain:"
    if ! awk -F= '/^Authority=/{print "    - " substr($0, index($0, "=") + 1); found=1} END{exit !found}' \
        <<< "$signing_details"
    then
        echo "    - ad hoc"
    fi

    profile="$inspected_app/embedded.mobileprovision"
    if [[ ! -f "$profile" ]]; then
        if [[ "$SIGNED_EXPORT" == "true" ]]; then
            fail "$label is marked as a signed export but has no embedded.mobileprovision"
        fi
        echo "  Embedded provisioning profile: none (local ad-hoc/non-installable signature)"
        return 0
    fi
    if [[ -z "$signing_team" || "$signing_team" == "not set" ]]; then
        fail "$label embeds a provisioning profile but its code signature has no TeamIdentifier"
    fi

    mkdir -p "$inspection_directory"
    profile_plist="$inspection_directory/embedded-profile.plist"
    if ! security cms -D -i "$profile" > "$profile_plist"; then
        fail "$label embedded.mobileprovision is not a readable CMS provisioning profile"
    fi
    plutil -lint "$profile_plist"

    profile_name="$(plutil -extract Name raw -o - "$profile_plist")"
    profile_uuid="$(plutil -extract UUID raw -o - "$profile_plist")"
    profile_team_name="$(plutil -extract TeamName raw -o - "$profile_plist")"
    profile_team="$(plutil -extract TeamIdentifier.0 raw -o - "$profile_plist")"
    profile_application_identifier="$(plutil -extract Entitlements.application-identifier raw -o - "$profile_plist")"
    profile_get_task_allow="$(plutil -extract Entitlements.get-task-allow raw -o - "$profile_plist")"
    profile_expiration="$(plutil -extract ExpirationDate raw -o - "$profile_plist")"

    echo "  Provisioning profile:"
    echo "    Name: $profile_name"
    echo "    UUID: $profile_uuid"
    echo "    Team: $profile_team_name ($profile_team)"
    echo "    Application identifier: $profile_application_identifier"
    echo "    Get task allow: $profile_get_task_allow"
    echo "    Expiration: $profile_expiration"

    if [[ "$profile_team" != "$signing_team" ]]; then
        fail "$label profile team '$profile_team' does not match code-signing team '$signing_team'"
    fi
    if ! profile_application_identifier_matches \
        "$profile_team" "$profile_application_identifier" "$bundle_identifier"
    then
        fail "$label profile application identifier '$profile_application_identifier' does not allow '${profile_team}.${bundle_identifier}'"
    fi
    if ! profile_expiration_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$profile_expiration" '+%s' 2>/dev/null)"; then
        fail "$label profile expiration '$profile_expiration' is not in the expected UTC format"
    fi
    if (( profile_expiration_epoch <= $(date -u '+%s') )); then
        fail "$label provisioning profile expired at $profile_expiration"
    fi

    signed_entitlements="$inspection_directory/signed-entitlements.plist"
    if ! codesign -d --entitlements :- "$inspected_app" > "$signed_entitlements" 2>/dev/null; then
        fail "$label signed entitlements could not be read"
    fi
    plutil -lint "$signed_entitlements"
    signed_application_identifier="$(plutil -extract application-identifier raw -o - "$signed_entitlements")"
    signed_entitlements_team="$(plutil -extract 'com\.apple\.developer\.team-identifier' raw -o - "$signed_entitlements")"
    if [[ "$signed_application_identifier" != "${profile_team}.${bundle_identifier}" ]]; then
        fail "$label signed application identifier '$signed_application_identifier' does not equal '${profile_team}.${bundle_identifier}'"
    fi
    if [[ "$signed_entitlements_team" != "$profile_team" ]]; then
        fail "$label signed-entitlements team '$signed_entitlements_team' does not match profile team '$profile_team'"
    fi

    certificate_prefix="$inspection_directory/signing-certificate"
    if ! codesign -d --extract-certificates="$certificate_prefix" "$inspected_app" >/dev/null 2>&1; then
        fail "$label signing certificate chain could not be extracted"
    fi
    leaf_certificate="${certificate_prefix}0"
    if [[ ! -f "$leaf_certificate" ]]; then
        fail "$label signing certificate chain has no leaf certificate"
    fi
    leaf_fingerprint="$(openssl x509 -inform DER -in "$leaf_certificate" -noout -fingerprint -sha256 | sed 's/^[^=]*=//' | tr -d ':')"

    while true; do
        profile_certificate_base64="$inspection_directory/profile-certificate-${profile_certificate_count}.base64"
        profile_certificate_der="$inspection_directory/profile-certificate-${profile_certificate_count}.der"
        if ! plutil -extract "DeveloperCertificates.${profile_certificate_count}" raw \
            -o "$profile_certificate_base64" "$profile_plist" 2>/dev/null
        then
            rm -f "$profile_certificate_base64"
            break
        fi
        if ! openssl base64 -d -A -in "$profile_certificate_base64" -out "$profile_certificate_der"; then
            fail "$label profile DeveloperCertificates.${profile_certificate_count} is not valid base64 DER"
        fi
        profile_certificate_fingerprint="$(openssl x509 -inform DER -in "$profile_certificate_der" -noout -fingerprint -sha256 | sed 's/^[^=]*=//' | tr -d ':')"
        if [[ "$profile_certificate_fingerprint" == "$leaf_fingerprint" ]]; then
            certificate_matches_profile=true
        fi
        profile_certificate_count=$((profile_certificate_count + 1))
    done
    if (( profile_certificate_count == 0 )); then
        fail "$label profile contains no DeveloperCertificates"
    fi
    if [[ "$certificate_matches_profile" != "true" ]]; then
        fail "$label leaf signing certificate is not present in the profile DeveloperCertificates"
    fi

    echo "  Leaf signing certificate SHA-256: $leaf_fingerprint"
    echo "  Certificate/profile match: yes ($profile_certificate_count profile certificates)"
    echo "  Signing metadata validation: passed"
}

echo "Executable"
file "$APP/$EXECUTABLE_NAME"
xcrun nm -gU "$APP/$EXECUTABLE_NAME" | grep ' _main$'
xcrun vtool -show-build "$APP/$EXECUTABLE_NAME"

echo
echo "Archive integrity"
plutil -lint "$ARCHIVE/Info.plist" "$APP/Info.plist"
unzip -t "$IPA"
APP_UUID="$(dwarfdump --uuid "$APP/$EXECUTABLE_NAME" | awk '{print $2}')"
DSYM_UUID="$(dwarfdump --uuid "$ARCHIVE/dSYMs/$EXECUTABLE_NAME.app.dSYM" | awk '{print $2}')"
if [[ "$APP_UUID" != "$DSYM_UUID" ]]; then
    echo "error: app and dSYM UUIDs differ" >&2
    exit 1
fi
echo "Matching app/dSYM UUID: $APP_UUID"

echo
echo "Compiled target assets"
if [[ ! -f "$APP/Assets.car" ]]; then
    echo "error: generated application does not contain Assets.car" >&2
    exit 1
fi
ASSET_INFO="$(xcrun assetutil --info "$APP/Assets.car")"
grep -q '"Name" : "AppIcon"' <<< "$ASSET_INFO"
grep -q '"Name" : "AccentColor"' <<< "$ASSET_INFO"
plutil -extract CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName raw -o - "$APP/Info.plist"
echo "$ASSET_INFO"

echo
echo "Bundle metadata"
plutil -p "$APP/Info.plist"

echo
echo "IPA contents"
unzip -l "$IPA"

echo
echo "Signing"
SIGNING_TMP="$(mktemp -d)"
trap 'rm -rf "$SIGNING_TMP"' EXIT
inspect_signing "$APP" "Archive application" "$SIGNING_TMP/archive"

mkdir -p "$SIGNING_TMP/ipa"
unzip -q "$IPA" -d "$SIGNING_TMP/ipa"
IPA_APP="$(find "$SIGNING_TMP/ipa/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$IPA_APP" || ! -d "$IPA_APP" ]]; then
    fail "IPA does not contain a Payload application"
fi
inspect_signing "$IPA_APP" "Exported IPA application" "$SIGNING_TMP/exported-ipa"

echo
echo "Build report"
cat "$REPORT"

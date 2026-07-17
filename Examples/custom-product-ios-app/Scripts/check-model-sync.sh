#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFINITION="$ROOT/IOSAppProductTypes/Sources/IOSAppProductTypes/IOSApplicationConfiguration.swift"
PLUGIN="$ROOT/IOSAppSupport/Plugins/IOSAppBuilder/IOSApplicationConfiguration.swift"
PACKAGER="$ROOT/IOSAppSupport/Sources/IOSAppPackager/IOSApplicationConfiguration.swift"

diff -u \
    <(sed '/import PackageDescription/d; /@available(_PackageDescription, introduced: 6.3)/d' "$DEFINITION") \
    "$PLUGIN"
diff -u "$PLUGIN" "$PACKAGER"

echo "The definition library, planning plug-in, and host packager share the same Codable schema."

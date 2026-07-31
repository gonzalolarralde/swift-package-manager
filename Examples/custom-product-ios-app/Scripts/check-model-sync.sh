#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN="$ROOT/IOSAppSupport/Plugins/IOSAppBuilder/IOSApplicationConfiguration.swift"
PACKAGER="$ROOT/IOSAppSupport/Sources/IOSAppPackager/IOSApplicationConfiguration.swift"

diff -u "$PLUGIN" "$PACKAGER"

echo "The planning plug-in and host packager share the same Codable schema."

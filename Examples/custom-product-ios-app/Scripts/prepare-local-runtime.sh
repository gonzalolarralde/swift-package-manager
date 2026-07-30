#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTPM_ROOT="${1:-$(cd "$DEMO_ROOT/../.." && pwd)}"
BUILD_PRODUCTS="$SWIFTPM_ROOT/.build/debug"
RUNTIME_ROOT="$DEMO_ROOT/.demo-runtime/SwiftPMRuntime"

package_description_module="$BUILD_PRODUCTS/Modules/PackageDescription.swiftmodule"
package_plugin_module="$BUILD_PRODUCTS/Modules/PackagePlugin.swiftmodule"
if [[ ! -e "$package_description_module" ]]; then
    package_description_module="$BUILD_PRODUCTS/PackageDescription.swiftmodule"
fi
if [[ ! -e "$package_plugin_module" ]]; then
    package_plugin_module="$BUILD_PRODUCTS/PackagePlugin.swiftmodule"
fi

package_description_library="$BUILD_PRODUCTS/libPackageDescription.dylib"
package_plugin_library="$BUILD_PRODUCTS/libPackagePlugin.dylib"
if [[ ! -f "$package_description_library" ]] ||
   [[ ! -f "$package_plugin_library" ]] ||
   [[ ! -e "$package_description_module" ]] ||
   [[ ! -e "$package_plugin_module" ]]; then
    echo "error: the fork's PackageDescription and PackagePlugin runtimes are not built" >&2
    echo "Run 'swift build' in $SWIFTPM_ROOT first." >&2
    exit 1
fi

mkdir -p "$RUNTIME_ROOT/ManifestAPI" "$RUNTIME_ROOT/PluginAPI"
ln -sfn "$package_description_library" \
    "$RUNTIME_ROOT/ManifestAPI/libPackageDescription.dylib"
ln -sfn "$package_description_module" \
    "$RUNTIME_ROOT/ManifestAPI/PackageDescription.swiftmodule"
ln -sfn "$package_plugin_library" \
    "$RUNTIME_ROOT/PluginAPI/libPackagePlugin.dylib"
ln -sfn "$package_plugin_module" \
    "$RUNTIME_ROOT/PluginAPI/PackagePlugin.swiftmodule"

echo "$RUNTIME_ROOT"

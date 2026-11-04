#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-app.sh [debug|release]" >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
swift_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${swift_options[@]}" -c "$configuration"
binary_directory="$(swift build "${swift_options[@]}" -c "$configuration" --show-bin-path)"
app="$PWD/dist/StatusNav.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_directory/StatusNav" "$app/Contents/MacOS/StatusNav"
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built: $app"

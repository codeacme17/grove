#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

GROVE_UNIVERSAL=1 bash scripts/build-app.sh release
app="dist/Grove.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="Grove-$version-macOS-universal.zip"

lipo "$app/Contents/MacOS/Grove" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(
    cd dist
    shasum -a 256 "$archive" > SHA256SUMS
)
echo "Release assets: $PWD/dist/$archive and $PWD/dist/SHA256SUMS"

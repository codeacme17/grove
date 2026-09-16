#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    echo "Usage: bash scripts/build-app.sh [release|debug]" >&2
    exit 1
fi
app="dist/Grove.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ "${GROVE_UNIVERSAL:-0}" == 1 ]]; then
    binaries=()
    for architecture in arm64 x86_64; do
        triple="$architecture-apple-macosx14.0"
        swift build -c "$configuration" --triple "$triple"
        binary_dir="$(swift build -c "$configuration" --triple "$triple" --show-bin-path)"
        binaries+=("$binary_dir/Grove")
    done
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Grove"
else
    swift build -c "$configuration"
    binary_dir="$(swift build -c "$configuration" --show-bin-path)"
    cp "$binary_dir/Grove" "$app/Contents/MacOS/Grove"
fi
ditto "$binary_dir/Grove_Grove.bundle" "$app/Contents/Resources/Grove_Grove.bundle"
cp ../../LICENSE "$app/Contents/Resources/LICENSE"
bash scripts/build-icon.sh "$app/Contents/Resources/Grove.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Grove</string>
<key>CFBundleIdentifier</key><string>com.codeacme17.grove</string>
<key>CFBundleName</key><string>Grove</string>
<key>CFBundleIconFile</key><string>Grove.icns</string>
<key>CFBundleDisplayName</key><string>Grove</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
signing_identity="${GROVE_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == - ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --sign "$signing_identity" --options runtime --timestamp "$app"
fi
echo "Built $PWD/$app"

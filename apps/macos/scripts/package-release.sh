#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

notary_profile="${GROVE_NOTARY_PROFILE:-}"
signing_identity="${GROVE_SIGNING_IDENTITY:--}"
if [[ -n "$notary_profile" && "$signing_identity" == - ]]; then
    echo "GROVE_NOTARY_PROFILE requires GROVE_SIGNING_IDENTITY (Developer ID Application)." >&2
    exit 1
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/grove-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

notarize() {
    local artifact="$1" report="$2" status
    echo "Submitting $(basename "$artifact") to Apple for notarization…"
    xcrun notarytool submit "$artifact" --keychain-profile "$notary_profile" \
        --wait --output-format plist > "$report"
    status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$report")"
    if [[ "$status" != Accepted ]]; then
        echo "Notarization status: $status. Submission details: $PWD/$report" >&2
        exit 1
    fi
}

GROVE_UNIVERSAL=1 bash scripts/build-app.sh release
app="dist/Grove.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="Grove-$version-macOS-universal.zip"
disk_image="Grove-$version-macOS-universal.dmg"

lipo "$app/Contents/MacOS/Grove" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$app"

if [[ "$signing_identity" != - ]]; then
    signature="$(codesign -dvv "$app" 2>&1)"
    if [[ "$signature" != *"Authority=Developer ID Application:"* ]]; then
        echo "Release signing requires a Developer ID Application certificate." >&2
        exit 1
    fi
fi

if [[ -n "$notary_profile" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/notarization.zip"
    notarize "$staging/notarization.zip" "dist/Grove-$version-app-notarization.plist"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
fi

bash scripts/build-dmg.sh "$app" "dist/$disk_image"

if [[ "$signing_identity" != - ]]; then
    codesign --force --sign "$signing_identity" --timestamp "dist/$disk_image"
    codesign --verify --strict "dist/$disk_image"
fi
if [[ -n "$notary_profile" ]]; then
    notarize "dist/$disk_image" "dist/Grove-$version-dmg-notarization.plist"
    xcrun stapler staple "dist/$disk_image"
    xcrun stapler validate "dist/$disk_image"
fi

hdiutil verify "dist/$disk_image"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(
    cd dist
    shasum -a 256 "$disk_image" "$archive" > SHA256SUMS
)
echo "Release assets: $PWD/dist/$disk_image, $PWD/dist/$archive, and $PWD/dist/SHA256SUMS"
if [[ -z "$notary_profile" ]]; then
    echo "This build is not notarized. Configure GROVE_SIGNING_IDENTITY and GROVE_NOTARY_PROFILE for notarized releases."
fi

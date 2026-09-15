#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-dist/Grove.icns}"
appearance="${2:-light}"
case "$appearance" in
    light) source="Sources/Grove/Resources/AppIcon.png" ;;
    dark) source="Sources/Grove/Resources/AppIconDark.png" ;;
    *) echo "Usage: bash scripts/build-icon.sh [output.icns] [light|dark]" >&2; exit 1 ;;
esac
icon_work_dir="$(mktemp -d)"
trap 'rm -rf "$icon_work_dir"' EXIT
iconset="$icon_work_dir/Grove.iconset"
mkdir -p "$iconset" "$(dirname "$output")"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$source" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$output"
echo "Built $output"

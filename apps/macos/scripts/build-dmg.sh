#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# != 2 ]]; then
    echo "Usage: bash scripts/build-dmg.sh app-path output.dmg" >&2
    exit 1
fi
app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$(dirname "$2")"
output="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
tools_dir="$PWD/.build/dmg-tools"
if [[ ! -x "$tools_dir/bin/python3" ]]; then
    python3 -m venv "$tools_dir"
fi
if ! cmp -s scripts/dmg-requirements.txt "$tools_dir/requirements.txt"; then
    "$tools_dir/bin/python3" -m pip install --disable-pip-version-check -r scripts/dmg-requirements.txt
    cp scripts/dmg-requirements.txt "$tools_dir/requirements.txt"
fi

artwork_dir="$(mktemp -d "${TMPDIR:-/tmp}/grove-dmg-artwork.XXXXXX")"
trap 'rm -rf "$artwork_dir"' EXIT
swift scripts/dmg-background.swift "$artwork_dir/background.tiff"
swiftc scripts/dmg-bookmark.swift -o "$artwork_dir/bookmark"
"$tools_dir/bin/python3" scripts/build-dmg.py \
    "$app" "$artwork_dir/background.tiff" "$artwork_dir/bookmark" "$output"
echo "Built branded installer: $output"

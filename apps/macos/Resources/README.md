# macOS app icon

`AppIcon.png` is the 1024 × 1024 source for Grove's macOS application icon.
It contains the approved abstract black mark on an ivory rounded-square tile,
with transparency around the tile. The mark has no lettering.

## Build

The app build invokes `scripts/build-icon.sh` automatically, before signing.
The resulting `Grove.icns` is copied into the app bundle's `Contents/Resources`
and selected by `CFBundleIconFile` in `Contents/Info.plist`.

To export only the icon, run from `apps/macos`:

```sh
bash scripts/build-icon.sh
```

This writes `dist/Grove.icns`. An optional first argument overrides the output
path, interpreted relative to `apps/macos` unless absolute.

The script uses the built-in macOS `sips` and `iconutil` tools to create 16, 32,
128, 256, and 512 point representations at both 1× and 2× resolution. Intermediate
PNG files are created in a temporary directory and removed after the build.

## Updating

Replace `AppIcon.png` with a square 1024 × 1024 PNG that retains transparent
outer margins, then rebuild the app. Keep the original mark's proportions and
avoid adding text at small icon sizes. Generated iconsets and app bundles do
not need to be committed. These resources belong to the macOS app; a future
Windows icon can be packaged independently.

## Verification

After building, inspect `CFBundleIconFile`, extract the ICNS with
`iconutil --convert iconset`, and check the standard and Retina sizes.
Verify the app signature after changing bundle resources. Launch the rebuilt
app to inspect its Dock icon; a previously running copy may retain its old icon.

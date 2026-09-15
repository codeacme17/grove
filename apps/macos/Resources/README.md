# macOS app icon

`../Sources/Grove/Resources/AppIcon.png` is the 1024 × 1024 source for Grove's macOS application icon.
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

Replace `Sources/Grove/Resources/AppIcon.png` with a square 1024 × 1024 PNG that retains transparent
outer margins, then rebuild the app. Keep the original mark's proportions and
avoid adding text at small icon sizes. Generated iconsets and app bundles do
not need to be committed. These resources belong to the macOS app; a future
Windows icon can be packaged independently.

## Verification

After building, inspect `CFBundleIconFile`, extract the ICNS with
`iconutil --convert iconset`, and check the standard and Retina sizes.
Verify the app signature after changing bundle resources. Launch the rebuilt
app to inspect its Dock icon; a previously running copy may retain its old icon.

## Dark appearance and application branding

`Sources/Grove/Resources/AppIconDark.png` is the charcoal-and-ivory dark variant.
Both PNGs are packaged by SwiftPM into `Grove_Grove.bundle`; the app build copies
that bundle into `Contents/Resources` before signing. `GroveBrand` loads this
packaged bundle first and falls back to `Bundle.module` for SwiftPM development.

The sidebar, welcome screen, and empty worktree state use `GroveLogo`. Its artwork
tracks the SwiftUI color scheme. The running application icon also tracks this
scheme through `NSApplication.applicationIconImage`. The About command supplies the
current application icon explicitly to the standard About panel. Finder retains the default light ICNS; this implementation
does not advertise system-managed icon appearance variants or change Finder icons.

Both repository and macOS README headers use a `picture` element with
`prefers-color-scheme: dark`, falling back to the light image in other renderers.

To export the dark ICNS from `apps/macos`:

```sh
bash scripts/build-icon.sh dist/Grove-Dark.icns dark
```

When verifying a packaged build, launch a copy outside the checkout and confirm
that both logos load without relying on the SwiftPM build directory. Check the
welcome screen and project sidebar in both appearances, including a live switch.

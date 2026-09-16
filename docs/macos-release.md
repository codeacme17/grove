# macOS releases

## Local packaging

Requires macOS, the Swift toolchain, and Python 3.9 or newer. On the first run, the packaging script installs pinned DMG build tools into `apps/macos/.build/dmg-tools`; this requires network access. These tools are only used for packaging and are not bundled with Grove.

From the repository root:

```sh
make release-macos
```

The command compiles Apple Silicon and Intel release binaries and produces these files in `apps/macos/dist`:

- `Grove-<version>-macOS-universal.dmg`: Grove.app and an Applications shortcut, with a branded drag-to-install window and Grove volume icon.
- `Grove-<version>-macOS-universal.zip`: the standalone app bundle.
- `SHA256SUMS`: checksums for both downloads.

Without signing configuration, the app uses an ad-hoc signature and is not notarized. Packaging alone does not satisfy Gatekeeper's distribution requirements.

### Installer appearance

`apps/macos/scripts/dmg-background.swift` draws the installation instructions and arrow at standard and Retina resolutions. `dmg-settings.py` defines the Finder window size and icon positions. The volume icon uses the app's existing `Grove.icns`.

`build-dmg.py` writes the Finder layout without UI automation and uses a native macOS bookmark for the background. To preview a layout change using an existing app bundle, run from `apps/macos`:

```sh
bash scripts/build-dmg.sh dist/Grove.app dist/Grove-preview.dmg
```

The preview container is unsigned. Run the full release pipeline after changing the layout so the final DMG is signed and notarized again.

## Developer ID and notarization

Install a **Developer ID Application** certificate and its matching private key in the local keychain. The Apple Developer Program Account Holder can [create this certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) using a [certificate signing request](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request) generated on the same Mac.

List available signing identities:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials using Apple's interactive prompt:

```sh
xcrun notarytool store-credentials grove-notary
```

Use the developer Apple Account, Team ID, and an [app-specific password](https://support.apple.com/en-us/102654), or an appropriate App Store Connect API key. Credentials remain in the keychain; do not add passwords, private keys, or certificate exports to the repository.

Build with the certificate's name or SHA-1 fingerprint and the saved profile:

```sh
GROVE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
GROVE_NOTARY_PROFILE="grove-notary" \
make release-macos
```

The pipeline:

1. Signs the universal app with hardened runtime and a secure timestamp.
2. Submits the app to Apple, waits for acceptance, and staples and validates its ticket.
3. Checks the app with Gatekeeper, creates the DMG, verifies that packaging preserved the bundled app's signature, and signs the DMG.
4. Submits the DMG to Apple, waits for acceptance, and staples and validates its ticket.
5. Verifies the disk image and creates the final ZIP and checksums from the stapled artifacts.

Both Apple submission reports are saved in `apps/macos/dist` as notarization plist files. Failed signing or notarization stops the command. Inspect the report's submission ID with `xcrun notarytool log <id> --keychain-profile grove-notary` if Apple rejects a submission. Only upload artifacts after the command completes successfully.

## Publishing

Promote tested changes from `dev` to `main` through a pull request, then tag the production commit. Upload the DMG, optional ZIP, and matching `SHA256SUMS` to the GitHub release. Verify the uploaded digests before announcing the release, and describe the actual signing and notarization status in its notes.

When a release has both assets listed in `SHA256SUMS`, verify one downloaded artifact without requiring the other:

```sh
shasum -a 256 "Grove-<version>-macOS-universal.dmg"
```

Compare that output with the DMG entry in `SHA256SUMS`. Download both artifacts to use `shasum -a 256 -c SHA256SUMS` without missing-file errors.

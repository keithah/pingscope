# Release Builds (Signed + Notarized)

This repo builds a menu-bar macOS app from SwiftPM and an Xcode app bundle with the WidgetKit extension. Public non-App-Store releases are Developer ID signed, notarized, stapled, and published on GitHub with a Sparkle appcast.

## Prerequisites

- Xcode command line tools installed (`xcode-select -p`)
- Developer ID certificates installed in Keychain:
  - Developer ID Application
  - Developer ID Installer (optional, only needed for `.pkg`)
- Notarytool keychain profile stored (recommended):

```bash
xcrun notarytool store-credentials "NotarytoolProfile" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```
- Sparkle EdDSA key stored in Keychain. PingScope uses account `pingscope-ed25519`:

```bash
find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys' \
  -type f -perm -111 | sort | tail -n 1

<generate_keys_path> --account pingscope-ed25519
```

Only commit the printed `SUPublicEDKey`. Keep the private key in Keychain.

## Build a release app bundle

```bash
scripts/build-xcode-app-bundle.sh release /private/tmp/artifacts developer-id
```

This prints the path to the resulting `.app`.

## Sign + notarize

```bash
deploy/sign-notarize.sh \
  --version 1.2.3 \
  --app "/private/tmp/artifacts/PingScope.app" \
  --sign-app "Developer ID Application: <Your Name> (<TEAMID>)" \
  --notary-profile "NotarytoolProfile"
```

Artifacts land in `/private/tmp/artifacts/PingScope-v<version>/`:
- `PingScope.app` (signed)
- `PingScope-v<version>.dmg` (signed + notarized + stapled)
- `checksums-v<version>.txt`

## Generate Sparkle appcast

```bash
scripts/appcast.sh \
  --release-dir "/private/tmp/artifacts/PingScope-v1.2.3/updates" \
  --dmg "/private/tmp/artifacts/PingScope-v1.2.3/PingScope-v1.2.3.dmg" \
  --download-url-prefix "https://github.com/keithah/pingscope/releases/download/v1.2.3"
```

## Publish GitHub release

```bash
scripts/release-github.sh --version 1.2.3 --release-notes RELEASE_NOTES.md
```

The release driver checks GitHub auth, the notary profile, the Developer ID Application certificate, and the Sparkle private key before publishing.

## Notes

- This flow targets Developer ID distribution (outside the Mac App Store).
- App Store builds use App Store updates. The in-app Sparkle update UI is hidden when `APPSTORE` is defined.

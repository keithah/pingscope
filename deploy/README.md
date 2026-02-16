# Release Builds (Signed + Notarized)

This repo builds a menu-bar macOS app from SwiftPM. For distribution builds (Developer ID signed + notarized), we build a real `.app` bundle, sign it, notarize it, and staple the ticket.

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

## Build a release app bundle

```bash
scripts/build-app-bundle.sh release /private/tmp/artifacts
```

This prints the path to the resulting `.app`.

## Sign + notarize (DMG and PKG)

```bash
deploy/sign-notarize.sh \
  --version 1.2.3 \
  --app " /private/tmp/artifacts/PingScope.app" \
  --sign-app "Developer ID Application: <Your Name> (<TEAMID>)" \
  --sign-installer "Developer ID Installer: <Your Name> (<TEAMID>)" \
  --notary-profile "NotarytoolProfile"
```

Artifacts land in `/private/tmp/artifacts/PingScope-v<version>/`:
- `PingScope.app` (signed)
- `PingScope-v<version>.dmg` (signed + notarized + stapled)
- `PingScope-v<version>.pkg` (signed + notarized + stapled)
- `checksums-v<version>.txt`

## Notes

- This flow targets Developer ID distribution (outside the Mac App Store).
- App Store submission requires an Xcode app target + sandboxing + provisioning profiles. We can add that later if needed.

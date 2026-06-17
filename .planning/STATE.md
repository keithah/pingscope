# Project State

## Current Position

PingScope `0.1.0` is the first public release of the fresh rebuild.

- `main`: current development branch
- Release tag: `v0.1.0`
- License: AGPLv3
- GitHub release: published with DMG, appcast, checksums, and Sparkle release notes
- Current task: repository cleanup after first release

## Validation Baseline

Last full local validation before release:

- `swift test`: passed, 38 tests
- `scripts/validate-probes.sh`: TCP, UDP, and ICMP live probes passed
- `scripts/validate-roadmap.sh`: passed
- Developer ID DMG: signed, notarized, stapled, Gatekeeper accepted
- App Store bundle verification: sandbox, network client entitlement, privacy manifest, export compliance passed

## Current Follow-Ups

- Manual install QA from the public GitHub DMG.
- Rebuild/re-upload `0.1.0` assets from the cleaned repository state.
- First Sparkle update validation on `0.1.1`.
- iOS preparation after Mac release cleanup.

## Repo Shape

Keep:

- `Sources/PingScopeCore`
- `Sources/PingScopeApp`
- `PingScopeWidget`
- `Tests/PingScopeFreshTests`
- `Assets.xcassets`
- `Configuration`
- `scripts`
- `deploy`
- `images`

Removed:

- Prior implementation under `Sources/PingScope`
- Prior tests under `Tests/PingScopeTests`
- Old App Store screenshot/metadata package
- Old Fastlane/Xcode Cloud scripts
- Duplicate legacy `widget` target
- Legacy long-form root docs from the previous app

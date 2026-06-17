# Phase 18 Implementation Plan

Goal: make PingScope iOS-friendly without promising continuous iOS background monitoring.

## Completed Slices

- [x] Add platform-neutral monitor session model in `PingScopeCore`.
- [x] Limit initial session durations to `30s` default and `1m` optional.
- [x] Add core tests for duration, remaining time, stale transition, normal completion, and early iOS background expiration.
- [x] Add compile-only `PingScopeiOS` SwiftPM product and target.
- [x] Add iOS SwiftUI shell with `30s`, `1m`, and stop controls.
- [x] Add gated ActivityKit attributes/content state for Live Activity data.
- [x] Make default gateway detection compile on iOS by returning `nil` outside macOS.
- [x] Make ICMP process probing compile on iOS by returning `icmpUnavailable` outside macOS.
- [x] Fix popover settings gear by injecting an explicit settings action from `AppDelegate`.
- [x] Add a real iOS app target with bundle id, signing, local-network usage copy, and App Group selection.
- [x] Add a real iOS Live Activity extension target with ActivityKit widget configuration.
- [x] Implement `LiveMonitorSessionController` for foreground probing and finite background expiration.
- [x] Add shared `PingScope-iOS` scheme for local and Xcode Cloud builds.
- [x] Add iOS app icon slots needed by Xcode validation.
- [x] Add persisted iOS host selection with Cloudflare and Google defaults.
- [x] Add iOS live session graph, latency, countdown, and stats UI.
- [x] Add basic iOS host add/edit/delete sheet for TCP and UDP hosts.
- [x] Add real iOS host interval, timeout, degraded threshold, down-after, and port validation controls.
- [x] Add iOS local recent history for finite session samples.
- [x] Wire iOS scene backgrounding to finite `UIApplication` background task expiration.
- [x] Add iOS validation script and physical-device QA checklist.
- [x] Add repeatable iOS simulator launch/screenshot smoke script.
- [x] Add repeatable physical-device build/install/launch smoke script.
- [x] Auto-start a `30s` monitor session on first iOS app appearance.

## Remaining Slices

- [ ] Run device-only manual QA for Live Activity updates, stale state, local-network permission, and early background expiration.

## Verification Commands

- `swift test`
- `swift build --product PingScopeiOS`
- `xcodebuild -scheme PingScopeiOS -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-AppStore -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
- `scripts/validate-ios.sh`
- `scripts/validate-ios-simulator-smoke.sh`
- `scripts/validate-ios-device-smoke.sh`

## Device QA Status

Physical iPhone smoke passed on `pHADM` (`iPhone17,1`, iOS `26.5`, Developer Mode enabled, wired). The earlier developer disk image mount failure cleared after the phone was unlocked and plugged in. The app builds, installs, launches, and the PingScope app process is visible through `devicectl`.

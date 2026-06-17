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

## Remaining Slices

- [ ] Add device-only manual QA for Live Activity updates, stale state, and early background expiration.
- [ ] Decide whether iOS durable history is in scope or whether the first iOS app remains live-session only.

## Verification Commands

- `swift test`
- `swift build --product PingScopeiOS`
- `xcodebuild -scheme PingScopeiOS -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-AppStore -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- `xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`

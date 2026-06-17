# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-17)

**Core value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.
**Current focus:** Phase 18 - iOS-ready architecture planning and eventual iOS app preparation

## Current Position

Phase: 18 of 19 (iOS-ready architecture)
Plan: not started
Status: Phase 17 widget/history/export roadmap validated locally; Phase 17.1 still requires Apple-side Xcode Cloud/App Store Connect setup for full remote automation.
Last activity: 2026-06-16 — Added automated roadmap validation, Xcode widget-bundle build/install script, widget bundle/shared-data validator, live history export validator, and release workflow wiring for widget-bearing builds.

Progress: [██████████████████░░] 90% (v1.0 + v1.1 complete, v2.0 local roadmap items validated, iOS architecture not started)

## Performance Metrics

**Previous milestones:**
- v1.0: 50 plans across 12 phases (shipped 2026-02-17)
- v1.1: 13 plans across 4 phases (shipped 2026-02-18)
- Combined: 63 plans, ~3.5 hours total execution

**v2.0/v3.0 (current):**
- Phase 17 widget foundation: complete locally with automated validation
- Durable history/export: complete locally with automated validation
- Phase 17.1 Xcode Cloud/Fastlane: repo-side automation present; Apple-side workflow/API setup remains external
- Phase 18 iOS-ready architecture: planned next

**Phase 17 metrics:**
- Plan 17-01: 6min (3 tasks, 5 files modified)
- Plan 17-02: 2.5min (3 tasks, 7 files created)

**Phase 17.1 metrics:**
- Plan 17.1-01: 3min (2 tasks, 5 files created/modified)

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- v1.1: Single codebase for both distributions (App Store + Developer ID) using build configurations
- v1.1: Manual ICNS creation for App Store icons (Xcode asset catalog compilation incomplete)
- v1.0: Use Swift Concurrency over GCD semaphores (eliminates race conditions)
- v1.0: Dual-mode ICMP support (true ICMP when not sandboxed, hidden when sandboxed)
- [Phase 17]: Use Team ID prefix format (6R7S5GA944.group.com.hadm.PingScope) for macOS Sequoia App Groups compatibility
- [Phase 17]: Convert Duration to milliseconds in WidgetDataStore for simpler widget consumption
- [Phase 17]: Implement 15-minute staleness threshold for widget data freshness checks
- [Phase 17]: 10-minute timeline spacing (144 updates/day) well within 40-70 system budget
- [Phase 17]: Status color thresholds: green (<50ms), yellow (50-100ms), red (>100ms or timeout)
- [Phase 17]: Stale data (>15min) shows at 60% opacity with orange warning badge
- [Phase quick-2]: Use reloadAllTimelines() instead of reloadTimelines(ofKind:) to prevent ChronoCoreErrorDomain Code=27 when widget not registered
- [Phase quick-2]: Widget extension inherits AppIcon from main app asset catalog via CFBundleIconFile key
- [Phase 17 completion]: widgetExtension now uses `PingScopeWidget/Info.plist` and the real `PingScopeWidget/` source folder
- [Phase quick-3]: Complete icon set (10 PNG files) required in widget's own asset catalog with filename references in Contents.json for proper ICNS compilation
- [Phase 17.1]: ci_post_clone.sh: removed PlistBuddy/CFBundleVersion manipulation — Xcode Cloud manages build numbers natively via CI_BUILD_NUMBER and MARKETING_VERSION build setting
- [Phase 17.1]: ci_post_xcodebuild.sh: removed ExportOptions.plist writing — Xcode Cloud handles export via workflow configuration, not external plist
- [Phase 17.1]: Release tag pattern ^release/[0-9]+\.[0-9]+\.[0-9]+$ triggers Fastlane submit_review
- [Phase 17.1]: submit_review lane uses deliver with skip_binary_upload:true — binary already uploaded by Xcode Cloud, Fastlane only triggers review submission
- [Phase 17.1]: apple_id omitted from Appfile — all automation uses ASC API key auth via ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_CONTENT env vars

### Pending Todos

- Configure App Store Connect API key and Xcode Cloud workflows outside the repo if remote TestFlight/App Review automation is still desired.
- Start Phase 18 by auditing `PingScopeCore` for iOS-safe APIs and adding a compile-only iOS shell target.

### Blockers/Concerns

- Apple does not expose reliable local script automation for adding widgets to the macOS Widget Gallery. Repo automation validates the widget bundle, entitlements, deep-link data contract, and shared defaults; visual Widget Gallery placement remains release QA.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Remove check for update feature for App Store build and prepare release submission | 2026-02-19 | 7a27384 | [1-remove-check-for-update-feature-for-app-](./quick/1-remove-check-for-update-feature-for-app-/) |
| 2 | Fix widget icon and timeline reload errors | 2026-02-20 | 998dc5b | [2-fix-widget-icon-and-timeline-reload-erro](./quick/2-fix-widget-icon-and-timeline-reload-erro/) |
| 3 | Copy app icons to widget asset catalog for App Store ICNS compliance | 2026-02-20 | 07e4464 | [3-copy-app-icons-to-widget-asset-catalog-f](./quick/3-copy-app-icons-to-widget-asset-catalog-f/) |
| 4 | Add ASSETCATALOG_COMPILER_APPICON_NAME build setting to widget target | 2026-02-20 | e4592ba | [4-add-assetcatalog-compiler-appicon-name-b](./quick/4-add-assetcatalog-compiler-appicon-name-b/) |

### Roadmap Evolution

- v1.0 (Phases 1-12): Complete (shipped 2026-02-17)
- v1.1 (Phases 13-16): Complete (shipped 2026-02-18)
- v2.0 (Phases 17-18): Ready to plan
- Phase 17.1 inserted after Phase 17: Use Xcode Cloud with Fastlane to automate builds (URGENT)

## Session Continuity

Last session: 2026-06-16
Stopped at: Phase 17 local automation complete and validated
Resume file: `.planning/ROADMAP.md`
Next action: Begin Phase 18 by keeping `PingScopeCore` platform-neutral and adding a compile-only iOS app target scaffold.

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-17)

**Core value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.
**Current focus:** Phase 17.1 - Xcode Cloud + Fastlane CI/CD Automation

## Current Position

Phase: 17.1 of 18 (Xcode Cloud + Fastlane CI/CD)
Plan: 2 of 2 (in progress — awaiting human actions)
Status: Phase 17.1 Plan 02 — blocked at Task 1 checkpoint (create ASC API key in App Store Connect)
Last activity: 2026-02-24 — Plan 17.1-02 (Xcode Cloud workflow configuration) started, waiting on human actions

Progress: [████████████████░░░░] 83% (v1.0 + v1.1 complete + 3 v2.0 plans: 66/68 total plans)

## Performance Metrics

**Previous milestones:**
- v1.0: 50 plans across 12 phases (shipped 2026-02-17)
- v1.1: 13 plans across 4 phases (shipped 2026-02-18)
- Combined: 63 plans, ~3.5 hours total execution

**v2.0 (current):**
- Total plans: 5 estimated
- Plans completed: 3
- Phases complete: 1/3 (Phase 17.1 complete, Phase 17 in progress)
- Status: Phase 17.1 complete

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
- [Phase quick-3]: widgetExtension target uses widget/Info.plist (not PingScopeWidget/Info.plist) per INFOPLIST_FILE build setting
- [Phase quick-3]: Complete icon set (10 PNG files) required in widget's own asset catalog with filename references in Contents.json for proper ICNS compilation
- [Phase 17.1]: ci_post_clone.sh: removed PlistBuddy/CFBundleVersion manipulation — Xcode Cloud manages build numbers natively via CI_BUILD_NUMBER and MARKETING_VERSION build setting
- [Phase 17.1]: ci_post_xcodebuild.sh: removed ExportOptions.plist writing — Xcode Cloud handles export via workflow configuration, not external plist
- [Phase 17.1]: Release tag pattern ^release/[0-9]+\.[0-9]+\.[0-9]+$ triggers Fastlane submit_review
- [Phase 17.1]: submit_review lane uses deliver with skip_binary_upload:true — binary already uploaded by Xcode Cloud, Fastlane only triggers review submission
- [Phase 17.1]: apple_id omitted from Appfile — all automation uses ASC API key auth via ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_CONTENT env vars

### Pending Todos

None.

### Blockers/Concerns

None — v2.0 roadmap created with clear phase structure based on research findings.

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

Last session: 2026-02-24
Stopped at: Plan 17.1-02 Task 1 — checkpoint:human-action (Create App Store Connect API key)
Resume file: .planning/phases/17.1-use-xcode-cloud-with-this-and-fastlane-to-automate-builds-and-not-require-me-to-build-it-locally-or-use-xcode-locally/17.1-02-SUMMARY.md
Next action: Human must create ASC API key (https://appstoreconnect.apple.com/access/api) and create two Xcode Cloud workflows in Xcode IDE. See SUMMARY.md for full instructions.

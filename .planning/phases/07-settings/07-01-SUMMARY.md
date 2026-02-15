---
phase: 07-settings
plan: 01
subsystem: ui
tags: [swiftui, appkit, lsuielement, settings, notifications]

requires:
  - phase: 06-notifications-settings
    provides: Settings scene scaffolding + notification preferences infrastructure
provides:
  - Dedicated, single-instance Settings window for a menu-bar (LSUIElement) app
  - Screenshot-matching Settings UI with Reset-to-Defaults behavior
  - Cmd+, and in-app/menu-bar entry points routed through one AppDelegate API
affects: [07-settings]

tech-stack:
  added: [ServiceManagement]
  patterns:
    - Dedicated NSWindowController for Settings (avoid SwiftUI Settings scene flakiness in accessory apps)
    - Preference-store reset APIs + HostStore resetToDefaults

key-files:
  created:
    - Sources/PingScope/Views/Settings/PingMonitorSettingsView.swift
    - Sources/PingScope/Services/StartOnLaunchService.swift
    - scripts/dev-run-app.sh
  modified:
    - Sources/PingScope/App/AppDelegate.swift
    - Sources/PingScope/PingMonitorApp.swift
    - Sources/PingScope/ViewModels/DisplayViewModel.swift
    - Sources/PingScope/Services/NotificationService.swift
    - Info.plist

key-decisions:
  - "Always show Settings via a dedicated NSWindowController for LSUIElement reliability"
  - "Guard notifications when running non-bundled (swift run) to avoid UNUserNotificationCenter crashes"

patterns-established:
  - "Reset APIs: preference stores expose reset() and app delegate aggregates via resetToDefaults()"

duration: 3min
completed: 2026-02-15
---

# Phase 7 Plan 1: Settings Window Reliability Summary

**A dedicated, reusable Settings window that matches the target UI and opens reliably from all entry points (including Cmd+,) in an LSUIElement menu-bar app.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-15T22:26:05Z
- **Completed:** 2026-02-15T22:28:50Z
- **Tasks:** 3
- **Files modified:** 16

## Accomplishments
- Replaced flaky Settings-scene usage with a dedicated `NSWindowController` hosting `PingMonitorSettingsView`
- Added Settings UI wiring for display/notification toggles, host list management, and Reset-to-Defaults
- Routed Settings entry points (menu bar, in-app gear, Cmd+,) through `AppDelegate.openSettings()`
- Added single-instance defense-in-depth (Info.plist + runtime activation/exit)

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire Settings window to the screenshot-matching view** - `c1a3279` (feat)
2. **Task 2: Route all Settings entry points through a single AppDelegate API** - `43f06a1` (feat)
3. **Task 3: Ensure multi-instance launches do not create multiple copies** - `e5ae934` (chore)

**Plan metadata:** (added in final docs commit)

## Files Created/Modified
- `Sources/PingScope/Views/Settings/PingMonitorSettingsView.swift` - Screenshot-matching Settings UI
- `Sources/PingScope/App/AppDelegate.swift` - Settings window lifecycle, openSettings API, reset defaults, single-instance guard
- `Sources/PingScope/Services/StartOnLaunchService.swift` - Start-on-launch toggle via ServiceManagement
- `Sources/PingScope/Services/NotificationService.swift` - Safe notification center initialization for bundled vs swift-run
- `Sources/PingScope/PingMonitorApp.swift` - Cmd+, command routed to AppDelegate.openSettings()
- `Info.plist` - Prohibit multiple running instances
- `scripts/dev-run-app.sh` - Helper to run as a minimal `.app` bundle for notification prompts

## Decisions Made
- Always use a dedicated `NSWindowController` for Settings in an accessory/menu-bar app to avoid Settings-scene reliability issues.
- Lazily initialize `UNUserNotificationCenter` only when running as a proper `.app` bundle (bundle identifier present).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Prevent notification-center crash when running via `swift run`**
- **Found during:** Task 1 (Wire Settings window to the screenshot-matching view)
- **Issue:** `UNUserNotificationCenter.current()` can assert/crash when Bundle identifier is missing (non-bundled SwiftPM execution)
- **Fix:** Lazily create/guard notification center; treat notifications as disabled until running as a bundled app
- **Files modified:** `Sources/PingScope/Services/NotificationService.swift`
- **Verification:** `swift build`
- **Committed in:** `c1a3279`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Required for stability during local development; no scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Settings window lifecycle and entry points are in place; follow-on plans can focus on Settings UX polish and feature completeness.

---
*Phase: 07-settings*
*Completed: 2026-02-15*

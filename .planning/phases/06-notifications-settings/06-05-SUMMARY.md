---
phase: 06-notifications-settings
plan: 05
subsystem: notifications
tags: [usernotifications, userdefaults, privacy-manifest, swiftpm]

requires:
  - phase: 06-notifications-settings
    provides: NotificationService + alert detection + settings UI
provides:
  - App lifecycle wiring for notification permission and alert evaluation
  - PrivacyInfo.xcprivacy declaring UserDefaults access (CA92.1)
  - SwiftPM resource processing for Resources bundle
affects: [06-06-human-verification]

tech-stack:
  added: []
  patterns:
    - AppDelegate owns a single NotificationService and forwards scheduler/gateway events into it
    - Privacy manifest shipped as a SwiftPM processed resource

key-files:
  created:
    - Sources/PingScope/Resources/PrivacyInfo.xcprivacy
  modified:
    - Sources/PingScope/App/AppDelegate.swift
    - Sources/PingScope/Services/NotificationService.swift
    - Package.swift

key-decisions:
  - "Internet loss evaluation treats hosts with unknown state as up to avoid false-positive 'internet loss' alerts during startup"

patterns-established:
  - "Notification permission is requested at app launch using NotificationService.requestAuthorization()"
  - "Scheduler results are forwarded to NotificationService.evaluateResult for per-host alert evaluation"

duration: 3min
completed: 2026-02-15
---

# Phase 6 Plan 05: Lifecycle Wiring + Privacy Manifest Summary

**End-to-end notification wiring from scheduler and gateway monitoring, plus App Store privacy manifest for UserDefaults usage**

## Performance

- **Duration:** 3min
- **Started:** 2026-02-15T20:20:50Z
- **Completed:** 2026-02-15T20:23:40Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Wired `NotificationService` into `AppDelegate` and requested notification authorization at launch
- Forwarded scheduler ping results, gateway changes, and internet-loss checks into notification evaluation
- Added `PrivacyInfo.xcprivacy` and configured SwiftPM to process `Sources/PingScope/Resources` for App Store compliance

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire NotificationService into AppDelegate** - `567ef68` (feat)
2. **Task 2: Create Privacy Manifest** - `9b1be55` (chore)
3. **Task 3: Verify notification flow with build and basic test** - `3124b80` (chore)

**Plan metadata:** (docs commit added after SUMMARY/STATE updates)

## Files Created/Modified

- `Sources/PingScope/App/AppDelegate.swift` - Request authorization and forward scheduler/gateway events into NotificationService
- `Sources/PingScope/Services/NotificationService.swift` - Gate evaluation by Host.notificationsEnabled
- `Sources/PingScope/Resources/PrivacyInfo.xcprivacy` - Declare UserDefaults access with CA92.1 reason
- `Package.swift` - Process Resources bundle so the privacy manifest ships correctly

## Decisions Made

- Internet loss evaluation uses a conservative default for unknown host states (treat as up) to avoid startup false positives.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Per-host notifications toggle was not enforced during evaluation**
- **Found during:** Task 1 (AppDelegate wiring)
- **Issue:** `NotificationService.evaluateResult` did not check `Host.notificationsEnabled`, so the per-host toggle from 06-03 would not actually affect notifications.
- **Fix:** Added a `guard host.notificationsEnabled` gate at the start of `evaluateResult`.
- **Files modified:** `Sources/PingScope/Services/NotificationService.swift`
- **Verification:** `swift build`
- **Committed in:** `567ef68` (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Essential for correctness; no scope creep.

## Issues Encountered

- `swift build` continues to emit a pre-existing Swift 6 warning in `Sources/PingScope/Services/HostStore.swift` about calling an actor-isolated method from init.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 06-06 human verification: settings UI exists and notification evaluation is wired through runtime events.

---
*Phase: 06-notifications-settings*
*Completed: 2026-02-15*

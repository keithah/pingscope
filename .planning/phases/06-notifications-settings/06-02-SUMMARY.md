---
phase: 06-notifications-settings
plan: 02
subsystem: notifications
tags: [usernotifications, swift-concurrency, detection, cooldown]

requires:
  - phase: 06-notifications-settings
    provides: NotificationService foundation and persisted NotificationPreferences
provides:
  - HostAlertState per-host tracking for transitions, baseline, failures, and cooldown
  - AlertDetector pure detection helpers + evaluate() orchestration
  - NotificationService evaluation entrypoints for host results, gateway change, and internet loss
affects: [06-03-host-notification-overrides, 06-04-settings-ui, 06-06-human-verification]

tech-stack:
  added: []
  patterns:
    - Pure detection helpers collected in a Sendable AlertDetector for testability
    - Per-host alert cooldown tracked in HostAlertState.lastAlertTimes

key-files:
  created:
    - Sources/PingScope/Models/HostAlertState.swift
    - Sources/PingScope/Services/AlertDetector.swift
  modified:
    - Sources/PingScope/Services/NotificationService.swift

key-decisions:
  - "Intermittent failure detection treats NotificationPreferences.intermittentWindowSize as a time window (seconds) since failures are tracked as [Date]"
  - "Per-host enabledAlertTypes are intersected with global enabledAlertTypes so overrides can further restrict but not expand global alert policy"

patterns-established:
  - "NotificationService.evaluateResult is the single ingestion point for per-host ping outcomes"
  - "Gateway/internet loss alerts are evaluated via dedicated NotificationService methods using AlertDetector pure functions"

duration: 2min
completed: 2026-02-15
---

# Phase 6 Plan 02: Alert Detection Summary

**All 7 alert types detected via pure AlertDetector functions, with per-host HostAlertState tracking and NotificationService cooldown enforcement**

## Performance

- **Duration:** 2min
- **Started:** 2026-02-15T20:08:09Z
- **Completed:** 2026-02-15T20:10:37Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Introduced `HostAlertState` for down/up transitions, latency baselining, recent failures, and per-alert cooldown timestamps
- Implemented `AlertDetector` with pure helpers for every notification condition and an `evaluate()` function for per-host alerts
- Integrated detection into `NotificationService` via `evaluateResult`, plus gateway change and internet loss evaluation entrypoints

## Task Commits

Each task was committed atomically:

1. **Task 1: Create HostAlertState model** - `ca7b556` (feat)
2. **Task 2: Create AlertDetector with detection logic** - `883aa26` (feat)
3. **Task 3: Integrate AlertDetector into NotificationService** - `796b487` (feat)

**Plan metadata:** (docs commit added after SUMMARY/STATE updates)

## Files Created/Modified

- `Sources/PingScope/Models/HostAlertState.swift` - Per-host state for alert transitions, rolling baselines, failure tracking, and cooldown
- `Sources/PingScope/Services/AlertDetector.swift` - Pure detection helpers and the per-host `evaluate()` orchestration function
- `Sources/PingScope/Services/NotificationService.swift` - Alert evaluation entrypoints + per-host state storage + cooldown enforcement

## Decisions Made

- Intermittent detection uses a time window (seconds) for `NotificationPreferences.intermittentWindowSize` because failures are recorded as timestamps.
- Per-host alert-type overrides are treated as a restriction layer (intersection with global enabled types) to preserve a single global policy gate.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `swift build` continues to emit a pre-existing Swift 6 warning in `Sources/PingScope/Services/HostStore.swift` about calling an actor-isolated method from init.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 06-03 and 06-04: detection plumbing is in place; remaining work is per-host settings UI and lifecycle wiring.

---
*Phase: 06-notifications-settings*
*Completed: 2026-02-15*

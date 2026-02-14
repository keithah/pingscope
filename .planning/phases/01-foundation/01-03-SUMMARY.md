---
phase: 01-foundation
plan: 03
subsystem: networking
tags: [swift-concurrency, actors, scheduling, connection-lifecycle]

# Dependency graph
requires:
  - phase: 01-02
    provides: PingService actor and async connection measurement primitives
provides:
  - Host health state tracking with 3-consecutive-failure down threshold
  - Periodic orphaned connection sweeping with 10s cadence and 30s max age
  - Staggered ping scheduling with restart-on-update and refresh behavior
affects: [01-04, phase-2]

# Tech tracking
tech-stack:
  added: []
  patterns: [actor-isolated health state, actor-managed resource sweeper, staggered task-group scheduling]

key-files:
  created:
    - Sources/PingMonitor/Services/HostHealthTracker.swift
    - Sources/PingMonitor/Services/ConnectionSweeper.swift
    - Sources/PingMonitor/Services/PingScheduler.swift
  modified: []

key-decisions:
  - Keep host-down determination at 3 consecutive failures by default
  - Use 10-second sweep interval and 30-second max-age orphan policy
  - Spread pings over 80% of interval and preserve 20% timing buffer

patterns-established:
  - "Health hysteresis: consecutive-failure threshold avoids transient false-down states"
  - "Scheduler restart semantics: cancel active loop before host/refresh reconfiguration"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 1 Plan 3: Orchestration Services Summary

**Actor-based health tracking, connection sweeping, and staggered ping scheduling complete the foundation orchestration layer on top of PingService.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T08:54:54Z
- **Completed:** 2026-02-14T08:56:22Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added `HostHealthTracker` actor that records per-host consecutive failures and marks down only at threshold.
- Added `ConnectionSweeper` actor that tracks active `NWConnection` objects and cancels orphaned ones older than 30 seconds.
- Added `PingScheduler` actor that staggers pings over 80% of each interval and restarts cleanly on host updates or manual refresh.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create HostHealthTracker Actor** - `841c636` (feat)
2. **Task 2: Create ConnectionSweeper Actor** - `5c3fa54` (feat)
3. **Task 3: Create PingScheduler Actor** - `04c3698` (feat)

## Files Created/Modified
- `Sources/PingMonitor/Services/HostHealthTracker.swift` - Consecutive failure tracking and host-down evaluation.
- `Sources/PingMonitor/Services/ConnectionSweeper.swift` - Active connection registration, timed sweeps, and bulk cancellation.
- `Sources/PingMonitor/Services/PingScheduler.swift` - Staggered ping orchestration with update and refresh restart controls.

## Decisions Made
- Kept host health bookkeeping keyed by host address strings to align with `PingResult.host` values.
- Used integer-safe interval scaling (`interval * 4 / 5`) to avoid floating-point duration math for stagger timing.
- Explicitly cancel scheduler loop before restart paths (`updateHosts` and `refresh`) to make restart behavior deterministic.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Foundation orchestration services are ready for 01-04 unit and behavior verification work.
- No blockers identified for moving into test coverage and validation.

---
*Phase: 01-foundation*
*Completed: 2026-02-14*

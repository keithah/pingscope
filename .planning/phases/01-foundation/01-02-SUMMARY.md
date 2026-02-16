---
phase: 01-foundation
plan: 02
subsystem: networking
tags: [swift-concurrency, network-framework, actors, timeout-racing]

# Dependency graph
requires:
  - phase: 01-01
    provides: Swift package structure and Sendable ping models
provides:
  - Async NWConnection wrapper with cancellation-safe callback bridging
  - Actor-isolated PingService with timeout racing and typed errors
  - Throttled multi-host ping execution with ordered results
affects: [01-03, 01-04, phase-2]

# Tech tracking
tech-stack:
  added: []
  patterns: [withCheckedThrowingContinuation bridge, withThrowingTaskGroup timeout race, actor-isolated service orchestration]

key-files:
  created:
    - Sources/PingScope/Services/ConnectionWrapper.swift
    - Sources/PingScope/Services/PingService.swift
  modified: []

key-decisions:
  - Use fresh NWConnection instances per measurement for reliability
  - Keep default ping timeout at 3 seconds
  - Limit pingAll concurrency to 10 by default

patterns-established:
  - "Cancellation-first cleanup: cancel NWConnection on timeout and task cancellation"
  - "Timeout racing: connection task races sleep task, loser is cancelled"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 1 Plan 2: Ping Service Summary

**Actor-based ping orchestration with async NWConnection bridging, deterministic timeout racing, and cancellation-safe connection cleanup.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T08:35:54Z
- **Completed:** 2026-02-14T08:37:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `ConnectionWrapper` to bridge `NWConnection` callbacks into async/await with continuation safety.
- Added `PingService` actor with `ping(host:)`, parameterized `ping(...)`, and `pingAll(...)` APIs.
- Implemented timeout racing using `withThrowingTaskGroup` with immediate loser cancellation.
- Enforced cleanup on all terminal paths and external cancellation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create NWConnection Async Wrapper** - `ff5bd80` (feat)
2. **Task 2: Create PingService Actor** - `7add630` (feat)

## Files Created/Modified
- `Sources/PingScope/Services/ConnectionWrapper.swift` - Async bridge over `NWConnection` state updates.
- `Sources/PingScope/Services/PingService.swift` - Actor service with timeout race and throttled multi-host pinging.

## Decisions Made
- Treated `.waiting` as failure to avoid indefinite hangs.
- Returned `PingError.cancelled` for cancellation paths to keep result semantics explicit.
- Kept result ordering in `pingAll` by indexing via host IDs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Removed Swift 6 sendable-capture hazard in callback state flag**
- **Found during:** Task 1 (Create NWConnection Async Wrapper)
- **Issue:** Captured mutable local `didResume` in concurrent callback produced sendable-capture warnings that become errors in Swift 6 mode.
- **Fix:** Replaced mutable captured var with lock-protected `ResumeState` reference type marked `@unchecked Sendable`.
- **Files modified:** `Sources/PingScope/Services/ConnectionWrapper.swift`
- **Verification:** `swift build` completed without sendable warnings.
- **Committed in:** `ff5bd80` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Fix was required for forward-compatible concurrency correctness; no scope creep.

## Issues Encountered
- None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Ready for 01-03 service layer additions (health tracking, sweeper, scheduler).
- Ping primitives now provide reliable timeout and cancellation behavior for higher-level orchestration.

---
*Phase: 01-foundation*
*Completed: 2026-02-14*

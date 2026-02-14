# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-13)

**Core value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.
**Current focus:** Phase 2 - Menu Bar & State

## Current Position

Phase: 2 of 6 (Menu Bar & State)
Plan: 3 of 4 in current phase
Status: In progress
Last activity: 2026-02-14 - Completed 02-03-PLAN.md

Progress: [█████░░░░░] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: 2 min
- Total execution time: 0.22 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 4 | 4 | 2 min |
| 2. Menu Bar & State | 2 | 4 | 2 min |

**Recent Trend:**
- Last 5 plans: 01-02 (2 min), 01-03 (2 min), 01-04 (2 min), 02-01 (2 min), 02-03 (3 min)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- (init): Use Swift Concurrency over GCD semaphores to eliminate race conditions
- (init): Modular file structure over single file for maintainability
- (init): Defer widget to v2 to focus on core app stability
- (01-01): Used Duration instead of TimeInterval for type-safe timing
- (01-01): All models conform to Sendable for actor isolation
- (01-02): Use fresh NWConnection instances per measurement for reliability
- (01-02): Timeout racing uses withThrowingTaskGroup with immediate loser cancellation
- (01-02): pingAll default concurrency limit remains 10
- (01-03): Host down state requires 3 consecutive failures tracked per host
- (01-03): Connection sweeper defaults to 10-second cadence with 30-second max age
- (01-03): Ping scheduling spreads execution across 80% of interval with cancel-before-restart updates
- (01-04): PingService tests use real DNS endpoints to verify timeout racing and pingAll behavior
- (01-04): Timeout assertions use bounded tolerance windows to avoid flaky scheduling-edge failures
- (01-04): ConnectionSweeper tests use short 100ms/200ms timing for deterministic fast cleanup checks
- (02-01): Menu status thresholds use <=80ms for green and reserve red for sustained failures
- (02-01): Sustained failure threshold for red status is 3 consecutive failures
- (02-01): Display text smoothing uses bounded EMA (alpha 0.35, max step 40ms)
- (02-03): Popover section order is fixed as status first, quick actions second
- (02-03): Popover snapshot sanitizes blank or missing host/latency to N/A

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-14T10:09:09Z
Stopped at: Completed 02-03-PLAN.md
Resume file: None

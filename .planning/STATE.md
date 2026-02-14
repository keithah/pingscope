# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-02-13)

**Core value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.
**Current focus:** Phase 3 - Host Monitoring

## Current Position

Phase: 3 of 6 (Host Monitoring)
Plan: 0 of TBD in current phase
Status: Ready to execute
Last activity: 2026-02-14 - Completed and verified Phase 2 (Menu Bar & State)

Progress: [███░░░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 8
- Average duration: 2 min
- Total execution time: 0.32 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Foundation | 4 | 4 | 2 min |
| 2. Menu Bar & State | 4 | 4 | 3 min |

**Recent Trend:**
- Last 5 plans: 01-04 (2 min), 02-01 (2 min), 02-03 (3 min), 02-02 (4 min), 02-04 (2 min)
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
- (02-02): Render status dot with SF Symbol tint and keep title compact to preserve menu-bar width
- (02-02): Route ctrl-click and cmd-click through the same context-menu path as right-click
- (02-02): Build menu sections from runtime state and persist mode toggles with a dedicated preference store
- (02-04): Status item uses a non-template drawn dot plus centered stacked text for reliable menu-bar contrast
- (02-04): Compact mode changes are observed alongside scheduler state so status rendering updates immediately
- (02-04): Settings action first tries showSettingsWindow and falls back to a dedicated NSWindow in accessory mode

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-02-14T10:27:54Z
Stopped at: Completed 02-04-PLAN.md
Resume file: None

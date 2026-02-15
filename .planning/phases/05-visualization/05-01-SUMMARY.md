---
phase: 05-visualization
plan: 01
subsystem: ui
tags: [swift, swiftui, viewmodel, retention, tests]

requires:
  - phase: 04-display-modes
    provides: Graph + history + time-range UI driven by DisplayViewModel
provides:
  - 3600-sample per-host in-memory history to fully populate the 1-hour time range
  - Regression test preventing sample retention regressions
affects: [05-visualization, DisplayViewModel, history, graph]

tech-stack:
  added: []
  patterns:
    - Bounded per-host sample arrays trimmed oldest-first

key-files:
  created: []
  modified:
    - Sources/PingScope/ViewModels/DisplayViewModel.swift
    - Tests/PingScopeTests/DisplayViewModelTests.swift
    - Sources/PingScope/MenuBar/StatusItemController.swift

key-decisions:
  - Keep retention session-only and increase capacity via the default sample buffer limit

patterns-established:
  - Retention tests use timestamps safely within the selected time-range window to avoid Date() cutoff flakiness

duration: 3m
completed: 2026-02-15
---

# Phase 5 Plan 1: History Buffer Summary

**In-memory per-host history now retains 3600 samples (session-only) so the 1-hour time range has enough data to be meaningful.**

## Performance

- **Duration:** 3m 21s
- **Started:** 2026-02-15T18:02:41Z
- **Completed:** 2026-02-15T18:06:02Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Increased per-host sample retention to cover the full 1-hour view without persistence.
- Locked the default buffer size with a regression test that fails if the history becomes smaller or unbounded.

## Task Commits

Each task was committed atomically:

1. **Task 1: Increase default per-host sample buffer to 3600** - `4cb4a2f` (feat)
2. **Task 2: Add regression test locking the 3600 default retention** - `a7189f4` (test)

_Additional fix during execution:_ `2f019ed` (fix)

**Plan metadata:** (docs commit created after STATE/SUMMARY updates)

## Files Created/Modified

- `Sources/PingScope/ViewModels/DisplayViewModel.swift` - Raises default `sampleBufferLimit` to keep up to one hour of samples.
- `Tests/PingScopeTests/DisplayViewModelTests.swift` - Verifies default retention keeps exactly 3600 newest samples.
- `Sources/PingScope/MenuBar/StatusItemController.swift` - Fixes status title formatting behavior for compact vs non-compact mode.

## Decisions Made

None - followed plan as specified.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed StatusItemTitleFormatter to match compact-mode expectations**

- **Found during:** Task 1 (Increase default per-host sample buffer to 3600)
- **Issue:** `swift test` failed because `StatusItemTitleFormatter` always removed the space in "NN ms" regardless of compact mode.
- **Fix:** Preserve display text in non-compact mode; strip " ms" only in compact mode.
- **Files modified:** `Sources/PingScope/MenuBar/StatusItemController.swift`
- **Verification:** `swift test`
- **Committed in:** `2f019ed`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to restore a green test run; no scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 1-hour time range now has adequate sample capacity; ready for Phase 5 graph styling/polish work.

---
*Phase: 05-visualization*
*Completed: 2026-02-15*

---
phase: 03-host-monitoring
plan: 09
subsystem: ui
tags: [swift, menubar, host-monitoring, thresholds, testing]

# Dependency graph
requires:
  - phase: 03-01
    provides: Host-level threshold overrides and effective threshold helpers
  - phase: 03-07
    provides: Selected-host runtime sync flow used to propagate host context
provides:
  - Threshold-aware menu bar status evaluation using selected-host effective green/yellow values
  - Runtime-to-view-model threshold propagation on host selection and host switching
  - Regression tests covering strict overrides, global fallback, and host-switch reclassification
affects: [phase-04-display-modes, phase-05-visualization, status-classification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Per-evaluation threshold injection into status classification instead of static evaluator config
    - Selection-driven status context updates that immediately recompute current menu bar status

key-files:
  created: []
  modified:
    - Sources/PingMonitor/MenuBar/MenuBarStatusEvaluator.swift
    - Sources/PingMonitor/ViewModels/MenuBarViewModel.swift
    - Sources/PingMonitor/MenuBar/MenuBarRuntime.swift
    - Tests/PingMonitorTests/MenuBarViewModelTests.swift
    - Tests/PingMonitorTests/MenuBarIntegrationSmokeTests.swift

key-decisions:
  - "MenuBarStatusEvaluator receives thresholds per evaluation call and normalizes ordering to keep deterministic banding."
  - "MenuBarViewModel stores active selected-host thresholds and recomputes status immediately on host selection changes."

patterns-established:
  - "Effective-threshold propagation: runtime passes selected host + global defaults to view model, view model resolves effective thresholds, evaluator classifies state."
  - "Threshold tests assert behavior across strict override, global fallback, and host-switch transitions with deterministic smoothing settings."

# Metrics
duration: 2 min
completed: 2026-02-14
---

# Phase 3 Plan 9: Host Threshold Status Wiring Summary

**Menu bar status classification now uses the selected host's effective green/yellow thresholds (with global fallback), so host overrides and host switches immediately change green/yellow/red boundaries.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T17:41:55Z
- **Completed:** 2026-02-14T17:44:33Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Refactored `MenuBarStatusEvaluator` to classify by dynamic green/yellow thresholds per evaluation while preserving monitoring guards and sustained-failure red handling.
- Wired selected-host threshold context through `MenuBarRuntime.syncSelection` into `MenuBarViewModel`, including immediate status recomputation when selection changes.
- Added regression coverage proving strict overrides, global threshold fallback, and host-switch threshold reclassification behaviors.

## Task Commits

Each task was committed atomically:

1. **Task 1: Make MenuBarStatusEvaluator threshold-aware per evaluation** - `e19b0b7` (feat)
2. **Task 2: Wire selected-host effective thresholds through runtime and view model** - `bde3489` (feat)
3. **Task 3: Add regression tests for host-threshold status behavior** - `f1f451d` (test)

## Files Created/Modified

- `Sources/PingMonitor/MenuBar/MenuBarStatusEvaluator.swift` - Evaluator now receives dynamic thresholds and classifies green/yellow/red using normalized threshold boundaries.
- `Sources/PingMonitor/ViewModels/MenuBarViewModel.swift` - Tracks active selected-host thresholds and passes them into status evaluation.
- `Sources/PingMonitor/MenuBar/MenuBarRuntime.swift` - Selection sync now passes selected host and global defaults into view-model threshold state.
- `Tests/PingMonitorTests/MenuBarViewModelTests.swift` - Adds targeted host-threshold regression cases and updates evaluator construction.
- `Tests/PingMonitorTests/MenuBarIntegrationSmokeTests.swift` - Updated smoke tests to current runtime API to unblock filtered test execution.

## Decisions Made

- Normalize threshold inputs before classifying latency bands so misordered inputs still produce deterministic status.
- Recompute status immediately when selected host changes so users see updated threshold boundaries without waiting for another ping.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated stale integration smoke tests to current runtime API**
- **Found during:** Task 3 (Add regression tests for host-threshold status behavior)
- **Issue:** `swift test --filter MenuBarViewModelTests` could not compile because `MenuBarIntegrationSmokeTests` still used old `MenuBarRuntime` method signatures.
- **Fix:** Updated smoke tests to call `syncSelection`, `ingestSchedulerResult(..., matchedHostID:)`, and `switchHost(in:)` with explicit host arrays.
- **Files modified:** `Tests/PingMonitorTests/MenuBarIntegrationSmokeTests.swift`
- **Verification:** `swift test --filter MenuBarViewModelTests` and `swift test --filter MenuBarIntegrationSmokeTests` both pass.
- **Committed in:** `f1f451d` (part of Task 3 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Blocking test infra issue was resolved to complete required verification; no scope creep in product behavior.

## Authentication Gates

None.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- HOST-08 threshold-wiring gap is closed with runtime/view-model/evaluator wiring and regression coverage.
- Remaining Phase 3 gap work (if any) can proceed independently; no blockers from this plan.

---
*Phase: 03-host-monitoring*
*Completed: 2026-02-14*

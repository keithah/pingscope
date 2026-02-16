---
phase: 02-menu-bar-state
plan: 01
subsystem: ui
tags: [menu-bar, view-model, swift-concurrency, appkit-state]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: PingResult model and scheduler callback pipeline for result ingestion
provides:
  - Centralized menu bar status evaluator with deterministic green/yellow/red/gray rules
  - Reusable latency smoother for compact display updates without raw latency loss
  - MainActor MenuBarViewModel exposing compact text and mode/context state
  - Behavior tests covering startup gray state, transitions, sustained failures, and smoothing
affects: [02-02, 02-03, 02-04, phase-3]

# Tech tracking
tech-stack:
  added: []
  patterns: [centralized status evaluation, display-only smoothing, main-actor observable ui state]

key-files:
  created:
    - Sources/PingScope/MenuBar/MenuBarState.swift
    - Sources/PingScope/MenuBar/MenuBarStatusEvaluator.swift
    - Sources/PingScope/MenuBar/LatencySmoother.swift
    - Sources/PingScope/ViewModels/MenuBarViewModel.swift
    - Tests/PingMonitorTests/MenuBarViewModelTests.swift
  modified: []

key-decisions:
  - Green/yellow split uses 80ms threshold while red is reserved for sustained failure streaks
  - Smoothing uses bounded EMA (alpha 0.35, max step 40ms) for stable compact text updates
  - Failures clear display latency to enforce N/A text when latency is unavailable

patterns-established:
  - "Single evaluator authority: status transitions are resolved in MenuBarStatusEvaluator"
  - "Raw/display separation: keep raw latency while rendering smoothed menu-bar text"

# Metrics
duration: 2min
completed: 2026-02-14
---

# Phase 2 Plan 1: Menu Bar State Summary

**Main-actor menu bar state now maps ping results into deterministic color status and compact, smoothed latency text for UI rendering.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T09:49:39Z
- **Completed:** 2026-02-14T09:51:54Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Added `MenuBarStatus`, `MenuBarState`, and `MenuBarStatusEvaluator` with centralized status semantics.
- Added `LatencySmoother` for display-only jitter reduction while preserving raw latency separately.
- Implemented `@MainActor` `MenuBarViewModel` as the single source of truth for compact text, status, selected host summary, and mode flags.
- Added `MenuBarViewModelTests` validating startup gray/N-A state, healthy-warning transitions, sustained-failure red behavior, and smoothing.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement menu bar state and status evaluation primitives** - `84995c6` (feat)
2. **Task 2: Build @MainActor menu bar view model with behavior tests** - `a18c6ee` (feat)

## Files Created/Modified
- `Sources/PingScope/MenuBar/MenuBarState.swift` - UI-facing menu bar state with display text, status, and last raw latency.
- `Sources/PingScope/MenuBar/MenuBarStatusEvaluator.swift` - Deterministic green/yellow/red/gray transition logic.
- `Sources/PingScope/MenuBar/LatencySmoother.swift` - Reusable side-effect-free smoothing utility for display latency.
- `Sources/PingScope/ViewModels/MenuBarViewModel.swift` - MainActor observable state pipeline for menu bar UI.
- `Tests/PingMonitorTests/MenuBarViewModelTests.swift` - Behavior coverage for status, text formatting, and smoothing.

## Decisions Made
- Chose `healthyUpperBoundMS = 80` and `sustainedFailureThreshold = 3` to align with compact menu semantics and prior host-down hysteresis.
- Used bounded EMA smoothing (`alpha = 0.35`, `maxStepMS = 40`) to reduce jumpiness while keeping updates responsive.
- Set failure display text to `N/A` until successful latency resumes, while still escalating to red only after sustained failures.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Status/state pipeline is ready for status-item controller integration in `02-02`.
- No blockers identified.

---
*Phase: 02-menu-bar-state*
*Completed: 2026-02-14*

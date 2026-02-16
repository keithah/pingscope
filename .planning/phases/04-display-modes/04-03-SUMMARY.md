---
phase: 04-display-modes
plan: 03
subsystem: ui
tags: [swift, appkit, nspopover, nswindow, menu-bar, testing]

# Dependency graph
requires:
  - phase: 04-01
    provides: display mode persistence contracts and per-mode frame state storage
provides:
  - Display shell coordinator for popover and floating-window routing
  - Anchor-and-clamp placement that keeps floating windows on-screen near the status item
  - Drag-handle-only floating window behavior with current-Space-only collection flags
affects: [04-04, 04-05, 05-visualization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Centralize shell presentation decisions in a dedicated AppKit coordinator
    - Re-anchor then clamp floating windows using status-item screen coordinates

key-files:
  created:
    - Sources/PingScope/MenuBar/DisplayModeCoordinator.swift
    - Sources/PingScope/Views/WindowDragHandleView.swift
    - Tests/PingMonitorTests/DisplayModeCoordinatorTests.swift
  modified:
    - Sources/PingScope/MenuBar/DisplayModeCoordinator.swift

key-decisions:
  - "Reopen and mode-switch floating windows are always re-anchored from the status-item button and clamped to visibleFrame"
  - "Floating shell uses borderless + floating level with collectionBehavior [.transient, .moveToActiveSpace] to stay in current Space"
  - "Window movement remains disabled for background drags; drag starts from dedicated handle path only"

patterns-established:
  - "Coordinator API split: open/showPopover/showFloatingWindow with explicit anchor conversion"
  - "Deterministic geometry helper: anchoredAndClampedFrame for regression-tested placement"

# Metrics
duration: 5 min
completed: 2026-02-14
---

# Phase 4 Plan 3: Presentation Shell Coordinator Summary

**AppKit shell coordination now routes popover versus floating windows with status-item anchoring, on-screen clamping, and drag-handle-only movement semantics.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-14T18:40:37Z
- **Completed:** 2026-02-14T18:45:13Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- Added `DisplayModeCoordinator` with centralized shell routing and explicit `showPopover`/`showFloatingWindow` APIs.
- Implemented anchor-to-screen conversion plus clamped placement logic so floating windows reopen near the menu bar icon but remain visible.
- Configured floating window flags for borderless floating behavior in current Space only and added `WindowDragHandleView` bridge for explicit drag initiation.
- Added focused coordinator tests for placement math, floating window flags, and drag-handle invocation path.

## Task Commits

Each task was committed atomically:

1. **Task 1: Build DisplayModeCoordinator with anchor-and-clamp placement** - `d1fdca8` (feat)
2. **Task 2: Implement drag-handle-only floating behavior** - `70d61a4` (feat)
3. **Task 3: Add coordinator tests for placement and window flags** - `b7369c4` (test)

## Files Created/Modified
- `Sources/PingScope/MenuBar/DisplayModeCoordinator.swift` - Central presentation coordinator with anchor/clamp placement and shell routing.
- `Sources/PingScope/Views/WindowDragHandleView.swift` - Dedicated AppKit drag-handle bridge that forwards mouse down to window drag behavior.
- `Tests/PingMonitorTests/DisplayModeCoordinatorTests.swift` - Regression suite for frame clamping, window flags, and drag-handle behavior.

## Decisions Made
- Keep placement deterministic by deriving anchor rect from `NSStatusBarButton` each open and clamping against active screen `visibleFrame`.
- Encode stay-on-top behavior in coordinator-owned window configuration rather than distributed call sites.
- Treat drag movement as an explicit handle affordance by leaving `isMovableByWindowBackground` disabled.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed test-target compile blocker from ambiguous `Host` symbol**
- **Found during:** Final verification (`swift test --filter DisplayModeCoordinatorTests`)
- **Issue:** Test target failed to compile because `Tests/PingMonitorTests/DisplayViewModelTests.swift` referenced unqualified `Host`, conflicting with Foundation `NSHost`.
- **Fix:** Updated the untracked test file to use `PingMonitor.Host` explicitly.
- **Files modified:** `Tests/PingMonitorTests/DisplayViewModelTests.swift` (untracked workspace file)
- **Verification:** Re-ran `swift build && swift test --filter DisplayModeCoordinatorTests` successfully.
- **Committed in:** Not committed (untracked file outside this plan's scoped artifacts)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Deviation was required to unblock package test compilation; no scope expansion to shell behavior implementation.

## Authentication Gates

None.

## Issues Encountered

- SwiftPM test compilation initially failed due to an unrelated untracked test file conflict in the workspace; resolved inline and verification completed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Display shell mechanics are in place and regression-covered, so Phase 4 runtime wiring can integrate coordinator APIs into `AppDelegate`/menu interactions.
No blockers identified for `04-04-PLAN.md`.

---
*Phase: 04-display-modes*
*Completed: 2026-02-14*

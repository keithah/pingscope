---
phase: 02-menu-bar-state
plan: 03
subsystem: ui
tags: [swiftui, menubar, popover, mvvm, testing]

# Dependency graph
requires:
  - phase: 02-01
    provides: Menu bar status state, compact latency text, and selected host summary
provides:
  - Status popover view model that transforms menu state into status-first UI snapshot
  - Quick-action model and callbacks for refresh, host switch entry, and settings entry
  - SwiftUI popover view that presents status and actions without click-routing coupling
affects: [02-04, phase-2-integration, status-item-controller]

# Tech tracking
tech-stack:
  added: []
  patterns: [MainActor popover view-model bridge, snapshot transformation with N/A fallback]

key-files:
  created:
    - Sources/PingScope/ViewModels/StatusPopoverViewModel.swift
    - Sources/PingScope/Views/StatusPopoverView.swift
    - Tests/PingMonitorTests/StatusPopoverViewModelTests.swift
  modified: []

key-decisions:
  - "Popover section order is fixed as status first, quick actions second"
  - "Missing or blank latency/host values are normalized to N/A in the popover snapshot"

patterns-established:
  - "Popover ViewModel consumes MenuBarViewModel published state and emits UI-ready snapshot"
  - "Popover View remains presentation-only and routes actions via callback hooks"

# Metrics
duration: 3min
completed: 2026-02-14
---

# Phase 2 Plan 3: Popover Surface Summary

**Status popover UI now ships with a MainActor view model that maps live menu-bar state into a compact status snapshot plus quick actions for refresh, host switching, and settings.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-14T10:06:21Z
- **Completed:** 2026-02-14T10:09:09Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Implemented `StatusPopoverViewModel` with status label/category, latency text, host summary, and action metadata.
- Added callback wiring for refresh, switch-host entry, and settings entry to keep phase-2 popover immediately interactive.
- Built `StatusPopoverView` as a compact SwiftUI layout emphasizing current status first and quick actions second.
- Added deterministic tests for section ordering, `N/A` fallback behavior, and quick-action callback execution.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement popover view model with status-first + action-ready sections** - `4bf0a1d` (feat)
2. **Task 2: Create SwiftUI popover view bound to popover view model** - `847b5f3` (feat)

**Plan metadata:** pending

## Files Created/Modified
- `Sources/PingScope/ViewModels/StatusPopoverViewModel.swift` - Popover state transformation, section/action metadata, and callback dispatch.
- `Sources/PingScope/Views/StatusPopoverView.swift` - SwiftUI popover surface rendering status details and quick-action controls.
- `Tests/PingMonitorTests/StatusPopoverViewModelTests.swift` - Unit coverage for section order, fallback display values, and action hooks.

## Decisions Made
- Kept popover section order explicit (`status`, then `quickActions`) so first-open emphasis matches context requirements.
- Centralized fallback sanitization in view-model snapshot mapping so the view never renders blank latency/host content.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Popover view-model and SwiftUI surface are ready for injection into status-item lifecycle wiring in `02-04`.
- No blockers identified.

---
*Phase: 02-menu-bar-state*
*Completed: 2026-02-14*

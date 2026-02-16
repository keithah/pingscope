---
phase: 04-display-modes
plan: 04
subsystem: ui
tags: [swift, swiftui, appkit, settings, menu-bar, integration-testing]

# Dependency graph
requires:
  - phase: 04-02
    provides: full/compact display surfaces and shared DisplayViewModel state
  - phase: 04-03
    provides: popover/floating shell routing coordinator with anchored reopening
provides:
  - App runtime wiring for DisplayRootView plus DisplayModeCoordinator shell presentation
  - Shared mode preference plumbing between context-menu quick toggles and settings toggles
  - Integration smoke assertions for mode persistence, shell-state selection, and selection continuity
affects: [04-05, 05-visualization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Keep one runtime-owned DisplayViewModel instance and feed scheduler results into it
    - Route all mode/stay-on-top writes through AppDelegate setters backed by ModePreferenceStore

key-files:
  created:
    - Sources/PingScope/Views/DisplayRootView.swift
  modified:
    - Sources/PingScope/App/AppDelegate.swift
    - Sources/PingScope/MenuBar/MenuBarRuntime.swift
    - Sources/PingScope/PingMonitorApp.swift
    - Tests/PingMonitorTests/MenuBarIntegrationSmokeTests.swift

key-decisions:
  - "Status-item open/close now delegates to DisplayModeCoordinator so reopening follows stay-on-top shell rules"
  - "Settings toggles bind directly to persisted menuBar.mode keys and call AppDelegate setters to keep live runtime state synchronized"
  - "Display mode switches reuse one DisplayViewModel instance so selected host/time-range state survives shell and mode transitions"

patterns-established:
  - "Display root switch pattern: coordinator receives a fresh NSHostingController wrapping mode-specific content"
  - "Integration smoke tests assert wiring contracts (persistence + shell choice + selection continuity) instead of visual rendering"

# Metrics
duration: 6 min
completed: 2026-02-14
---

# Phase 4 Plan 4: Runtime Display-Mode Wiring Summary

**Menu-bar runtime now opens full/compact display surfaces through a coordinator-driven popover or floating shell, with shared settings/context toggles and preserved selection context across mode switches.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-14T18:50:05Z
- **Completed:** 2026-02-14T18:55:43Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Integrated `DisplayModeCoordinator` + `DisplayRootView` into `AppDelegate` so status-item open/close and reopen paths honor current mode and stay-on-top shell behavior.
- Routed scheduler results and host-selection synchronization through one shared `DisplayViewModel`, preserving selected host/time range while switching display modes.
- Replaced settings placeholder with lightweight display toggles bound to persisted mode keys and synchronized with quick-toggle runtime actions.
- Extended integration smoke tests to cover compact/full persistence, stay-on-top shell preference selection, and selection-context continuity.

## Task Commits

Each task was committed atomically:

1. **Task 1: Integrate DisplayRootView and coordinator into AppDelegate runtime flow** - `d8f3298` (feat)
2. **Task 2: Expose display toggles in settings while keeping quick toggle behavior** - `a9d3044` (feat)
3. **Task 3: Extend integration smoke tests for display mode and shell switching** - `963cb4a` (test)

## Files Created/Modified
- `Sources/PingScope/App/AppDelegate.swift` - Wires runtime display presentation, host-selection bridging, and scheduler fanout into `DisplayViewModel`.
- `Sources/PingScope/MenuBar/MenuBarRuntime.swift` - Adds explicit compact/stay-on-top setter APIs and active `displayMode` projection.
- `Sources/PingScope/Views/DisplayRootView.swift` - Mode-aware root view that switches between full and compact surfaces and exposes floating drag chrome.
- `Sources/PingScope/PingMonitorApp.swift` - Adds display settings toggles for compact mode and stay-on-top with shared preference-key bindings.
- `Tests/PingMonitorTests/MenuBarIntegrationSmokeTests.swift` - Adds wiring-level assertions for persisted mode/shell toggles and preserved selection context.

## Decisions Made
- Route status-item presentation through coordinator-based `presentDisplay` refreshes so mode/stay-on-top toggles can immediately re-anchor active shells.
- Keep mode persistence source-of-truth in `ModePreferenceStore` and mirror settings writes through `AppDelegate` to avoid split runtime state.
- Assert shell switching through deterministic stay-on-top state contracts in integration smoke tests rather than fragile visual checks.

## Deviations from Plan

None - plan executed exactly as written.

## Authentication Gates

None.

## Issues Encountered

- `SwiftUI.onChange` overloads were unavailable for the package target baseline, so settings synchronization was implemented with explicit `Binding` setters.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Runtime display-mode behavior is now end-to-end wired for DISP-01 through DISP-06 handoff expectations, with integration smoke protection in place.
No blockers identified for `04-05-PLAN.md`.

---
*Phase: 04-display-modes*
*Completed: 2026-02-14*

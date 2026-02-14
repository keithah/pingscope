---
phase: 02-menu-bar-state
plan: 02
subsystem: ui
tags: [appkit, menubar, nsmenu, userdefaults, swift]
requires:
  - phase: 02-01
    provides: menu bar status/state evaluation and display text smoothing
provides:
  - NSStatusItem controller with deterministic left/right/control/command click routing
  - State-driven context menu factory with grouped host, mode, settings, and quit actions
  - UserDefaults-backed persistence for compact and stay-on-top toggles
affects: [02-03, 02-04, phase-4-display-modes]
tech-stack:
  added: []
  patterns:
    - Adapter-based click routing separated from AppKit event handlers
    - Context menu construction from explicit state/action models
    - Lightweight mode persistence via dedicated preference store
key-files:
  created:
    - Sources/PingMonitor/MenuBar/StatusItemController.swift
    - Sources/PingMonitor/MenuBar/ContextMenuFactory.swift
    - Sources/PingMonitor/MenuBar/ModePreferenceStore.swift
    - Tests/PingMonitorTests/ContextMenuFactoryTests.swift
  modified:
    - Sources/PingMonitor/PingMonitorApp.swift
key-decisions:
  - "Render menu bar dot using SF Symbol image tint plus compact text to keep width small"
  - "Route ctrl-click and cmd-click through the same context-menu path as right-click"
  - "Retain menu action relay via associated object so menu callbacks remain stable"
patterns-established:
  - "Menu controller receives closures for popover/context actions instead of owning business logic"
  - "Context menus are rebuilt from runtime view-model state at open time"
duration: 4m
completed: 2026-02-14
---

# Phase 2 Plan 2: Menu Interaction Surface Summary

**Menu bar interaction is now live with deterministic click routing, grouped context menus, and persistent mode toggles wired into app startup.**

## Performance

- **Duration:** 4m
- **Started:** 2026-02-14T10:06:26Z
- **Completed:** 2026-02-14T10:10:51Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Implemented `StatusItemController` to render status dot + compact latency text and route click events deterministically.
- Added `ContextMenuFactory` that builds host, mode, and app action sections from current state with callback wiring.
- Added `ModePreferenceStore` to persist compact/stay-on-top toggles and integrated both menu and persistence into `PingMonitorApp`.
- Added `ContextMenuFactoryTests` validating section ordering, required items, checked states, callback wiring, and persistence behavior.

## Task Commits

Each task was committed atomically:

1. **Task 1: Build status item controller with deterministic click routing** - `07da38a` (feat)
2. **Task 2: Implement context menu factory and mode preference persistence** - `cfbf627` (feat)

## Files Created/Modified
- `Sources/PingMonitor/MenuBar/StatusItemController.swift` - NSStatusItem lifecycle, rendering, and route adapters.
- `Sources/PingMonitor/MenuBar/ContextMenuFactory.swift` - State-driven NSMenu composition and callback relay.
- `Sources/PingMonitor/MenuBar/ModePreferenceStore.swift` - UserDefaults-backed compact/stay-on-top mode persistence.
- `Tests/PingMonitorTests/ContextMenuFactoryTests.swift` - Menu structure/action/persistence coverage.
- `Sources/PingMonitor/PingMonitorApp.swift` - App delegate wiring for status item, popover toggle, host switch flow, and mode persistence.

## Decisions Made
- Used `StatusItemClickRouter` as a separate adapter so click routing remains deterministic and testable without full app launch.
- Kept popover and context menu independent so right/control/command-click does not force-close the open popover.
- Chose `Current Host + Switch Host...` top section instead of inline host lists to match locked phase context.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added app lifecycle wiring for smoke verification path**
- **Found during:** Task 1 (status item controller implementation)
- **Issue:** The app had no status-item lifecycle wiring, so `swift run PingMonitor` could not satisfy the required visible menu-bar interaction path.
- **Fix:** Updated app delegate startup to instantiate `StatusItemController`, popover toggle behavior, and context-menu presentation hooks.
- **Files modified:** `Sources/PingMonitor/PingMonitorApp.swift`
- **Verification:** `swift build`; `swift run PingMonitor` startup smoke run
- **Committed in:** `07da38a` (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Fix was required to make verification meaningful; scope remained within Phase 2 interaction goals.

## Issues Encountered
- Context-menu action test helper initially used `NSApp.sendAction` which is unavailable in headless test execution; switched to direct target selector invocation.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Menu-bar interaction shell is ready for richer popover UI and phase-2 integration wiring.
- No blockers identified for 02-03.

---
*Phase: 02-menu-bar-state*
*Completed: 2026-02-14*

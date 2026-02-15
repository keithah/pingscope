---
phase: 07-settings
plan: 02
subsystem: ui
tags: [swift, swiftui, appkit, settings, viewmodel, hoststore]

# Dependency graph
requires:
  - phase: 07-settings
    provides: Dedicated settings window controller + reliable openSettings entrypoint
provides:
  - Settings scene renders the same live Settings UI used by the dedicated settings window
  - Shared HostListViewModel/HostStore wiring so Settings host CRUD applies immediately to the running monitor
affects: [07-settings-03, 07-settings-04, settings-persistence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Settings scenes should use AppDelegate-provided live view models (no ad-hoc HostStore instances)"

key-files:
  created: []
  modified:
    - Sources/PingScope/App/AppDelegate.swift
    - Sources/PingScope/PingMonitorApp.swift
    - Sources/PingScope/Views/Settings/PingMonitorSettingsView.swift

key-decisions:
  - "Replace SettingsTabView/HostSettingsView settings-scene content with PingMonitorSettingsView wired to AppDelegate dependencies"
  - "Expose AppDelegate shared view models/stores at module scope to allow Settings scene to use live runtime wiring"

patterns-established:
  - "SettingsSceneView bridges SwiftUI Settings scene to the same runtime-backed settings view"

# Metrics
duration: 6min
completed: 2026-02-15
---

# Phase 7 Plan 02: Live Settings Host Store Summary

**SwiftUI Settings scene now uses the live HostListViewModel/HostStore wiring so Settings host CRUD updates the running scheduler/UI immediately.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-15T22:32:10Z
- **Completed:** 2026-02-15T22:38:31Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Removed the last Settings entry point that used an ad-hoc HostStore (preventing divergent in-memory host lists)
- Unified Settings scene and dedicated Settings window to render the same PingMonitorSettingsView with shared dependencies
- Simplified Settings host removal flow to act on the presented selection

## Task Commits

Each task was committed atomically:

1. **Task 1: Use the app's live HostListViewModel in Settings** - `06f5f36` (feat)
2. **Task 2: Wire Settings host CRUD to live refresh** - `bff3928` (fix)

**Plan metadata:** (docs: complete plan)

## Files Created/Modified
- `Sources/PingScope/App/AppDelegate.swift` - Expose shared view models/stores and remove optional hostListViewModel plumbing
- `Sources/PingScope/PingMonitorApp.swift` - Render Settings scene via PingMonitorSettingsView wired to AppDelegate dependencies
- `Sources/PingScope/Views/Settings/PingMonitorSettingsView.swift` - Remove redundant delete trigger in confirmation flow

## Decisions Made
- Replaced the Settings-scene TabView implementation with PingMonitorSettingsView to ensure host CRUD always routes through the live runtime wiring.
- Made AppDelegate’s shared HostListViewModel/DisplayViewModel and notification store available to the module so SwiftUI scenes can bind to the same instances.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Settings host CRUD now routes through live runtime wiring; ready to focus on persistence/reload consistency in 07-03.

---
*Phase: 07-settings*
*Completed: 2026-02-15*

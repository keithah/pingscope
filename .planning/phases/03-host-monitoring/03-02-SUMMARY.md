---
phase: 03-host-monitoring
plan: 02
subsystem: services
tags: [swift, network, nwpathmonitor, sysctl, corewlan, gateway]

# Dependency graph
requires:
  - phase: 03-01
    provides: Host and ping method models consumed by gateway monitoring integration
provides:
  - GatewayInfo model with network-aware display naming
  - GatewayDetector actor with NWPathMonitor-driven AsyncStream updates
  - sysctl route-table parsing for default gateway IP and interface detection
  - Debounced gateway refresh with immediate unavailable updates on disconnect
affects: [03-03, 03-04, 03-07, menu status network indicators]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Gateway changes are emitted through AsyncStream from actor-isolated state
    - Route-table queries and SSID lookup run in detached utility tasks to avoid blocking actor callbacks

key-files:
  created:
    - Sources/PingMonitor/Services/GatewayDetector.swift
  modified:
    - Sources/PingMonitor/Services/GatewayDetector.swift
    - Sources/PingMonitor/Services/PingService.swift

key-decisions:
  - "Use sysctl route-table parsing instead of NWPath gateway fields for default gateway detection"
  - "Debounce satisfied path updates at 200ms but emit unavailable immediately when disconnected"

patterns-established:
  - "GatewayDetector tracks previous network names to expose a future network-change indicator signal"
  - "GatewayInfo.displayName prefers SSID-based naming and gracefully falls back to IP or No Network"

# Metrics
duration: 2 min
completed: 2026-02-14
---

# Phase 3 Plan 2: Gateway Detector Summary

**Gateway detection now streams real-time updates using NWPathMonitor, resolves default routes via sysctl, and labels gateways with Wi-Fi SSID when available.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-14T16:49:01Z
- **Completed:** 2026-02-14T16:51:56Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `GatewayInfo` with availability semantics, SSID-aware display naming, and an unavailable sentinel.
- Implemented `GatewayDetector` actor to stream debounced gateway updates from `NWPathMonitor` path changes.
- Added sysctl route-table parsing and CoreWLAN SSID lookup for gateway IP/interface and network-aware naming.
- Added path status handling for immediate `.unavailable` emission on disconnect plus network-change tracking helpers.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement GatewayInfo and gateway detection** - `b211f31` (feat)
2. **Task 2: Add network path status handling** - `59394ec` (feat)

## Files Created/Modified
- `Sources/PingMonitor/Services/GatewayDetector.swift` - Gateway model, sysctl parsing, SSID lookup, monitor stream, debounce, and network-change helpers.
- `Sources/PingMonitor/Services/PingService.swift` - Blocking API alignment fix so package builds with the current `Host` schema.

## Decisions Made
- Preferred kernel routing-table queries via `sysctl` over `NWPath` gateway fields to avoid known stability pitfalls during path transitions.
- Kept disconnect handling immediate (no debounce) while preserving debounce for connected transitions to avoid gateway thrashing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated PingService for current Host API to restore build verification**
- **Found during:** Task 1 (Implement GatewayInfo and gateway detection)
- **Issue:** `PingService` still referenced removed `Host.ProtocolType` and `Host.timeout`, causing `swift build` to fail before gateway changes could be verified.
- **Fix:** Switched `PingService` to `Host.pingMethod` and `Host.timeoutOverride`, with temporary `icmpSimulated` routing through TCP parameters.
- **Files modified:** `Sources/PingMonitor/Services/PingService.swift`
- **Verification:** `swift build` succeeds after the fix.
- **Committed in:** `b211f31`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Blocking fix was required to verify and complete planned gateway work. No scope creep beyond build restoration.

## Issues Encountered
- Initial `swift build` failed due to pre-existing `PingService` references to removed Host fields; resolved inline as a blocking fix.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Ready for `03-03-PLAN.md` to complete ping-method execution behavior, including dedicated ICMP-simulated probing logic.
- Gateway detection foundation is in place for later integration work in `03-07-PLAN.md`.

---
*Phase: 03-host-monitoring*
*Completed: 2026-02-14*

# Roadmap: PingMonitor

## Overview

PingMonitor is a macOS menu bar network monitoring app rewritten from a monolithic implementation to a stable, modular architecture. The roadmap prioritizes foundation-first development to eliminate the race conditions and stale connections that plagued the previous implementation. Each phase delivers a complete, verifiable capability building toward a reliable ping monitor that users can trust.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Foundation** - Async patterns and connection lifecycle management
- [x] **Phase 2: Menu Bar & State** - Menu bar display, interaction, and state management
- [x] **Phase 3: Host Monitoring** - Multi-host support, ping methods, and configuration
- [ ] **Phase 4: Display Modes** - Full view, compact view, and floating window
- [ ] **Phase 5: Visualization** - Latency graph, history table, and statistics
- [ ] **Phase 6: Notifications & Settings** - Alert system and persistent configuration

## Phase Details

### Phase 1: Foundation
**Goal**: Establish correct async patterns and connection lifecycle that prevent the race conditions and stale connections from the previous implementation.
**Depends on**: Nothing (first phase)
**Requirements**: TECH-01, TECH-02, TECH-03, TECH-04, TECH-05, TECH-06, TECH-07
**Success Criteria** (what must be TRUE):
  1. PingService can measure TCP/UDP connection latency using async/await (no DispatchSemaphore)
  2. Connection timeouts report accurately without false positives from race conditions
  3. Connections are properly cleaned up after use (no stale connections accumulating)
  4. Unit tests verify timeout behavior and concurrent ping handling
**Plans**: 4 plans

Plans:
- [x] 01-01-PLAN.md — Swift package setup and core data models (PingResult, Host, PingError)
- [x] 01-02-PLAN.md — NWConnection async wrapper and PingService actor with timeout racing
- [x] 01-03-PLAN.md — HostHealthTracker, ConnectionSweeper, and PingScheduler services
- [x] 01-04-PLAN.md — Unit tests for timeout behavior and concurrent handling

### Phase 2: Menu Bar & State
**Goal**: Users see real-time ping status in the menu bar and can interact via left/right click.
**Depends on**: Phase 1
**Requirements**: MENU-01, MENU-02, MENU-03, MENU-04, MENU-05, MENU-06, MENU-07
**Success Criteria** (what must be TRUE):
  1. Menu bar shows color-coded dot (green/yellow/red/gray) reflecting current ping status
  2. Menu bar shows ping time in milliseconds that updates in real-time
  3. Left-click opens a popover/window with the app interface
  4. Right-click opens a context menu with host switching, mode toggles, Settings, and Quit
**Plans**: 4 plans

Plans:
- [x] 02-01-PLAN.md — Menu bar state evaluator, smoothing, and view-model tests
- [x] 02-02-PLAN.md — Status item controller, click routing, context menu, and mode persistence
- [x] 02-03-PLAN.md — Popover view model and SwiftUI popover interface
- [x] 02-04-PLAN.md — App lifecycle wiring, integration smoke tests, and human interaction verification

### Phase 3: Host Monitoring
**Goal**: Users can monitor multiple hosts with configurable ping methods and settings.
**Depends on**: Phase 2
**Requirements**: HOST-01, HOST-02, HOST-03, HOST-04, HOST-05, HOST-06, HOST-07, HOST-08, HOST-09, HOST-10
**Success Criteria** (what must be TRUE):
  1. App monitors multiple hosts simultaneously (Google DNS, Cloudflare, Gateway + custom)
  2. Default gateway is auto-detected and updates when network changes
  3. User can choose ping method per host (ICMP-simulated, UDP, TCP)
  4. User can configure interval, timeout, and latency thresholds per host
  5. User can add, edit, and delete custom hosts (default hosts protected)
**Plans**: 9 plans (including 2 gap-closure plans)

Plans:
- [x] 03-01-PLAN.md — Extend Host model with per-host configuration and ping methods
- [x] 03-02-PLAN.md — GatewayDetector service with sysctl gateway lookup and network monitoring
- [x] 03-03-PLAN.md — Update PingService for TCP, UDP, and ICMP-simulated methods
- [x] 03-04-PLAN.md — HostStore actor for CRUD and UserDefaults persistence
- [x] 03-05-PLAN.md — Host list view with selection, indicators, and delete confirmation
- [x] 03-06-PLAN.md — Add/edit host sheet with form validation and test ping
- [x] 03-07-PLAN.md — App integration with multi-host monitoring and gateway detection
- [x] 03-08-PLAN.md — Gap closure: per-host scheduler cadence wiring and tests
- [x] 03-09-PLAN.md — Gap closure: threshold-aware status evaluation wiring and tests

### Phase 4: Display Modes
**Goal**: Users can choose between full and compact views, with optional stay-on-top floating window.
**Depends on**: Phase 3
**Requirements**: DISP-01, DISP-02, DISP-03, DISP-04, DISP-05, DISP-06
**Success Criteria** (what must be TRUE):
  1. Full view mode (450x500) shows host tabs, graph, and history
  2. Compact view mode (280x220) shows condensed display
  3. User can toggle between full and compact modes
  4. Stay-on-top floating window works with borderless, movable frame
**Plans**: 5 plans

Plans:
- [ ] 04-01-PLAN.md — Define display-mode persistence contracts and preference store
- [ ] 04-02-PLAN.md — Build full/compact display views and shared display view model
- [ ] 04-03-PLAN.md — Implement popover/floating coordinator with anchor and drag-handle behavior
- [ ] 04-04-PLAN.md — Integrate display mode runtime wiring, settings toggles, and smoke tests
- [ ] 04-05-PLAN.md — Human verification checkpoint for DISP-01 through DISP-06

### Phase 5: Visualization
**Goal**: Users can see latency trends via graph and review ping history with statistics.
**Depends on**: Phase 4
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05, VIS-06, VIS-07
**Success Criteria** (what must be TRUE):
  1. Real-time latency graph shows line with gradient fill and data points
  2. Graph time filter works (1min, 5min, 10min, 1hour)
  3. History table shows timestamp, host, ping time, and status (scrollable, recent first)
  4. Statistics display shows transmitted, received, packet loss, min/avg/max/stddev
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

### Phase 6: Notifications & Settings
**Goal**: Users receive intelligent alerts and all settings persist across app restarts.
**Depends on**: Phase 5
**Requirements**: NOTF-01, NOTF-02, NOTF-03, NOTF-04, NOTF-05, NOTF-06, NOTF-07, NOTF-08, NOTF-09, NOTF-10, SETT-01, SETT-02, SETT-03, SETT-04, SETT-05, SETT-06
**Success Criteria** (what must be TRUE):
  1. App requests notification permission and delivers alerts via macOS Notification Center
  2. All 7 alert types work (no response, high latency, recovery, degradation, intermittent, network change, internet loss)
  3. User can configure notification settings per-host and globally
  4. Settings panel allows host, notification, and display configuration
  5. All settings persist via UserDefaults and survive app restart
**Plans**: TBD

Plans:
- [ ] 06-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 4/4 | Complete | 2026-02-14 |
| 2. Menu Bar & State | 4/4 | Complete | 2026-02-14 |
| 3. Host Monitoring | 9/9 | Complete | 2026-02-14 |
| 4. Display Modes | 0/5 | Not started | - |
| 5. Visualization | 0/? | Not started | - |
| 6. Notifications & Settings | 0/? | Not started | - |

---
*Roadmap created: 2026-02-13*
*Phase 1 planned: 2026-02-14*
*Phase 3 planned: 2026-02-14*
*Phase 4 planned: 2026-02-14*

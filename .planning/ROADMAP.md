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
- [x] **Phase 4: Display Modes** - Full view, compact view, and floating window
- [x] **Phase 5: Visualization** - Latency graph, history table, and statistics
- [x] **Phase 6: Notifications & Settings** - Alert system and persistent configuration
- [x] **Phase 7: Settings Focus** - Settings reliability, live-updating configuration, and end-to-end persistence
- [x] **Phase 8: Visualization Requirement Reconciliation & Verification** - Close VIS-01 through VIS-07 and produce missing Phase 5 verification artifact
- [x] **Phase 9: Regression Test Wiring Recovery** - Restore compile-green automated regression integration coverage
- [x] **Phase 10: True ICMP Support** - Real ICMP ping when running outside sandbox
- [x] **Phase 11: Tech Debt Closure** - Close non-blocking v1.0 debt in runtime wiring, settings UX, and planning traceability

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
- [x] 04-01-PLAN.md — Define display-mode persistence contracts and preference store
- [x] 04-02-PLAN.md — Build full/compact display views and shared display view model
- [x] 04-03-PLAN.md — Implement popover/floating coordinator with anchor and drag-handle behavior
- [x] 04-04-PLAN.md — Integrate display mode runtime wiring, settings toggles, and smoke tests
- [x] 04-05-PLAN.md — Human verification checkpoint for DISP-01 through DISP-06

### Phase 5: Visualization
**Goal**: Users can see latency trends via graph and review ping history with statistics.
**Depends on**: Phase 4
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05, VIS-06, VIS-07
**Success Criteria** (what must be TRUE):
  1. Real-time latency graph shows line with gradient fill and data points
  2. Graph time filter works (1min, 5min, 10min, 1hour)
  3. History table shows timestamp, host, ping time, and status (scrollable, recent first)
  4. Statistics display shows transmitted, received, packet loss, min/avg/max/stddev
**Plans**: 3 plans

Plans:
- [x] 05-01-PLAN.md — Increase in-session history retention to 3600 samples per host
- [x] 05-02-PLAN.md — Polish graph styling (Activity Monitor-like gradient fill + per-sample markers)
- [x] 05-03-PLAN.md — Human verification checkpoint for visualization polish

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
**Plans**: 8 plans (including 2 gap-closure plans)

Plans:
- [x] 06-01-PLAN.md — NotificationService actor, AlertType enum, and NotificationPreferencesStore
- [x] 06-02-PLAN.md — Alert detection logic for all 7 alert types with cooldown
- [x] 06-03-PLAN.md — Per-host notification settings in Host model and add/edit sheet
- [x] 06-04-PLAN.md — Settings TabView with Host, Notification, and Display tabs
- [x] 06-05-PLAN.md — Privacy manifest and app lifecycle notification wiring
- [x] 06-06-PLAN.md — Human verification checkpoint for all Phase 6 requirements
- [x] 06-07-PLAN.md — Gap closure: restore tabbed Settings shell and wire advanced notification controls
- [x] 06-08-PLAN.md — Gap closure: human re-verification of Phase 6 settings truths

### Phase 7: Settings Focus
**Goal**: Settings are reliable, native-feeling, and changes apply immediately across the running app (no restart required).
**Depends on**: Phase 6 (Settings UI + persistence foundation)
**Requirements**: SETT-01, SETT-02, SETT-03, SETT-04, SETT-05, SETT-06
**Success Criteria** (what must be TRUE):
  1. Settings opens reliably from all entry points (menu-bar context menu, in-app gear, Cmd+,)
  2. Only one Settings window exists; repeated opens focus the existing window
  3. Host add/edit/delete in Settings updates the running monitor immediately
  4. Display settings toggles in Settings affect the running UI immediately
  5. Settings persist across quit/relaunch and restore correctly
**Plans**: 4 plans

Plans:
- [x] 07-01-PLAN.md — Dedicated settings window + single-window behavior + command wiring
- [x] 07-02-PLAN.md — Use a shared HostStore (no duplicate stores) so Settings updates apply live
- [x] 07-03-PLAN.md — Settings persistence + reload consistency (hosts, display, notifications UI)
- [x] 07-04-PLAN.md — Human verification checkpoint for Settings end-to-end

### Phase 8: Visualization Requirement Reconciliation & Verification
**Goal**: Close milestone visualization gaps by reconciling VIS-01 through VIS-07 with implementation and producing complete verification evidence.
**Depends on**: Phase 7
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04, VIS-05, VIS-06, VIS-07
**Gap Closure**: Closes audit requirement gaps and missing Phase 5 verification artifact
**Success Criteria** (what must be TRUE):
  1. VIS-01 through VIS-07 are all implemented and verified against current runtime behavior
  2. `.planning/phases/05-visualization/*-VERIFICATION.md` exists and documents pass/fail evidence for each VIS requirement
  3. `.planning/REQUIREMENTS.md` traceability marks VIS-01 through VIS-07 as Complete
**Plans**: 1 plan

Plans:
- [x] 08-01-PLAN.md — Reconcile visualization requirements, fill implementation gaps, and produce Phase 5 verification artifact

### Phase 9: Regression Test Wiring Recovery
**Goal**: Restore cross-phase test wiring so automated regression checks compile and run cleanly.
**Depends on**: Phase 8
**Requirements**: Milestone integration closure (test compile baseline)
**Gap Closure**: Closes audit integration gap blocking automated regression verification
**Success Criteria** (what must be TRUE):
  1. Test targets compile without stale symbol/signature errors
  2. `StatusItemTitleFormatter` and `ContextMenuActions` test wiring aligns with current production interfaces
  3. Regression suite can run to completion in CI/local verification flow
**Plans**: 1 plan

Plans:
- [x] 09-01-PLAN.md — Repair stale test references and re-establish compile-green regression baseline

### Phase 10: True ICMP Support
**Goal:** Enable real ICMP ping when running outside App Store sandbox, with automatic detection and graceful UI hiding when sandboxed.
**Depends on**: Phase 9
**Requirements**: HOST-11
**Success Criteria** (what must be TRUE):
  1. App detects sandbox status at runtime via environment check
  2. ICMPPinger service implements raw socket ping with proper timeout handling
  3. PingMethod.icmp case available and functional when not sandboxed
  4. ICMP option hidden from host configuration UI when sandboxed
  5. Existing TCP/UDP/ICMP-simulated methods unchanged
**Plans**: 4 plans

Plans:
- [x] 10-01-PLAN.md — SandboxDetector utility and ICMPPacket structures
- [x] 10-02-PLAN.md — ICMPPinger service with non-privileged socket ping
- [x] 10-03-PLAN.md — PingMethod.icmp case, PingService routing, and AddHostSheet filtering
- [x] 10-04-PLAN.md — Human verification checkpoint for ICMP support end-to-end

### Phase 11: Tech Debt Closure

**Goal:** Close non-critical v1.0 tech debt so production wiring and active settings UX are fully aligned with implemented capabilities.
**Depends on:** Phase 10
**Requirements:** Debt closure follow-up from v1.0 milestone audit
**Success Criteria** (what must be TRUE):
  1. ConnectionSweeper is wired into active TCP/UDP ping lifecycle (not orphaned)
  2. Active Settings flow includes per-host notification override configuration path
  3. Unused legacy HostSettingsView is removed from the codebase
  4. Planning summaries use consistent `Sources/PingScope` source path references
**Plans:** 4 plans

Plans:
- [x] 11-01-PLAN.md — Wire ConnectionSweeper into production ping lifecycle with regression coverage
- [x] 11-02-PLAN.md — Add active settings host-level notification override editor and persistence tests
- [x] 11-03-PLAN.md — Remove legacy HostSettingsView and normalize planning summary path conventions
- [x] 11-04-PLAN.md — Run debt-closure verification checks and human acceptance checkpoint

**Details:**
This phase intentionally targets non-blocking debt identified by the v1.0 audit to reduce maintenance overhead and tighten runtime/UX traceability before future feature work.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 4/4 | Complete | 2026-02-14 |
| 2. Menu Bar & State | 4/4 | Complete | 2026-02-14 |
| 3. Host Monitoring | 9/9 | Complete | 2026-02-14 |
| 4. Display Modes | 5/5 | Complete | 2026-02-15 |
| 5. Visualization | 3/3 | Complete | 2026-02-15 |
| 6. Notifications & Settings | 8/8 | Complete | 2026-02-16 |
| 7. Settings Focus | 4/4 | Complete | 2026-02-16 |
| 8. Visualization Requirement Reconciliation & Verification | 1/1 | Complete | 2026-02-16 |
| 9. Regression Test Wiring Recovery | 1/1 | Complete | 2026-02-16 |
| 10. True ICMP Support | 4/4 | Complete | 2026-02-16 |
| 11. Tech Debt Closure | 4/4 | Complete | 2026-02-17 |

---
*Roadmap created: 2026-02-13*
*Phase 1 planned: 2026-02-14*
*Phase 3 planned: 2026-02-14*
*Phase 4 planned: 2026-02-14*
*Phase 9 planned: 2026-02-16*
*Phase 10 planned: 2026-02-16*
*Phase 11 planned: 2026-02-16*

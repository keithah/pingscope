# Roadmap: PingScope

## Milestones

- ✅ **v1.0 MVP** - Phases 1-12 (shipped 2026-02-17)
- ✅ **v1.1 App Store Release** - Phases 13-16 (shipped 2026-02-18)
- 🚧 **v2.0 Widgets & Cross-Platform** - Phases 17-18 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-12) - SHIPPED 2026-02-17</summary>

Complete menu bar ping monitor rewrite with stable async architecture, multi-host monitoring, visualization, and true ICMP support.

**Key accomplishments:**
- Async-first architecture with Swift Concurrency eliminating race conditions and false timeouts
- Multi-host monitoring with auto-detected gateway, configurable intervals, and per-host thresholds
- Real-time latency graph visualization with 1hr/10m/5m/1m time ranges and history table
- Full/compact display modes with stay-on-top floating window option
- 7 alert types with per-host notification overrides and cooldown behavior
- True ICMP ping support when running outside App Store sandbox
- Comprehensive test coverage with automated regression suite

**Stats:** 236 files changed, ~8000 LOC Swift, 12 phases, 50 plans, 226 commits over 5 months

See: [.planning/milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)

</details>

<details>
<summary>✅ v1.1 App Store Release (Phases 13-16) - SHIPPED 2026-02-18</summary>

PingScope submitted to Mac App Store with dual-distribution strategy (App Store + Developer ID).

**Key accomplishments:**
- Dual-build Xcode configuration supporting both App Store (sandboxed) and Developer ID (non-sandboxed) distributions
- Complete App Store compliance: privacy manifest, export declarations, age rating, and privacy nutrition label
- Professional App Store listing: optimized metadata, 5 screenshots at 2880x1800, review notes
- First build (v1.0 build 1) uploaded and submitted for App Store Review

**Stats:** 4 phases, 13 plans, build in review as of 2026-02-17

See: [.planning/milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)

</details>

### 🚧 v2.0 Widgets & Cross-Platform (In Progress)

**Milestone Goal:** Add WidgetKit support for macOS and refactor architecture for future cross-platform expansion.

- [ ] **Phase 17: Widget Foundation** - Working widgets (small/medium/large) displaying live ping status
- [ ] **Phase 18: Cross-Platform Architecture** - Platform-separated codebase ready for iOS

## Phase Details

### Phase 17: Widget Foundation
**Goal**: Users can view ping status and latency in macOS widgets (desktop and Notification Center)
**Depends on**: Phase 16 (App Store Release complete)
**Requirements**: WI-01, WI-02, WI-03, WI-04, WI-05, WI-06, WI-07, WUI-01, WUI-02, WUI-03, WUI-04, WUI-05, WUI-06, WUI-07, WUI-08, WUI-09, WUI-10
**Success Criteria** (what must be TRUE):
  1. User can add small widget showing single host status with color-coded indicator and current latency
  2. User can add medium widget showing multi-host summary (3 hosts) with status indicators
  3. User can add large widget showing all configured hosts with statistics (packet loss, avg latency)
  4. Widget displays last update timestamp and shows stale data indicator when >15 minutes old
  5. Tapping any widget opens main PingScope app
  6. Widgets update within 5-15 minutes showing current ping status from running app
  7. Widgets display correctly in both light and dark mode
**Plans**: 3 plans

Plans:
- [ ] 17-01-PLAN.md — Widget infrastructure (App Groups, extension target, WidgetDataStore)
- [ ] 17-02-PLAN.md — Widget UI (TimelineProvider, small/medium/large views)
- [ ] 17-03-PLAN.md — Integration and verification (deep linking, app wiring, testing)

### Phase 17.1: use xcode cloud with this and fastlane to automate builds and not require me to build it locally or use xcode locally (INSERTED)

**Goal:** Pushing to main triggers a TestFlight build automatically; pushing a release/x.y.z tag triggers App Store submission — no manual Xcode or App Store Connect steps required
**Depends on:** Phase 17
**Requirements:** CI-01, CI-02, CI-03, CI-04, CI-05
**Plans:** 2 plans

Plans:
- [ ] 17.1-01-PLAN.md — Fix ci_scripts and create Fastlane setup (Gemfile, Appfile, Fastfile)
- [ ] 17.1-02-PLAN.md — Configure Xcode Cloud workflows and verify end-to-end pipeline

### Phase 18: Cross-Platform Architecture
**Goal**: Codebase is organized for future iOS support with clean platform separation
**Depends on**: Phase 17
**Requirements**: XP-01, XP-02, XP-03, XP-04, XP-05, XP-06, XP-07, XP-08
**Success Criteria** (what must be TRUE):
  1. Platform-specific code (MenuBarViewModel, AppDelegate) organized in macOS/ folder
  2. Shared models and services (PingService, HostStore, Host, PingResult) organized in Shared/ folder
  3. Widget extension code organized in WidgetExtension/ folder
  4. PingService, HostStore, and data models build without warnings on macOS target
  5. Compiler directives (#if os) used in fewer than 10 locations across codebase
  6. macOS app and widgets continue working after reorganization (validated via manual testing)
**Plans**: TBD

Plans:
- [ ] 18-01: TBD
- [ ] 18-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 17 → 18

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-12. v1.0 MVP | v1.0 | 50/50 | Complete | 2026-02-17 |
| 13. Xcode Infrastructure Setup | v1.1 | 4/4 | Complete | 2026-02-16 |
| 14. Privacy and Compliance | v1.1 | 3/3 | Complete | 2026-02-17 |
| 15. App Store Metadata and Assets | v1.1 | 2/2 | Complete | 2026-02-17 |
| 16. Submission and Distribution | v1.1 | 4/4 | Complete | 2026-02-18 |
| 17. Widget Foundation | v2.0 | 0/3 | Not started | - |
| 18. Cross-Platform Architecture | v2.0 | 0/2 | Not started | - |

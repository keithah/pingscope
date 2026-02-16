# Requirements: PingMonitor

**Defined:** 2026-02-13
**Core Value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Menu Bar Display

- [ ] **MENU-01**: Menu bar shows color-coded status dot (green/yellow/red/gray)
- [ ] **MENU-02**: Menu bar shows ping time in milliseconds below status dot
- [ ] **MENU-03**: Left-click opens popover/window with full interface
- [ ] **MENU-04**: Right-click (or Ctrl+click, Cmd+click) opens context menu
- [ ] **MENU-05**: Context menu allows host switching
- [ ] **MENU-06**: Context menu shows mode toggles (compact, stay-on-top)
- [ ] **MENU-07**: Context menu includes Settings and Quit options

### Host Monitoring

- [ ] **HOST-01**: Monitor multiple hosts simultaneously (Google DNS, Cloudflare, Gateway + custom)
- [ ] **HOST-02**: Auto-detect default gateway via SystemConfiguration
- [ ] **HOST-03**: Support ICMP ping method (simulated via TCP connections to ports 53, 80, 443, 22, 25)
- [ ] **HOST-04**: Support UDP ping method (default port 53)
- [ ] **HOST-05**: Support TCP ping method (default port 80)
- [ ] **HOST-06**: Per-host configurable ping interval
- [ ] **HOST-07**: Per-host configurable timeout
- [ ] **HOST-08**: Per-host configurable thresholds (good/warning/error)
- [ ] **HOST-09**: Host management (add, edit, delete custom hosts)
- [ ] **HOST-10**: Default hosts cannot be deleted (Google, Cloudflare, Gateway)
- [ ] **HOST-11**: True ICMP ping when running outside sandbox; ICMP option hidden when sandboxed

### Visualization

- [ ] **VIS-01**: Real-time latency graph with line and gradient fill
- [ ] **VIS-02**: Graph shows data points for individual pings
- [ ] **VIS-03**: Graph has configurable time filter (1min, 5min, 10min, 1hour)
- [ ] **VIS-04**: History table shows timestamp, host, ping time, status
- [ ] **VIS-05**: History table scrollable with recent results first
- [ ] **VIS-06**: Statistics display: transmitted, received, packet loss %
- [ ] **VIS-07**: Statistics display: min/avg/max/stddev latency

### Display Modes

- [x] **DISP-01**: Full view mode (450x500) with host tabs, graph, history
- [x] **DISP-02**: Compact view mode (280x220) with condensed display
- [x] **DISP-03**: Toggle between full and compact modes
- [x] **DISP-04**: Stay-on-top floating window option
- [x] **DISP-05**: Floating window is borderless and movable
- [x] **DISP-06**: Window positions near menu bar icon when opened

### Notifications

- [ ] **NOTF-01**: Request notification permission from user
- [ ] **NOTF-02**: Alert when host transitions from good to no response
- [ ] **NOTF-03**: Alert when ping exceeds configurable threshold
- [ ] **NOTF-04**: Alert when host recovers from failure
- [ ] **NOTF-05**: Alert on performance degradation (latency increases by X%)
- [ ] **NOTF-06**: Alert on intermittent failures (N failures in M-ping window)
- [ ] **NOTF-07**: Alert on network change (gateway IP changes)
- [ ] **NOTF-08**: Alert when all hosts fail (internet loss)
- [ ] **NOTF-09**: Per-host notification settings
- [ ] **NOTF-10**: Global notification enable/disable

### Settings & Persistence

- [x] **SETT-01**: Settings panel for host management
- [x] **SETT-02**: Settings panel for notification configuration
- [x] **SETT-03**: Settings panel for display preferences
- [x] **SETT-04**: Persist all settings via UserDefaults
- [x] **SETT-05**: Settings survive app restart
- [x] **SETT-06**: Privacy manifest declares UserDefaults usage

### Core Technical

- [ ] **TECH-01**: Use Swift Concurrency (async/await) throughout — no DispatchSemaphore
- [ ] **TECH-02**: Proper NWConnection lifecycle management (no stale connections)
- [ ] **TECH-03**: Accurate timeout handling (no false timeouts from race conditions)
- [ ] **TECH-04**: Actor-isolated PingService for thread-safe concurrent pings
- [ ] **TECH-05**: @MainActor ViewModels for UI thread safety
- [ ] **TECH-06**: Support macOS 13.0+ (Ventura)
- [ ] **TECH-07**: App Store sandbox compatible (no raw ICMP sockets)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Widget

- **WIDG-01**: Small widget showing primary host status
- **WIDG-02**: Medium widget showing 3 hosts horizontally
- **WIDG-03**: Large widget showing all hosts in detail

### Data Export

- **EXPT-01**: Export ping history to CSV format
- **EXPT-02**: Export ping history to JSON format
- **EXPT-03**: Export ping history to plain text format
- **EXPT-04**: Time range filter for exports (last hour, 24h, week, all)
- **EXPT-05**: Per-host filtering for exports

### Quality Metrics

- **QUAL-01**: Jitter measurement (standard deviation of latency)
- **QUAL-02**: Connection quality score (0-100)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| HTTP/HTTPS endpoint monitoring | Different protocol, adds complexity — focus on latency |
| Webhook integration | Power user feature, adds external dependencies |
| Cloud sync | No need for local utility app |
| Multi-platform | macOS only, native quality over portability |
| AppleScript/Shortcuts | Can add later without architectural changes |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TECH-01 | Phase 1 | Complete |
| TECH-02 | Phase 1 | Complete |
| TECH-03 | Phase 1 | Complete |
| TECH-04 | Phase 1 | Complete |
| TECH-05 | Phase 1 | Complete |
| TECH-06 | Phase 1 | Complete |
| TECH-07 | Phase 1 | Complete |
| MENU-01 | Phase 2 | Complete |
| MENU-02 | Phase 2 | Complete |
| MENU-03 | Phase 2 | Complete |
| MENU-04 | Phase 2 | Complete |
| MENU-05 | Phase 2 | Complete |
| MENU-06 | Phase 2 | Complete |
| MENU-07 | Phase 2 | Complete |
| HOST-01 | Phase 3 | Complete |
| HOST-02 | Phase 3 | Complete |
| HOST-03 | Phase 3 | Complete |
| HOST-04 | Phase 3 | Complete |
| HOST-05 | Phase 3 | Complete |
| HOST-06 | Phase 3 | Complete |
| HOST-07 | Phase 3 | Complete |
| HOST-08 | Phase 3 | Complete |
| HOST-09 | Phase 3 | Complete |
| HOST-10 | Phase 3 | Complete |
| DISP-01 | Phase 4 | Complete |
| DISP-02 | Phase 4 | Complete |
| DISP-03 | Phase 4 | Complete |
| DISP-04 | Phase 4 | Complete |
| DISP-05 | Phase 4 | Complete |
| DISP-06 | Phase 4 | Complete |
| VIS-01 | Phase 5 | Complete |
| VIS-02 | Phase 5 | Complete |
| VIS-03 | Phase 5 | Complete |
| VIS-04 | Phase 5 | Complete |
| VIS-05 | Phase 5 | Complete |
| VIS-06 | Phase 5 | Complete |
| VIS-07 | Phase 5 | Complete |
| NOTF-01 | Phase 6 | Complete |
| NOTF-02 | Phase 6 | Complete |
| NOTF-03 | Phase 6 | Complete |
| NOTF-04 | Phase 6 | Complete |
| NOTF-05 | Phase 6 | Complete |
| NOTF-06 | Phase 6 | Complete |
| NOTF-07 | Phase 6 | Complete |
| NOTF-08 | Phase 6 | Complete |
| NOTF-09 | Phase 6 | Complete |
| NOTF-10 | Phase 6 | Complete |
| SETT-01 | Phase 6 | Complete |
| SETT-02 | Phase 6 | Complete |
| SETT-03 | Phase 6 | Complete |
| SETT-04 | Phase 6 | Complete |
| SETT-05 | Phase 6 | Complete |
| SETT-06 | Phase 6 | Complete |
| HOST-11 | Phase 10 | Planned |

**Coverage:**
- v1 requirements: 44 total
- Mapped to phases: 44
- Unmapped: 0

---
*Requirements defined: 2026-02-13*
*Last updated: 2026-02-16 after Phase 8 visualization reconciliation*

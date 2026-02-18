# Requirements: PingScope v2.0

**Defined:** 2026-02-17
**Core Value:** Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.

## v2.0 Requirements

Requirements for WidgetKit and cross-platform architecture milestone. Each maps to roadmap phases.

### Widget Infrastructure

- [ ] **WI-01**: App Groups entitlement configured with correct Team ID prefix for macOS Sequoia
- [ ] **WI-02**: Shared UserDefaults accessible from both main app and widget extension
- [ ] **WI-03**: Widget Extension target created in Xcode with proper bundle ID and entitlements
- [ ] **WI-04**: WidgetDataStore service writes ping results to shared UserDefaults
- [ ] **WI-05**: WidgetCenter reloadTimelines() called after UserDefaults writes
- [ ] **WI-06**: TimelineProvider reads cached ping data from shared UserDefaults
- [ ] **WI-07**: Timeline entries spaced 5+ minutes apart to respect system budget (40-70/day)

### Widget UI

- [ ] **WUI-01**: Small widget displays single host status with color-coded indicator
- [ ] **WUI-02**: Small widget shows current ping latency value
- [ ] **WUI-03**: Medium widget displays multi-host summary (3 hosts horizontal)
- [ ] **WUI-04**: Medium widget shows status indicators for each host
- [ ] **WUI-05**: Large widget displays all configured hosts in list format
- [ ] **WUI-06**: Large widget shows statistics (packet loss, avg latency) per host
- [ ] **WUI-07**: All widget sizes display last update timestamp
- [ ] **WUI-08**: Tapping any widget opens main app
- [ ] **WUI-09**: Widgets show stale data indicator when >15 minutes old
- [ ] **WUI-10**: Widget views support both light and dark mode

### Cross-Platform Architecture

- [ ] **XP-01**: Platform-specific code organized in macOS/ folder structure
- [ ] **XP-02**: Shared models and services organized in Shared/ folder structure
- [ ] **XP-03**: Widget extension code organized in WidgetExtension/ folder
- [ ] **XP-04**: MenuBarViewModel remains macOS-specific (not shared)
- [ ] **XP-05**: PingService, HostStore, and models accessible from all targets
- [ ] **XP-06**: Compiler directives (#if os) minimized to <10 occurrences
- [ ] **XP-07**: Platform abstractions use protocols rather than conditionals where possible
- [ ] **XP-08**: All shared code builds without warnings on macOS target

## Future Requirements

Deferred to v2.1+ based on user validation and demand.

### Widget Enhancements

- **WUI-E01**: Mini latency graph visualization in medium/large widgets
- **WUI-E02**: Host-specific deep links with URL parameters
- **WUI-E03**: Widget configuration intents for user customization
- **WUI-E04**: Staleness indicators with gradual dimming

### iOS Support

- **IOS-01**: iOS app with tab-based navigation
- **IOS-02**: iOS widgets (Home Screen, Lock Screen)
- **IOS-03**: iOS-specific ViewModel (AppViewModel)
- **IOS-04**: iOS App Store listing and submission
- **IOS-05**: Shared test suite for iOS and macOS

### Advanced Features

- **ADV-01**: Widget interaction zones for per-host actions
- **ADV-02**: Widget animation and transitions
- **ADV-03**: Accessibility enhancements for widgets
- **ADV-04**: Widget size adaptation for different screen densities

## Out of Scope

Explicitly excluded from v2.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| iOS app shipping | v2.0 is architecture prep only; iOS ships in v3.0+ |
| Real-time widget updates | System budget prevents continuous updates (40-70/day limit) |
| Network operations in widgets | Runtime constraints prevent ping execution in widget process |
| Widget configuration UI | Complexity vs unclear user demand; defer until core widgets validated |
| watchOS support | Platform not prioritized; focus on macOS + iOS |
| macOS 14+ @Observable migration | Keep macOS 13 compatibility; defer to v3.0 |
| Custom widget refresh intervals | System-controlled; user configuration not supported by WidgetKit |
| Interactive widget controls | Limited value for ping monitoring use case |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| WI-01 | Phase 17 | Pending |
| WI-02 | Phase 17 | Pending |
| WI-03 | Phase 17 | Pending |
| WI-04 | Phase 17 | Pending |
| WI-05 | Phase 17 | Pending |
| WI-06 | Phase 17 | Pending |
| WI-07 | Phase 17 | Pending |
| WUI-01 | Phase 17 | Pending |
| WUI-02 | Phase 17 | Pending |
| WUI-03 | Phase 17 | Pending |
| WUI-04 | Phase 17 | Pending |
| WUI-05 | Phase 17 | Pending |
| WUI-06 | Phase 17 | Pending |
| WUI-07 | Phase 17 | Pending |
| WUI-08 | Phase 17 | Pending |
| WUI-09 | Phase 17 | Pending |
| WUI-10 | Phase 17 | Pending |
| XP-01 | Phase 18 | Pending |
| XP-02 | Phase 18 | Pending |
| XP-03 | Phase 18 | Pending |
| XP-04 | Phase 18 | Pending |
| XP-05 | Phase 18 | Pending |
| XP-06 | Phase 18 | Pending |
| XP-07 | Phase 18 | Pending |
| XP-08 | Phase 18 | Pending |

**Coverage:**
- v2.0 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-17 after roadmap creation*

# PingScope

## What This Is

A macOS menu bar application that monitors network connectivity by pinging configurable hosts. It displays real-time latency in the menu bar with color-coded status, provides historical graphs and ping history in a dropdown interface, and supports multiple hosts including auto-detected default gateway. Available via both Mac App Store (sandboxed) and direct download (with true ICMP support).

## Core Value

Reliable, accurate ping monitoring that users can trust — no false timeouts, no stale connections, no crashes.

## Requirements

### Validated

- Menu bar status display with color-coded dot and ping time text — v1.0
- Multiple host monitoring (Google DNS, Cloudflare DNS, Default Gateway) — v1.0
- Four ping methods: True ICMP (non-sandbox only), ICMP-simulated (TCP), UDP, TCP — v1.0
- Auto-detection of default gateway via SystemConfiguration — v1.0
- Real-time latency graph visualization — v1.0
- Ping history list with timestamps — v1.0
- Full view mode (450x500) with host tabs, graph, history — v1.0
- Compact view mode (280x220) with condensed display — v1.0
- Stay-on-top floating window option — v1.0
- Settings panel for host management — v1.0
- 7 notification alert types (no response, high latency, recovery, degradation, intermittent, network change, internet loss) — v1.0
- Persistent settings via UserDefaults — v1.0
- Left-click opens popover, right-click shows context menu — v1.0
- Statistics display (transmitted, received, packet loss, min/avg/max/stddev) — v1.0

- Xcode dual-build infrastructure (App Store + Developer ID) — v1.1
- Privacy manifest and App Store compliance — v1.1
- App Store metadata and screenshots — v1.1
- App Store submission and review process — v1.1

### Active

(Ready for next milestone)

### Out of Scope

- OAuth/cloud sync — not needed for local utility app
- Multi-platform — macOS only
- Widget extension — defer to v3
- Data export — defer to v3

## Current Milestone: None (Between Milestones)

Ready to plan next milestone with `/gsd:new-milestone`.

## Context

**v1.0 shipped (2026-02-17):**
- Complete rewrite from single-file to modular MVVM architecture
- Async/await eliminating race conditions and false timeouts
- Multi-host monitoring with gateway detection
- Real-time visualization with full/compact modes
- 7 notification alert types with per-host overrides
- True ICMP support for non-sandboxed builds

**Current distribution:**
- Developer ID signed releases via GitHub Actions
- Direct download from GitHub releases
- Not yet in Mac App Store

**v1.1 shipped (2026-02-18):**
- Dual-channel distribution established (App Store + Developer ID)
- Xcode project with dual build schemes (PingScope-AppStore, PingScope-DeveloperID)
- App Store listing created with metadata and 5 professional screenshots
- First build submitted for App Store Review (in review as of 2026-02-17)
- Both builds use same codebase with sandbox-aware configuration

## Constraints

- **Platform:** macOS 13.0+ (Ventura) — required for modern SwiftUI features
- **Distribution:** Dual-channel — App Store (sandboxed) and Developer ID (non-sandboxed)
- **Bundle ID:** com.hadm.pingscope — consistent across both distributions
- **Frameworks:** SwiftUI, AppKit, Network.framework, SystemConfiguration — no external dependencies
- **App Store:** Free tier, sandboxed, no privileged operations
- **Signing:** Requires App Store distribution certificate + Developer ID certificate

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Swift Concurrency over GCD semaphores | Eliminates race conditions causing false timeouts | ✓ Good (v1.0) |
| Modular file structure over single file | Maintainability, testability, separation of concerns | ✓ Good (v1.0) |
| Dual-mode ICMP support | True ICMP when not sandboxed, hidden when sandboxed | ✓ Good (v1.0) |
| Free App Store pricing | Maximize adoption, monetize later if needed | ✓ Good (v1.1) |
| Single codebase for both distributions | Reduces maintenance, uses build configurations | ✓ Good (v1.1) |
| Manual ICNS creation for App Store icons | Xcode asset catalog compilation incomplete | ⚠️ Workaround (v1.1) |
| Use Transporter for App Store uploads | xcrun altool deprecated by Apple | ✓ Good (v1.1) |

## Current State

**Version:** v1.1 in App Store Review (submitted 2026-02-17), v1.0 available via direct download
**Codebase:** ~8000 LOC Swift, 54 source files
**Tech stack:** SwiftUI, AppKit, Network.framework, SystemConfiguration
**Distribution:** Dual-channel (App Store pending approval, Developer ID active)
**Known issues:** CI/CD automation deferred (Plan 16-04), manual release workflow documented

---
*Last updated: 2026-02-18 after v1.1 milestone completion*

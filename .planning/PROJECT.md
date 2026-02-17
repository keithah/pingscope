# PingMonitor

## What This Is

A macOS menu bar application that monitors network connectivity by pinging configurable hosts. It displays real-time latency in the menu bar with color-coded status, provides historical graphs and ping history in a dropdown interface, and supports multiple hosts including auto-detected default gateway. This is a rewrite of an existing single-file implementation to be more stable, efficient, and maintainable.

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

### Active

- Data export (CSV, JSON, Text)
- Widget extension (small/medium/large sizes)

### Out of Scope

- OAuth/cloud sync — not needed for local utility app
- Multi-platform — macOS only

## Context

**Existing implementation:** A ~125KB single-file Swift app (`~/src/old_pingmonitor/PingMonitor.swift`) that works but has issues:
- Monolithic structure makes maintenance difficult
- Uses `DispatchSemaphore` for synchronous waiting which causes race conditions
- Timeout handlers race with connection state handlers causing false timeouts
- Connections not always properly cleaned up causing stale connections
- No clear separation of concerns

**Rewrite goals:**
- Modular MVVM architecture matching the documentation in this repo
- Swift Concurrency (async/await) instead of semaphores for cleaner async handling
- Proper connection lifecycle management to prevent stale connections
- Accurate timeout handling to eliminate false timeouts
- Lower CPU and memory usage
- Same UI/UX as existing app — users shouldn't notice the difference except improved reliability

**Reference documentation:**
- `ARCHITECTURE.md` — System architecture and component interactions
- `MODELS.md` — Data model specifications
- `SERVICES.md` — Service layer documentation
- `VIEWS.md` — View layer and UI components
- `CONFIGURATION.md` — Constants and configuration options

## Constraints

- **Platform:** macOS 13.0+ (Ventura) — required for WidgetKit and modern SwiftUI features
- **Sandbox:** Dual-mode distribution — App Store (sandboxed, TCP/UDP simulation) and Developer ID (non-sandboxed, true ICMP enabled)
- **Bundle ID:** com.hadm.pingmonitor — maintain existing identifier
- **Frameworks:** SwiftUI, AppKit, Network.framework, SystemConfiguration — no external dependencies

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use Swift Concurrency over GCD semaphores | Eliminates race conditions causing false timeouts | — Pending |
| Modular file structure over single file | Maintainability, testability, separation of concerns | — Pending |
| Defer widget to v2 | Focus on core app stability first | — Pending |
| Dual-mode ICMP support | True ICMP when not sandboxed, hidden when sandboxed | — Pending |

## Current State

**Version:** v1.0 shipped 2026-02-17
**Codebase:** ~8000 LOC Swift, 54 source files
**Tech stack:** SwiftUI, AppKit, Network.framework, SystemConfiguration

---
*Last updated: 2026-02-17 after v1.0 milestone*

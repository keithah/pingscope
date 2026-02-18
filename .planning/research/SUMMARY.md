# Project Research Summary

**Project:** PingScope v2.0 - WidgetKit & Cross-Platform
**Domain:** macOS menu bar network monitoring with widgets and iOS preparation
**Researched:** 2026-02-17
**Confidence:** HIGH

## Executive Summary

PingScope v2.0 adds WidgetKit widgets and cross-platform architecture to the existing v1.1 macOS menu bar network monitoring app. The research reveals this is a **data sharing challenge** rather than a UI challenge. Widgets run in separate processes and cannot perform network operations due to system constraints (40-70 update/day budget, <1 second runtime). The recommended approach uses App Groups + shared UserDefaults as the data pipeline: the main app performs continuous ping monitoring and writes results to shared storage, while widgets display cached status through WidgetKit's TimelineProvider.

The key architectural decision is **platform separation over premature abstraction**. Models and services (PingService, HostStore) are fully shareable across macOS, iOS, and widgets. ViewModels should be shared at the business logic level but split at the platform level (MenuBarViewModel stays macOS-only; future iOS needs separate AppViewModel). This approach balances code reuse with platform-specific strengths while avoiding conditional compilation sprawl.

**Critical risks:** Widget update budget exhaustion from over-refreshing, macOS Sequoia App Groups requiring Team ID prefix (not `group.` like iOS), and network calls blocking widget timeline rendering. These are all preventable with proper architecture in Phase 1. The cross-platform preparation sets up the codebase for future iOS support without requiring iOS implementation in v2.0.

## Key Findings

### Recommended Stack

PingScope benefits from Swift 6 concurrency, WidgetKit (macOS 11+), and modern SwiftUI patterns. The existing v1.1 stack (Swift Concurrency, Network.framework, ObservableObject, UserDefaults) remains solid—v2.0 adds WidgetKit infrastructure and App Groups for data sharing.

**Core technologies:**
- **WidgetKit + TimelineProvider**: Apple's widget framework, required for macOS widgets — standard pattern since macOS 11
- **App Groups + UserDefaults**: Data sharing between app and widget extension — uses Team ID prefix on macOS (not `group.` prefix)
- **Network.framework**: TCP/UDP ping operations — already implemented, cross-platform (macOS + iOS)
- **SwiftUI + ObservableObject**: State management — keep existing pattern for macOS 13 compatibility (skip @Observable)
- **Swift Concurrency (async/await)**: Actor-based services — existing architecture is correct, fully shareable

**v2.0-specific additions:**
- Widget Extension target (Xcode-only, SPM cannot create extensions)
- Shared UserDefaults with suite name for app-widget communication
- Compiler directives (`#if os(macOS)`) for platform isolation (minimize usage)
- Asset catalog for widget icons

**Critical constraint:** WidgetKit imposes 40-70 updates/day budget. Widgets cannot run continuous monitoring. Main app writes to shared storage on every ping; widgets refresh timeline every 5-15 minutes to read cached data.

### Expected Features

Users expect widgets to show **glanceable network status**, not real-time updates. The research identifies clear table stakes vs competitive features.

**Must have (table stakes):**
- Small/Medium/Large widget size variants — users expect all 3 sizes
- Visual status indicators (color-coded dots) — universal in network monitoring
- Ping time display — core value proposition
- Tap widget to open app — standard interaction
- Update timestamps — users need to trust freshness

**Should have (competitive):**
- Multi-host summary view in medium widget — most competitors show single host
- Shared data pipeline via App Groups — required for widget functionality
- Platform UI separation (macOS-specific + shared layer) — foundation for iOS

**Defer (v2.x+):**
- Mini latency graph in widgets — validates user interest in trends after core widgets work
- Host-specific deep links — add after confirming users tap widgets
- iOS/iPadOS support — requires App Store iOS build, separate milestone
- Widget intents (user configuration) — significant complexity, unclear demand

**Anti-features to avoid:**
- Real-time continuous updates (exhausts budget)
- Interactive controls in widgets (complexity, limited value)
- Custom widget refresh intervals (system controlled)

### Architecture Approach

The architecture uses **actor-based services + @MainActor ViewModels + coordinator pattern**. This existing structure works well and should be preserved. The v2.0 addition is a shared data layer accessible to widgets.

**Major components:**

1. **WidgetExtension target** — Separate build target with TimelineProvider, widget views, reads shared UserDefaults
2. **Shared data models** — Move Host, PingResult to shared code accessible by app + widget
3. **WidgetDataStore service** — Encapsulates UserDefaults(suiteName:) access, called by main app after ping results
4. **Platform separation** — macOS/ folder for menu bar code, Shared/ folder for models/services/ViewModels
5. **WidgetCenter integration** — AppDelegate calls `WidgetCenter.shared.reloadAllTimelines()` on state changes (not every ping)

**Data flow:** PingService (actor) → PingScheduler → AppDelegate.ingestResult() → [MenuBarViewModel + WidgetDataStore.save()] → WidgetCenter.reload() → Widget TimelineProvider reads UserDefaults → Widget views

**Cross-platform pattern:** Share models (100%), services (100%), ViewModels (business logic 100%, presentation layer split), views (leaf views 80%, root views 0%). Use `#if os()` only for platform API differences (SystemConfiguration on macOS, alternative on iOS).

### Critical Pitfalls

1. **Widget update budget exhaustion** — Updating widgets every few minutes exhausts 40-70/day budget, causing widgets to freeze. **Avoidance:** Timeline entries spaced 5-15 minutes minimum, main app writes to shared storage on every ping (data fresh), widget shows cached data.

2. **App Groups Team ID prefix on macOS Sequoia** — Using iOS-style `group.` prefix fails silently on macOS. **Avoidance:** macOS uses `<TEAMID>.com.hadm.pingscope.shared` format, iOS uses `group.com.hadm.pingscope.shared`, conditional entitlements if supporting both.

3. **Network calls blocking widget timeline** — Attempting to ping hosts in widget causes "Unable to Load Widget" errors (10-15 second timeout, ping operations exceed this). **Avoidance:** Widget displays pre-computed results from shared UserDefaults, main app performs all network operations.

4. **Premature cross-platform abstraction** — Scattering `#if os(macOS)` conditionals throughout ViewModels creates maintenance burden. **Avoidance:** Platform-specific ViewModels (MenuBarViewModel for macOS, AppViewModel for iOS future), shared business logic in services, file organization separates macOS/ vs Shared/ vs iOS/.

5. **Widget/app state synchronization** — Widgets show stale data if app doesn't trigger reloads. **Avoidance:** `WidgetCenter.shared.reloadTimelines()` called after UserDefaults writes, wrapped in helper function to ensure consistency.

6. **@Observable minimum version lock-in** — Adopting @Observable forces macOS 14+, cutting off macOS 13 users. **Avoidance:** Keep existing ObservableObject for v2.0, maintain macOS 13.0 support.

## Implications for Roadmap

Based on research, suggested 2-phase structure for v2.0:

### Phase 1: Widget Foundation
**Rationale:** Data sharing and widget infrastructure must come first. Widgets require App Groups configuration and shared data access before any UI can work. This phase addresses the highest-risk pitfalls (budget exhaustion, App Groups misconfiguration, network blocking).

**Delivers:** Working widgets (small/medium/large) displaying live ping status from main app

**Addresses:**
- Widget size variants (table stakes from FEATURES.md)
- Real-time status display via shared data
- Visual status indicators (reuse existing logic)
- App Group container setup (required for widget access)
- Timeline provider with 5-15 min refresh

**Avoids:**
- Widget update budget exhaustion (timeline spacing)
- App Groups Team ID mismatch (macOS-specific configuration)
- Network calls blocking timeline (widgets read only)
- Widget/app state drift (WidgetCenter reload triggers)

**Stack elements:**
- WidgetKit framework
- TimelineProvider protocol
- App Groups entitlement
- UserDefaults(suiteName:)

**Architecture:**
- Widget Extension target (Xcode)
- WidgetDataStore service
- TimelineEntry model
- Widget views (small/medium/large)

**Research flags:** None — WidgetKit patterns are well-documented. Standard implementation.

### Phase 2: Cross-Platform Architecture
**Rationale:** With widgets working, restructure codebase for future iOS support. This phase doesn't ship iOS but sets up platform separation so iOS can be added later without major refactoring. Addresses premature abstraction pitfall by establishing clear boundaries.

**Delivers:** Platform-separated codebase (macOS/, Shared/, future iOS/) with shared ViewModels and services

**Addresses:**
- Platform UI separation (competitive feature)
- Shared ViewModels extracted from macOS code
- Foundation for future iOS/iPadOS support

**Avoids:**
- Premature cross-platform abstraction (file organization, not conditionals)
- Shared ViewModel pollution (MenuBarViewModel stays macOS-only)

**Stack elements:**
- Compiler directives (`#if os(macOS)`)
- Platform abstraction patterns
- Shared Package.swift structure

**Architecture:**
- Folder reorganization (macOS/, Shared/, WidgetExtension/)
- Platform-specific ViewModels
- Shared services remain actors

**Research flags:** None — SwiftUI multiplatform patterns are well-established. Reorganization is low-risk with proper testing.

### Phase Ordering Rationale

- **Widget Foundation first:** Widgets cannot function without data sharing. App Groups setup and WidgetDataStore are prerequisites for any widget UI. Research shows widget budget exhaustion is the #1 pitfall—addressing this in Phase 1 prevents rework.

- **Cross-Platform second:** Restructuring is safer after widgets work. Phase 1 validates the shared data model design. Phase 2 can then extract shared code confidently, knowing what actually needs to be shared vs platform-specific.

- **Defer enhancements:** Mini latency graphs, host-specific deep links, iOS implementation deferred to v2.x+. Research shows these are nice-to-have; core widget functionality validates user demand first.

**Phase dependencies:**
- Phase 1 has no dependencies (can start immediately)
- Phase 2 depends on Phase 1 complete (validates shared models)

**Testing strategy per phase:**
- Phase 1: Monitor widget updates over 48 hours (verify budget), test shared UserDefaults access (verify Team ID prefix), measure timeline provider completion time (verify <2 sec)
- Phase 2: Count `#if os()` occurrences (<10), verify platform VMs cleanly separated, test macOS app + widget still work after reorganization

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Widget Foundation):** WidgetKit is well-documented with clear examples. App Groups + UserDefaults pattern is established. No research needed.
- **Phase 2 (Cross-Platform Architecture):** SwiftUI multiplatform patterns are standard. File organization is straightforward refactoring, not novel architecture.

**No phases require /gsd:research-phase** — All patterns are documented and understood.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | WidgetKit, App Groups, Network.framework all verified in Apple docs and community sources. macOS Sequoia Team ID requirement confirmed in Apple Developer Forums. |
| Features | HIGH | Widget size expectations are WidgetKit standard. Table stakes vs competitive features validated across competitor analysis. Anti-features grounded in system constraints. |
| Architecture | HIGH | Actor-based services + TimelineProvider pattern is established. Data sharing via App Groups is official Apple approach. Cross-platform separation patterns have strong community consensus. |
| Pitfalls | MEDIUM-HIGH | Widget budget exhaustion (HIGH — Apple docs + community), Team ID prefix (HIGH — Apple Forums), network blocking (HIGH — WidgetKit docs), premature abstraction (MEDIUM — community patterns). |

**Overall confidence:** HIGH

### Gaps to Address

- **Widget refresh timing optimization:** Research suggests 5-15 minute intervals, but optimal value depends on user behavior. Phase 1 should implement configurable interval with 5-min default, gather analytics to tune in v2.1.

- **App Groups container size limits:** Research identified 10 MB warning threshold, but macOS-specific limits unclear. Phase 1 should log UserDefaults data size, monitor during beta testing.

- **@Observable adoption timeline:** Research recommends keeping ObservableObject for macOS 13 support. Decision point: v3.0 could bump to macOS 14 and adopt @Observable if user base shifts. Monitor macOS version analytics.

- **iOS timeline differences:** Research notes iOS Lock Screen widgets may have different budget constraints. Validate during iOS implementation (Phase 3+).

- **Widget interaction patterns:** Research defers host-specific deep links. Phase 1 should track widget tap analytics to validate demand for this feature in v2.x.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: WidgetKit, TimelineProvider, App Groups, Network.framework, Swift Concurrency
- Apple Developer Forums: App Groups Team ID requirement (macOS Sequoia), widget budget limits, UserDefaults sharing
- WWDC sessions: WidgetKit strategy, keeping widgets up to date

### Secondary (MEDIUM confidence)
- Community articles: SwiftUI multiplatform architecture (Jesse Squires, Medium), WidgetKit pitfalls (Medium), cross-platform patterns (Kodeco)
- Technical blogs: Widget data sharing (Use Your Loaf), UserDefaults with widgets (SwiftLee), compiler directives (Swift by Sundell)

### Tertiary (LOW confidence)
- Widget budget "400 entry limit" — community reported, not in official docs (needs validation)
- iOS Lock Screen widget budget differences — assumed different, needs iOS testing

**All sources aggregated from:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md

---
*Research completed: 2026-02-17*
*Ready for roadmap: yes*

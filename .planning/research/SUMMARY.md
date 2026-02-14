# Project Research Summary

**Project:** PingMonitor - macOS Menu Bar Network Monitoring App
**Domain:** Native macOS menu bar utility with real-time network connectivity monitoring
**Researched:** 2026-02-13
**Confidence:** HIGH

## Executive Summary

PingMonitor is a macOS menu bar application that monitors network connectivity through real-time latency measurement. Expert implementations prioritize Swift Concurrency over legacy GCD patterns, Network.framework over BSD sockets for sandbox compatibility, and the modern Observation framework for state management. The recommended architecture is MVVM with service layer isolation using actors for thread-safe network operations.

The critical technical decision is to use TCP/UDP connection timing instead of raw ICMP ping, as App Store sandbox restrictions prohibit raw socket access. This constraint is well-documented and accepted in the domain, with production apps like Ping (neat.software) and SimplePing using similar approaches. The architecture must carefully manage NWConnection lifecycle to avoid the two most common failure modes: stale connections that report false success, and DispatchSemaphore deadlocks that cause the previous implementation to fail.

Key risks center on Swift Concurrency integration with Network.framework's callback-based API. The previous app suffered from race conditions between timeout handlers and connection state updates. Mitigation requires structured concurrency patterns (withTaskGroup for timeouts), actor isolation for connection tracking, and always maintaining a pending receive() operation to detect connection failures. Energy impact is a secondary concern - aggressive polling intervals (sub-5 second) cause battery drain complaints and macOS energy warnings.

## Key Findings

### Recommended Stack

The stack reflects 2025 best practices for macOS native development with strong emphasis on Swift 6 concurrency features. The core decision is Swift Concurrency throughout - no GCD or Combine for new code - with Network.framework as the only sandbox-compatible option for TCP/UDP connectivity checking.

**Core technologies:**
- **Swift 6.x**: Modern concurrency with strict data race checking, required for async/await patterns
- **SwiftUI (macOS 13+)**: MenuBarExtra API for declarative menu bar integration, hybrid with AppKit where needed
- **Network.framework**: Apple's modern networking API, sandbox-compatible, async-ready via continuations
- **Observation framework (macOS 14+) or ObservableObject (macOS 13)**: State management with fine-grained view updates
- **UserDefaults + @AppStorage**: Lightweight persistence for configuration (SwiftData/Core Data are overkill)

**Critical version constraint:** macOS 13.0 minimum enables MenuBarExtra, but macOS 14.0 unlocks @Observable which significantly simplifies state management. Consider bumping minimum target to 14.0 unless Ventura user base is substantial.

**ICMP limitation:** Network.framework does not expose ICMP (raw sockets). TCP connection timing to port 80/443 is the accepted alternative used by all App Store network monitoring apps. This is an architectural limitation, not a framework gap.

### Expected Features

Research shows clear separation between table stakes (expected in any ping monitor) and differentiators (competitive advantages). The existing app already exceeds most competitors with multi-host monitoring and visualization features.

**Must have (table stakes):**
- Real-time latency display in menu bar with color-coding (green/yellow/red minimum)
- Configurable ping target(s) with IPv4/IPv6 support
- Configurable interval (1s-60s range expected)
- Basic statistics (min/max/avg)
- Connection lost notifications via Notification Center
- Launch at login capability
- Light/dark mode support
- Privacy-focused (no external servers, direct ping only)

**Should have (competitive differentiators):**
- Multiple host monitoring with tabs/groups (your app has this)
- Latency history graph visualization (your app has this)
- Detailed ping history table (your app has this)
- Per-host notification customization (your app has 7 notification types)
- Data export (CSV/JSON) (your app has this)
- Compact/minimal display mode (your app has this)
- Stay-on-top floating window (your app has this)
- Jitter measurement (standard deviation of latency)
- Packet loss tracking (percentage over time window)
- Connection quality score (0-100 metric)

**Defer to v2+:**
- Webhook integration (power user feature, adds complexity)
- AppleScript/Shortcuts support (can add later without breaking changes)
- Bulk import of hosts (only needed at scale)
- Host grouping/organization (only valuable with many hosts)
- HTTP/HTTPS endpoint monitoring (different protocol, scope creep)

**Anti-features (explicitly avoid):**
- Cluttered menu bar display (offer compact mode instead)
- Aggressive default ping frequency (battery drain, default to 5-10s)
- External server dependencies (privacy concerns)
- Non-native UI (feels cheap on macOS)
- Subscription-only pricing (users expect one-time purchase for utilities)

### Architecture Approach

MVVM with Service Layer using SwiftUI for views and AppKit (NSStatusItem/NSPopover) for advanced menu bar integration. The critical architectural decision is actor isolation for services combined with @MainActor for ViewModels.

**Major components:**
1. **MenuBarController (@MainActor, AppKit bridge)** — NSStatusItem lifecycle, NSPopover management, click handling
2. **ViewModels (@MainActor, @Observable)** — Per-view state management (PingViewModel, SettingsViewModel), coordinates services with UI
3. **PingService (actor-isolated)** — Network.framework connections, latency measurement, concurrent ping handling
4. **NetworkMonitorService (actor)** — NWPathMonitor for connectivity changes, gateway detection
5. **NotificationService (@MainActor)** — Alert scheduling, condition evaluation
6. **AppState (@MainActor, shared)** — App-wide state (selected host, view mode, network status)
7. **Models (Sendable structs)** — Pure data structures that cross actor boundaries

**Key patterns:**
- **Structured concurrency for timers**: Replace Timer with Task + Task.sleep for automatic cancellation
- **withTimeout wrapper**: Race operation vs timeout using withTaskGroup, cancel loser to prevent races
- **Continuation-based NWConnection**: Convert callback-based API to async/await cleanly
- **Lazy popover creation**: Don't create NSPopover until first click (memory optimization)
- **Connection lifecycle tracking**: Actor-isolated dictionary with defer cleanup to prevent leaks

**Data flow:** User action → ViewModel (process) → Service (execute) → Model (result) → AppState (update) → View (re-render). Timer-driven ping cycle runs independently in ViewModel, updating AppState on each result.

### Critical Pitfalls

The previous implementation failed due to these specific issues. Prevention is the primary focus of phase planning.

1. **DispatchSemaphore with Swift Concurrency deadlock** — Using semaphore.wait() to block async operations causes cooperative thread pool deadlocks. The semaphore blocks the thread, but the work needed to signal it cannot run. **Prevention**: Never use DispatchSemaphore in any code path, use async/await throughout the stack.

2. **NWConnection state race (.ready → .failed)** — Connections can transition from .ready to .failed while code believes they're still ready. This caused the "stale connections" issue in the previous app. **Prevention**: Always maintain a pending receive() operation (NWConnection only notices dead connections if receive is pending), treat any send/receive error as connection death.

3. **Custom timeout race conditions** — Timeout fires after successful operation, or operation completes but timeout cleanup races with result handling. This caused false timeout reports. **Prevention**: Use withTaskGroup to race operation vs timeout, cancelling the loser. Check Task.isCancelled immediately after any await point.

4. **NWConnection memory leaks via retain cycles** — stateUpdateHandler captures self strongly, preventing deallocation. Connections accumulate over time. **Prevention**: Always use [weak self] in handlers, explicitly call connection.cancel() before releasing, set handlers to nil after cancellation.

5. **NSStatusItem disappearing (reference not retained)** — Menu bar icon vanishes because NSStatusItem stored in local variable instead of persistent property. **Prevention**: Store NSStatusItem as property on AppDelegate or long-lived object, initialize in applicationDidFinishLaunching.

**Secondary pitfalls:**
- Energy impact from aggressive polling (default to 30-60s intervals, not 1s)
- App Store sandbox ICMP restriction (use TCP/UDP from start, not raw sockets)
- Ignoring NWConnection .waiting state (third state beyond success/failure)
- Missing quit menu item (users can't quit after hiding from Dock)

## Implications for Roadmap

Based on research, the recommended phase structure prioritizes establishing correct async patterns and NWConnection lifecycle management before building features. The existing app has the right features but wrong foundation - the rewrite must fix the foundation first.

### Phase 1: Foundation & Core Networking
**Rationale:** The previous app's failures stemmed from incorrect async patterns and connection management. Establishing these patterns correctly is prerequisite to everything else. This phase delivers no user-visible features but prevents the critical pitfalls.

**Delivers:**
- Models (PingResult, HostConfig, ConnectionType, PingStatistics) as Sendable structs
- PingService actor with proper NWConnection lifecycle management
- Continuation-based async/await wrapper for NWConnection state transitions
- withTimeout pattern using withTaskGroup to prevent timeout races
- Connection tracking with defer cleanup to prevent memory leaks
- Unit tests for timeout behavior, connection lifecycle, concurrent pings

**Addresses features:**
- (Internal) TCP/UDP connection timing as ICMP alternative
- (Internal) Configurable timeout per host

**Avoids pitfalls:**
- Pitfall 1: No DispatchSemaphore, async/await only
- Pitfall 2: Pending receive() operations to detect stale connections
- Pitfall 3: withTaskGroup timeout pattern prevents races
- Pitfall 4: [weak self] in handlers, explicit cleanup
- Pitfall 10: TCP/UDP only, no ICMP attempts

**Research flag:** Standard patterns - Network.framework is well-documented, no phase research needed.

### Phase 2: State Management & Menu Bar Integration
**Rationale:** With correct networking foundation, build the UI layer using recommended state patterns. MenuBarExtra + NSStatusItem hybrid for menu bar, @Observable (or ObservableObject) for state, AppState for shared context.

**Delivers:**
- AppState (@MainActor, @Observable) shared state
- PingViewModel (@MainActor) managing timer-driven ping cycle
- MenuBarController with NSStatusItem retention pattern
- Basic MenuBarExtra with status display
- Launch at login via SMAppService or LaunchAgent
- Light/dark mode via system appearance

**Addresses features:**
- Real-time latency display in menu bar
- Color-coded status indicators (green/yellow/red)
- Launch at login
- Light/dark mode support

**Avoids pitfalls:**
- Pitfall 5: NSStatusItem stored as persistent property
- Pitfall 12: Quit menu item included from start

**Uses stack:**
- SwiftUI MenuBarExtra (macOS 13+)
- AppKit NSStatusItem for retention
- @Observable (macOS 14) or ObservableObject (macOS 13)

**Research flag:** Standard patterns - MenuBarExtra is documented, no phase research needed.

### Phase 3: Single Host Monitoring MVP
**Rationale:** Deliver minimal viable product with one host monitoring. Proves the core value proposition before adding multi-host complexity. This is the smallest releasable feature set.

**Delivers:**
- Settings view for host configuration (address, port, interval, timeout)
- Timer-driven ping cycle in PingViewModel using Task + Task.sleep
- Basic statistics calculation (min/max/avg from history)
- UserDefaults persistence for single host config
- Simple notification on connection lost

**Addresses features:**
- Configurable ping target (single host)
- Configurable ping interval
- Basic latency statistics
- Local macOS notifications
- Privacy-focused (no external servers)

**Uses stack:**
- UserDefaults + @AppStorage for preferences
- UNUserNotificationCenter for notifications

**Research flag:** Standard patterns - no phase research needed.

### Phase 4: Multi-Host Monitoring
**Rationale:** Add the primary differentiator over competitors. Requires concurrent ping handling (actors enable this safely) and host selection UI.

**Delivers:**
- AppState.hosts array with selected host tracking
- Concurrent ping handling using withTaskGroup in PingViewModel
- Host tabs/selection UI in menu bar popover
- Per-host configuration and statistics
- UserDefaults array persistence for multiple hosts

**Addresses features:**
- Multiple host monitoring (key differentiator)
- Per-host notification customization (foundation for this)

**Research flag:** Standard patterns - concurrent Task handling is documented, no phase research needed.

### Phase 5: History & Visualization
**Rationale:** Add debugging and analysis features that differentiate from basic ping tools. History table and graph both require the same underlying data structure.

**Delivers:**
- PingResult history storage (in-memory, configurable retention)
- History table view with timestamp, latency, status columns
- Latency graph visualization (SwiftUI Charts or custom view)
- Jitter calculation (standard deviation of latency)
- Packet loss tracking (failed pings / total pings percentage)
- Data export (CSV/JSON) from history

**Addresses features:**
- Latency history graph visualization (differentiator)
- Detailed ping history table (differentiator)
- Jitter measurement (differentiator)
- Packet loss tracking (differentiator)
- Data export (differentiator)

**Research flag:** Chart library choice may need research - SwiftUI Charts (macOS 13+) vs custom drawing. Medium complexity, but well-documented domain.

### Phase 6: Advanced Features & Polish
**Rationale:** Add remaining differentiators and polish for 1.0 release.

**Delivers:**
- Compact/minimal display mode toggle
- Stay-on-top floating window option
- Connection quality score (0-100 calculated from latency/jitter/packet loss)
- NetworkMonitorService with NWPathMonitor integration
- Gateway detection using SystemConfiguration (optional)
- Energy-aware polling (backoff on failures)
- Comprehensive notification types (7 types as in existing app)

**Addresses features:**
- Compact/minimal display mode (differentiator)
- Stay-on-top/floating window (differentiator)
- Connection quality score (differentiator)

**Avoids pitfalls:**
- Pitfall 9: Energy impact mitigation with backoff and reasonable defaults

**Research flag:** SystemConfiguration gateway detection may need API research if implemented. Otherwise standard patterns.

### Phase Ordering Rationale

- **Foundation first** prevents the critical pitfalls that caused the previous app to fail. No features until async patterns are correct.
- **State + menu bar second** establishes UI patterns before feature complexity.
- **Single host MVP third** delivers releasable product early, validates approach.
- **Multi-host fourth** adds primary differentiator on proven foundation.
- **History fifth** builds on stable multi-host monitoring, adds visualization value.
- **Polish last** completes 1.0 feature set after core is proven.

This ordering maps directly to the dependency graph in ARCHITECTURE.md: Models → Services → State → ViewModels → MenuBar → Views → App. Each phase builds on the previous, with no forward dependencies.

### Research Flags

**Phases with standard patterns (skip research-phase):**
- Phase 1 (Foundation): Network.framework is well-documented, Swift Concurrency patterns are established
- Phase 2 (State/MenuBar): MenuBarExtra and @Observable are documented by Apple
- Phase 3 (Single Host): UserDefaults and notifications are standard APIs
- Phase 4 (Multi-Host): Concurrent task patterns are well-established

**Phases that might benefit from research-phase:**
- Phase 5 (Visualization): Chart library selection (SwiftUI Charts vs custom) - MEDIUM priority research
- Phase 6 (Gateway detection): SystemConfiguration API if implemented - LOW priority research

**Overall recommendation:** Proceed directly to roadmap creation without additional research. All critical patterns are well-documented in research files.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Multiple authoritative sources agree on Swift Concurrency, Network.framework, @Observable recommendations. ICMP limitation verified in Apple Developer Forums. |
| Features | MEDIUM | Based on competitor analysis via App Store listings and product websites. Table stakes and differentiators align across multiple sources. Existing app already has key differentiators. |
| Architecture | HIGH | MVVM with service layer is standard macOS pattern. Actor isolation for services + @MainActor for ViewModels matches Swift 6 best practices. Patterns verified via Apple documentation and community consensus. |
| Pitfalls | HIGH | Critical pitfalls (DispatchSemaphore deadlock, NWConnection races, timeout races) verified via Apple Developer Forums and known issues from previous implementation. Prevention strategies tested in community projects. |

**Overall confidence:** HIGH

The technical recommendations are strongly supported by official documentation and community consensus. The previous app's failure modes are well-understood and preventable with proper async patterns. Feature expectations are based on competitor analysis which is inherently MEDIUM confidence, but the existing app already validates that these features are valued.

### Gaps to Address

**Gap 1: macOS 13 vs 14 minimum target decision**
- Trade-off between @Observable (macOS 14+) benefits and Ventura user reach
- **Handling**: Make explicit decision in Phase 1 planning based on analytics (if available) or default to macOS 14 for simplicity
- **Impact**: Determines whether to use @Observable or ObservableObject throughout

**Gap 2: TCP port selection for "ping"**
- Which port(s) to use for TCP connection timing (80, 443, 7, configurable?)
- **Handling**: Make configurable from start, default to 443 (HTTPS), document in settings
- **Impact**: Affects PingService design and HostConfig model

**Gap 3: Chart visualization library**
- SwiftUI Charts (macOS 13+) vs custom SwiftUI drawing vs third-party
- **Handling**: Prototype both in Phase 5, choose based on customization needs
- **Impact**: Affects visualization complexity and macOS version requirements

**Gap 4: Privacy manifest requirements**
- As of May 2024, apps using UserDefaults must declare in privacy manifest
- **Handling**: Create PrivacyInfo.xcprivacy in Phase 3 when adding UserDefaults
- **Impact**: App Store submission requirement, not optional

These gaps are tactical decisions that don't block roadmap creation. They can be resolved during phase implementation with the information available.

## Sources

### Primary (HIGH confidence)
- STACK.md (verified via Apple Developer Documentation, WWDC sessions, official tech notes)
- ARCHITECTURE.md (verified via Apple documentation, SwiftUI patterns, concurrency best practices)
- PITFALLS.md (verified via Apple Developer Forums, Swift Forums, known issues from previous implementation)
- FEATURES.md (competitor analysis via App Store listings, product websites)

### Key Official Documentation
- [TN3151: Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- [MenuBarExtra | Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [Network.framework | Apple Developer Documentation](https://developer.apple.com/documentation/network)
- [Observation framework | Apple Developer Documentation](https://developer.apple.com/documentation/Observation)
- [WWDC23: Beyond structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/)

### Key Community Sources
- [Apple Developer Forums: Network.framework ICMP discussion](https://developer.apple.com/forums/thread/709256)
- [Apple Developer Forums: DispatchSemaphore anti-pattern](https://developer.apple.com/forums/thread/124155)
- [Swift Forums: Cooperative pool deadlock](https://forums.swift.org/t/cooperative-pool-deadlock-when-calling-into-an-opaque-subsystem/70685)
- [SwiftLee: Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*

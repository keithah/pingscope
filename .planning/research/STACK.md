# Technology Stack

**Project:** PingMonitor - macOS Menu Bar Network Monitoring App
**Researched:** 2026-02-13
**Overall Confidence:** HIGH

## Executive Summary

This stack recommendation reflects 2025 best practices for building a native macOS menu bar application with real-time network monitoring. The architecture prioritizes Swift Concurrency over legacy GCD patterns, the modern Observation framework over ObservableObject, and Network.framework over BSD sockets for sandbox-compatible network operations.

---

## Recommended Stack

### Core Platform

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift | 6.x | Primary language | Modern concurrency, type safety, macros | HIGH |
| SwiftUI | macOS 13+ | UI framework | MenuBarExtra API, declarative UI, @Observable support | HIGH |
| AppKit | macOS 13+ | NSStatusItem integration | Required for advanced menu bar customization beyond MenuBarExtra limitations | HIGH |
| Xcode | 16+ | IDE and toolchain | Swift 6 support, modern previews, testing | HIGH |

### Concurrency Model

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift Concurrency | Swift 5.5+ | Async operations | Cleaner than GCD, structured concurrency, no thread explosion | HIGH |
| async/await | Swift 5.5+ | Async code flow | Sequential reads like sync code, better error handling | HIGH |
| Actors | Swift 5.5+ | Thread-safe state | Replace manual locks, compile-time data race prevention | HIGH |
| @MainActor | Swift 5.5+ | UI thread safety | Guaranteed main thread execution for UI updates | HIGH |

**Critical Recommendation:** Use Swift Concurrency exclusively for new code. GCD is deprecated in practice - all modern Swift patterns use async/await. Avoid DispatchQueue except for legacy API compatibility.

### Networking

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Network.framework | macOS 10.14+ | TCP/UDP connections | Apple's modern networking API, sandbox-compatible, async-ready | HIGH |
| NWConnection | Network.framework | Individual host probes | Direct TCP/UDP access without raw sockets | HIGH |
| NWPathMonitor | Network.framework | Network status changes | Real-time path monitoring, detects Wi-Fi/Ethernet changes | HIGH |
| SystemConfiguration | macOS SDK | Gateway detection | SCNetworkReachability for router/gateway identification | MEDIUM |

**ICMP Limitation:** Network.framework does not expose ICMP (raw socket) functionality due to its position in the network stack. For App Store sandbox compliance, use TCP connection timing or UDP probes as ping alternatives. This is verified by Apple Developer Forums discussion.

### State Management

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| @Observable macro | macOS 14+ | Reactive state | Modern replacement for ObservableObject, better performance | HIGH |
| Observation framework | macOS 14+ | Change tracking | Fine-grained updates, only redraws views reading changed properties | HIGH |

**Fallback for macOS 13:** If supporting macOS 13 (Ventura), use ObservableObject with @Published. The Observation framework requires macOS 14+.

**macOS 13 Compatibility Note:** Since the target is macOS 13.0+ (Ventura), use ObservableObject with @Published for state management. Consider minimum bump to macOS 14 to gain @Observable benefits - this is a tradeoff decision between user reach and developer ergonomics.

### Data Persistence

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| UserDefaults | Foundation | Simple preferences | Host list, intervals, thresholds - ideal for small key-value data | HIGH |
| @AppStorage | SwiftUI | SwiftUI preference binding | Auto-sync with UserDefaults, automatic view updates | HIGH |

**Why NOT SwiftData:** SwiftData is overkill for this app's needs. Ping history is transient (no need to persist hours of data), and configuration is simple key-value pairs. UserDefaults is sufficient and lighter weight.

**Privacy Manifest Required:** As of May 2024, apps using UserDefaults must declare this in their privacy manifest file. Include NSPrivacyAccessedAPIType: NSPrivacyAccessedAPICategoryUserDefaults.

### Menu Bar Integration

| Technology | Purpose | When to Use | Confidence |
|------------|---------|-------------|------------|
| MenuBarExtra | SwiftUI menu bar scene | Simple menus, macOS 13+ | HIGH |
| NSStatusItem | AppKit status item | Advanced customization, dynamic icons | HIGH |
| NSPopover | AppKit popover | Rich UI beyond menu constraints | MEDIUM |

**MenuBarExtra Limitations (verified):**
- Cannot programmatically show/hide menu
- No access to underlying NSStatusItem
- Limited styling options (button styles ignored)
- Blocks runloop when using `.menuBarExtraStyle(.menu)`
- SettingsLink unreliable in MenuBarExtra context
- No right-click menu support

**Recommendation:** Start with MenuBarExtra for simplicity. If hitting limitations (dynamic icon updates, right-click menus), drop to NSStatusItem + AppDelegate pattern. Many production apps use hybrid approach.

---

## Architecture Patterns

### Recommended: Actor-Based Network Manager

```swift
// Use actors for thread-safe network state
actor PingManager {
    private var connections: [String: NWConnection] = [:]

    func probe(host: String, port: UInt16) async throws -> TimeInterval {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        // Measure connection time as "ping"
        let start = ContinuousClock.now
        try await connect(connection)
        let elapsed = start.duration(to: .now)
        connection.cancel()
        return elapsed.components.seconds + Double(elapsed.components.attoseconds) / 1e18
    }
}
```

### Recommended: @MainActor for UI State

```swift
@MainActor
@Observable
class AppState {
    var hosts: [MonitoredHost] = []
    var isMonitoring: Bool = false
    var lastError: String?
}
```

### Recommended: Structured Concurrency for Parallel Probes

```swift
func probeAllHosts() async {
    await withTaskGroup(of: ProbeResult.self) { group in
        for host in hosts {
            group.addTask {
                await self.probe(host: host)
            }
        }
        for await result in group {
            updateUI(with: result)
        }
    }
}
```

---

## What NOT to Use

| Technology | Why Avoid | Use Instead |
|------------|-----------|-------------|
| Grand Central Dispatch (GCD) | Legacy pattern, thread explosion risk, no structured concurrency | Swift async/await |
| DispatchQueue | See above | Task, TaskGroup, actors |
| DispatchGroup | See above | withTaskGroup |
| Combine | More complex, higher learning curve, less readable | async/await for most cases |
| ObservableObject | Legacy, less efficient updates | @Observable (macOS 14+) |
| BSD Sockets | Not sandbox-compatible, low-level complexity | Network.framework |
| ICMP ping | Blocked by App Store sandbox | TCP/UDP connection timing |
| Core Data | Overkill for simple preferences | UserDefaults |
| SwiftData | Same as above for this app's needs | UserDefaults |
| URLSession | HTTP-focused, not for raw TCP probes | NWConnection |

---

## App Sandbox Entitlements

Required entitlements for App Store distribution:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

**Note:** `com.apple.security.network.client` allows outbound connections. No server entitlement needed for ping monitoring.

**ICMP Reality Check:** There is no entitlement that enables raw ICMP sockets in sandboxed apps. Apple deliberately restricts this. TCP connection timing is the accepted alternative used by App Store network utilities.

---

## Testing Strategy

| Layer | Tool | Approach | Confidence |
|-------|------|----------|------------|
| Unit tests | XCTest + Swift Testing | Protocol-based mocking, dependency injection | HIGH |
| Network mocking | OHHTTPStubs / custom protocols | Inject mock NWConnection wrappers | MEDIUM |
| UI tests | XCUITest | Menu bar interaction testing | MEDIUM |
| Async tests | XCTest async/await | Native async test methods | HIGH |

**Recommended Pattern:** Define protocols for network operations, inject mock implementations in tests.

```swift
protocol NetworkProbing {
    func probe(host: String, port: UInt16) async throws -> TimeInterval
}

// Production
struct LiveNetworkProber: NetworkProbing { ... }

// Test
struct MockNetworkProber: NetworkProbing {
    var stubbedLatency: TimeInterval = 0.05
    func probe(host: String, port: UInt16) async throws -> TimeInterval {
        return stubbedLatency
    }
}
```

---

## Version Constraints Summary

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| macOS Target | 13.0 (Ventura) | 14.0 (Sonoma) | macOS 14 enables @Observable |
| Swift | 5.9 | 6.0 | Swift 6 for full concurrency checking |
| Xcode | 15 | 16 | Swift 6 and latest SDKs |
| Network.framework | macOS 10.14 | Current | Stable, well-documented |
| MenuBarExtra | macOS 13 | macOS 13 | SwiftUI menu bar API |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not Alternative |
|----------|-------------|-------------|---------------------|
| Concurrency | async/await | GCD | GCD is legacy, prone to thread explosion, harder to reason about |
| Concurrency | async/await | Combine | Combine has steeper learning curve, async/await preferred for new code |
| State | @Observable | ObservableObject | ObservableObject causes unnecessary view updates |
| State | @Observable | Redux/TCA | Over-engineering for a menu bar app |
| Network | Network.framework | URLSession | URLSession is HTTP-focused, not for TCP probes |
| Network | Network.framework | BSD sockets | Not sandbox-compatible |
| Storage | UserDefaults | SwiftData | SwiftData is overkill for simple config |
| Storage | UserDefaults | SQLite | Same as above |
| Menu Bar | MenuBarExtra + NSStatusItem | Pure AppKit | SwiftUI is more maintainable, hybrid approach best |

---

## Quick Start Setup

### Project Configuration

1. **Create new macOS App** in Xcode (SwiftUI lifecycle)
2. **Set deployment target:** macOS 13.0
3. **Enable App Sandbox** in Signing & Capabilities
4. **Add Network entitlement:** `com.apple.security.network.client`
5. **Set activation policy:** `.accessory` (no Dock icon)

### Essential App Structure

```swift
@main
struct PingMonitorApp: App {
    var body: some Scene {
        MenuBarExtra("PingMonitor", systemImage: "network") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

### Info.plist Configuration

```xml
<key>LSUIElement</key>
<true/>  <!-- Hides from Dock -->
```

---

## Sources

### Official Documentation
- [TN3151: Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) - Apple's API selection guidance
- [MenuBarExtra | Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [NWPathMonitor | Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [SCNetworkReachability | Apple Developer Documentation](https://developer.apple.com/documentation/systemconfiguration/scnetworkreachability-g7d)
- [Observation | Apple Developer Documentation](https://developer.apple.com/documentation/Observation)
- [Security entitlements | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/security-entitlements)

### Verified Community Sources
- [Network.Framework ICMP/Ping | Apple Developer Forums](https://developer.apple.com/forums/thread/709256) - Confirms ICMP limitations
- [Swift Concurrency: From GCD to Async/Await](https://medium.com/@kamzksta/swift-concurrency-from-gcd-to-async-await-a-staff-engineers-guide-159d1d90c466)
- [Building a MacOS Menu Bar App with Swift](https://gaitatzis.medium.com/building-a-macos-menu-bar-app-with-swift-d6e293cd48eb)
- [FluidMenuBarExtra GitHub](https://github.com/wadetregaskis/FluidMenuBarExtra) - MenuBarExtra limitations workaround
- [Combine vs async/await in 2025](https://medium.com/@rajputpragat/combine-vs-async-await-in-2025-is-combine-still-relevant-134ef8449a22)
- [Network Reachability With Swift](https://www.marcosantadev.com/network-reachability-swift/)
- [NWPathMonitor usage](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor)

---

## Confidence Assessment

| Area | Level | Rationale |
|------|-------|-----------|
| Swift Concurrency recommendation | HIGH | Multiple authoritative sources agree, Apple's stated direction |
| Network.framework for TCP/UDP | HIGH | Official Apple tech note, verified in forums |
| ICMP not available in sandbox | HIGH | Confirmed in Apple Developer Forums, architectural limitation |
| MenuBarExtra limitations | HIGH | Multiple sources document same issues, verified in 2025 |
| @Observable for macOS 14+ | HIGH | Official Apple documentation, WWDC sessions |
| UserDefaults for persistence | HIGH | Standard pattern for menu bar app preferences |
| Testing approach | MEDIUM | Community patterns, no single authoritative source |
| SystemConfiguration for gateway | MEDIUM | API exists, but modern NWPathMonitor may suffice |

---

## Open Questions for Implementation

1. **macOS 13 vs 14 minimum:** Is the user base large enough on macOS 13 to justify the complexity of ObservableObject? Consider bumping to macOS 14.

2. **TCP port for probes:** What port to use for TCP "ping"? Port 80 (HTTP) or 443 (HTTPS) are commonly open. Consider making configurable.

3. **Hybrid MenuBarExtra approach:** At what point to drop to NSStatusItem? Dynamic icon color changes may require it.

4. **Privacy manifest:** Ensure UserDefaults usage is documented in PrivacyInfo.xcprivacy before App Store submission.

# Technology Stack

**Project:** PingScope - macOS Menu Bar Network Monitoring App
**Researched:** 2026-02-13
**Updated:** 2026-02-17 (WidgetKit and cross-platform architecture additions for v2.0)
**Overall Confidence:** HIGH

## Executive Summary

This stack recommendation reflects 2025-2026 best practices for building a native macOS menu bar application with real-time network monitoring. The architecture prioritizes Swift Concurrency over legacy GCD patterns, the modern Observation framework over ObservableObject, and Network.framework over BSD sockets for sandbox-compatible network operations.

**v2.0 Update:** This document now includes WidgetKit widget support and cross-platform architecture preparation. Key additions: App Groups for data sharing, TimelineProvider for widget updates, and compiler directives for platform-specific code isolation.

---

## Recommended Stack

### Core Platform

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift | 6.x | Primary language | Modern concurrency, type safety, macros | HIGH |
| SwiftUI | macOS 13+ | UI framework | MenuBarExtra API, declarative UI, @Observable support, **WidgetKit requirement** | HIGH |
| AppKit | macOS 13+ | NSStatusItem integration | Required for advanced menu bar customization beyond MenuBarExtra limitations | HIGH |
| Xcode | 26+ (mandatory April 28, 2026) | IDE and toolchain | Swift 6 support, modern previews, testing, Mac App Store submission, **Widget Extension targets** | HIGH |

**v2.0 Change:** WidgetKit requires SwiftUI for widget UI (no AppKit option). Widget Extension targets can only be created in Xcode, not Swift Package Manager.

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
| Network.framework | macOS 10.14+ | TCP/UDP connections | Apple's modern networking API, sandbox-compatible, async-ready, **cross-platform (iOS 12+)** | HIGH |
| NWConnection | Network.framework | Individual host probes | Direct TCP/UDP access without raw sockets | HIGH |
| NWPathMonitor | Network.framework | Network status changes | Real-time path monitoring, detects Wi-Fi/Ethernet changes | HIGH |
| SystemConfiguration | macOS SDK | Gateway detection | SCNetworkReachability for router/gateway identification (**macOS-only**, needs `#if os(macOS)`) | MEDIUM |

**ICMP Limitation:** Network.framework does not expose ICMP (raw socket) functionality due to its position in the network stack. For App Store sandbox compliance, use TCP connection timing or UDP probes as ping alternatives. This is verified by Apple Developer Forums discussion.

**Cross-Platform Note:** Network.framework works on both macOS and iOS. SystemConfiguration gateway detection is macOS-only; future iOS support will need NWPathMonitor API instead.

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
| UserDefaults | Foundation | Simple preferences | Host list, intervals, thresholds - ideal for small key-value data, **cross-platform** | HIGH |
| App Groups | macOS 10.8+ | Data sharing | **Share UserDefaults between app and widget extension** | HIGH |
| @AppStorage | SwiftUI | SwiftUI preference binding | Auto-sync with UserDefaults, automatic view updates | HIGH |
| Codable | Swift 4+ | Model serialization | JSON encoding for UserDefaults storage, **platform-independent** | HIGH |

**v2.0 Critical Addition:** App Groups enable UserDefaults sharing between main app and widget extension. Widgets run in separate process and cannot access standard UserDefaults container.

**App Groups Implementation:**
```swift
// Before (v1.0)
UserDefaults.standard

// After (v2.0)
UserDefaults(suiteName: "group.com.hadm.PingScope") ?? .standard
```

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

## v2.0 New Stack: WidgetKit

### Core WidgetKit Components

| Technology | Version | Purpose | Why Required | Confidence |
|------------|---------|---------|--------------|------------|
| WidgetKit | macOS 11.0+ | Widget framework | Apple's official widget API, required for desktop and Notification Center widgets | HIGH |
| TimelineProvider | WidgetKit | Widget updates | Defines when widget snapshots are generated (5-15 min intervals) | HIGH |
| TimelineEntry | WidgetKit | Widget state snapshots | Represents widget state at specific time | HIGH |
| StaticConfiguration | WidgetKit | Widget definition | Defines widget metadata (kind, provider, views) | HIGH |
| WidgetFamily | WidgetKit | Widget sizes | Small, Medium, Large sizing options | HIGH |

**macOS Widget Support:**
- **macOS 11+ (Big Sur):** Notification Center widgets
- **macOS 14+ (Sonoma):** Desktop widgets

**Widget Sizes Available:**
- **Small:** Square, minimal space (two can fit side-by-side)
- **Medium:** Twice the width of small
- **Large:** Four times the size of small (square)

**System Constraints:**
- **Refresh budget:** 40-70 updates/day (~15-60 minute intervals)
- **Minimum spacing:** 5 minutes between timeline entries
- **Runtime limit:** <1 second for snapshot generation
- **No background execution:** Widget only runs when generating snapshots
- **No direct ping operations:** Widget reads data from shared UserDefaults

### Widget Extension Target

**Critical SPM Limitation:** Swift Package Manager cannot create Widget Extension targets. Widget must be added as Xcode target.

**Solution:**
- Main app remains in Package.swift
- Widget Extension added via Xcode (File → New → Target → Widget Extension)
- Widget imports PingScope package to access shared models

**Why:** [SPM does not support app extension targets](https://forums.swift.org/t/is-there-a-way-to-add-swift-package-to-app-extensions/61379) as of Swift 6.0. This is an architectural platform limitation.

### Widget Timeline Patterns

| Pattern | Use Case | Refresh Policy | Confidence |
|---------|----------|----------------|------------|
| `.atEnd` | Automatic refresh when timeline expires | System reloads widget when last entry reached | HIGH |
| `.after(Date)` | Scheduled refresh at specific time | Widget updates after specified date | HIGH |
| `.never` | Manual refresh only | App calls `WidgetCenter.shared.reloadTimelines(ofKind:)` | MEDIUM |

**Recommended:** Use `.atEnd` policy for automatic updates. Widget generates 5-15 minute timeline entries, system automatically refreshes when timeline runs out.

### App Groups Configuration

| Component | Purpose | Configuration | Confidence |
|-----------|---------|---------------|------------|
| Entitlement key | Enable shared container | `com.apple.security.application-groups` | HIGH |
| Group identifier | Shared container name | `group.com.hadm.PingScope` | HIGH |
| Suite name | UserDefaults accessor | `UserDefaults(suiteName: "group.com.hadm.PingScope")` | HIGH |

**Both targets need entitlement:**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.hadm.PingScope</string>
</array>
```

**Pitfall:** Group identifier must start with `group.` prefix. Without this, data sharing fails silently.

---

## v2.0 New Stack: Cross-Platform Architecture

### Platform Abstraction Patterns

| Pattern | Use Case | Implementation | Confidence |
|---------|----------|----------------|------------|
| Compiler directives | Platform-specific code | `#if os(macOS)` / `#if os(iOS)` | HIGH |
| Type aliases | Unify similar APIs | `typealias PlatformView = NSView` / `UIView` | HIGH |
| Protocol abstraction | Abstract platform differences | Protocol + platform-specific implementations | MEDIUM |
| Shared ViewModels | Business logic | Platform-independent @MainActor classes | HIGH |
| Platform-specific Views | UI layer | Separate view files per platform | HIGH |

**Compiler Directive Example:**
```swift
#if os(macOS)
import AppKit
typealias PlatformView = NSView
#elseif os(iOS)
import UIKit
typealias PlatformView = UIView
#endif
```

**Recommended Approach:** Use compiler directives for isolation, not separate framework targets. This keeps codebase unified while enabling platform-specific code.

### Cross-Platform Code Organization

**What is already cross-platform (no changes needed):**
- All data models (Host, PingResult, GlobalDefaults) - Foundation-only types
- Network.framework ping operations (works macOS + iOS)
- ViewModels (MenuBarViewModel, DisplayViewModel, HostListViewModel) - platform-independent logic
- UserDefaults persistence (Foundation)
- Codable serialization (Swift standard library)

**What needs platform isolation:**
- SystemConfiguration gateway detection (macOS-only) - wrap in `#if os(macOS)`
- NSStatusBarButton / NSPopover (AppKit) - macOS-only UI
- Future iOS equivalents (UIKit navigation, iOS-specific UI patterns)

**File Organization Strategy:**

```
Sources/PingScope/
├── Models/                    # ✓ Already cross-platform
│   ├── Host.swift
│   ├── PingResult.swift
│   └── GlobalDefaults.swift
├── Services/                  # Mix of cross-platform and platform-specific
│   ├── PingService.swift             # ✓ Cross-platform
│   ├── HostStore.swift               # ✓ Cross-platform (update suite name)
│   ├── GatewayDetector.swift         # Needs #if os(macOS)
│   └── NotificationService.swift     # ✓ Cross-platform
├── ViewModels/                # ✓ Already cross-platform
│   ├── MenuBarViewModel.swift        # Logic cross-platform, UI binding macOS-only
│   ├── DisplayViewModel.swift
│   └── HostListViewModel.swift
├── Views/                     # Platform-specific UI
│   ├── HostRowView.swift             # Pure SwiftUI, cross-platform
│   ├── StatusPopoverView.swift       # Uses AppKit, needs platform check
│   └── DisplayGraphView.swift        # Pure SwiftUI, cross-platform
└── App/
    └── AppDelegate.swift             # macOS-only (NSApplicationDelegate)
```

### Platform-Specific Multiplatform Patterns

| Component | macOS Implementation | iOS Implementation (Future) | Shared |
|-----------|---------------------|----------------------------|--------|
| App Entry | NSApplicationDelegate + MenuBarExtra | UIApplicationDelegate | App struct |
| Main View | NSPopover / NSWindow | UINavigationController | ViewModel |
| Status Display | NSStatusBarButton | Widget / Notification | Data models |
| Gateway Detection | SystemConfiguration | NWPathMonitor | Network.framework |
| Persistence | UserDefaults (suite name) | UserDefaults (suite name) | Codable models |

---

## Mac App Store Distribution Stack (v2.0)

### Build Infrastructure

| Component | Version | Purpose | Why Required | Confidence |
|-----------|---------|---------|--------------|------------|
| Xcode Project (.xcodeproj) | N/A | Wrapper around SPM | Mac App Store requires Xcode-generated bundles; SPM alone cannot submit, **Widget Extension targets** | HIGH |
| macOS SDK | 15+ (Sequoia) | Platform SDK | April 2026 deadline requires latest SDK | HIGH |
| Swift Package Manager | 5.9+ | Dependency/target management | Remains source of truth, referenced by Xcode project | HIGH |

**Critical Finding:** Pure SPM cannot submit to Mac App Store. The final application package won't be a proper macOS bundle, lacks code signing infrastructure, and asset catalog support. An Xcode project wrapper is mandatory.

**v2.0 Widget Note:** Widget Extension targets can ONLY be created in Xcode. This reinforces the need for Xcode project infrastructure.

**Integration Approach:** Xcode project references Package.swift via "Add Local Package" rather than duplicating code. SPM remains canonical for source organization.

### Asset Management

| Component | Purpose | Why Required | Confidence |
|-----------|---------|--------------|------------|
| Asset Catalog (.xcassets) | App icon storage | Mac App Store requires asset catalogs for icons (not manual .icns) | HIGH |
| App Icon Set | Multi-resolution icons | 16×16, 32×32, 128×128, 256×256, 512×512 (@1x, @2x) + 1024×1024 for App Store | HIGH |

**Icon Requirements:** 1024×1024 master icon for App Store marketing. Asset catalog auto-generates runtime sizes. As of macOS 11+, asset catalogs are mandatory for App Store submissions.

### Code Signing (App Store-Specific)

| Certificate Type | Purpose | Different from Developer ID | Confidence |
|------------------|---------|------------------------------|------------|
| 3rd Party Mac Developer Application | Sign app bundle | Yes - different certificate chain | HIGH |
| 3rd Party Mac Developer Installer | Sign .pkg for upload | Yes - different from Developer ID Installer | HIGH |
| Mac App Store Provisioning Profile | Bundle authorization | Links bundle ID to App Store entitlements | HIGH |

**Certificate Lifecycle Difference:**
- **Developer ID:** Users download with your signature permanently
- **Mac App Store:** Apple re-signs with Apple's signature; your cert only validates upload

**Dual Distribution Note:** Keep existing Developer ID certificates for GitHub releases. App Store and Developer ID use separate certificate chains.

### Entitlements (App Store + Widget)

| Entitlement Key | Value | Purpose | Target | Confidence |
|-----------------|-------|---------|--------|------------|
| com.apple.security.app-sandbox | true | Enable App Sandbox | App + Widget | HIGH |
| com.apple.security.network.client | true | Outgoing network | App only | HIGH |
| com.apple.security.application-groups | array | Data sharing | App + Widget | HIGH |

**v2.0 Change:** App Groups entitlement now required for both main app and widget extension.

**Example App Groups Entitlement:**
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.hadm.PingScope</string>
</array>
```

**Widget Limitation:** Widget extension cannot perform network operations directly. Widget reads ping status from shared UserDefaults written by main app.

### Info.plist Keys (App Store-Required)

| Key | Value Example | Purpose | Confidence |
|-----|---------------|---------|------------|
| LSMinimumSystemVersion | "13.0.0" | Minimum macOS version (must match Package.swift) | HIGH |
| LSApplicationCategoryType | public.app-category.utilities | App Store category placement | HIGH |
| CFBundleShortVersionString | "2.0.0" | Marketing version (user-facing) | HIGH |
| CFBundleVersion | Build number | Internal build tracking (must increment per upload) | HIGH |

**Category Rationale:** Network monitoring apps use `public.app-category.utilities` for App Store categorization.

### Upload and Submission Tools

| Tool | Purpose | When to Use | Confidence |
|------|---------|-------------|------------|
| Transporter (GUI) | Upload .pkg to App Store Connect | Manual uploads | HIGH |
| xcrun altool --upload-package | Upload .pkg (CLI) | CI/CD automation | HIGH |
| App Store Connect API + Transporter CLI | Upload with JWT | Full automation | MEDIUM |
| productbuild | Create signed .pkg | Package .app for App Store Connect | HIGH |

**Upload Workflow:** Unlike Developer ID (DMG/PKG to users), App Store requires submitting .pkg to App Store Connect. Apple extracts, re-signs, and distributes via App Store.

**altool Status:** Notarization subcommands deprecated (use notarytool), but --upload-package still works for App Store submissions.

### CI/CD Additions (App Store)

**New GitHub Secrets Required:**

| Secret | Purpose | Separate from Developer ID | Confidence |
|--------|---------|----------------------------|------------|
| APPLE_MAS_CERTIFICATE_P12 | Mac App Store Application cert | Yes | HIGH |
| APPLE_MAS_INSTALLER_P12 | Mac App Store Installer cert | Yes | HIGH |
| MAS_PROVISIONING_PROFILE | Mac App Store provisioning profile | Yes | HIGH |
| APP_STORE_CONNECT_KEY_ID | API key for automated uploads | Yes | MEDIUM |
| APP_STORE_CONNECT_ISSUER_ID | API issuer ID | Yes | MEDIUM |
| APP_STORE_CONNECT_KEY | Private key (base64) | Yes | MEDIUM |

**Existing Developer ID secrets preserved for GitHub releases:**
- APPLE_CERTIFICATE_P12
- APPLE_INSTALLER_P12

**Dual Workflow Strategy:** Separate GitHub Actions workflows for Developer ID (GitHub releases) and App Store (App Store Connect uploads).

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

### v2.0 New Pattern: Widget Timeline Provider

```swift
struct PingTimelineProvider: TimelineProvider {
    typealias Entry = PingEntry

    func placeholder(in context: Context) -> PingEntry {
        PingEntry(date: Date(), status: .unknown, latency: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PingEntry) -> Void) {
        let entry = loadCurrentStatus()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PingEntry>) -> Void) {
        let currentDate = Date()
        let entries = (0..<12).map { offset in
            let entryDate = currentDate.addingTimeInterval(Double(offset) * 5 * 60) // 5-minute intervals
            return loadStatusForDate(entryDate)
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func loadCurrentStatus() -> PingEntry {
        // Read from shared UserDefaults
        let defaults = UserDefaults(suiteName: "group.com.hadm.PingScope")
        // Decode latest ping status
        // Return entry
    }
}
```

### v2.0 New Pattern: Shared UserDefaults Access

```swift
// Shared data access layer
class SharedDataStore {
    private let defaults: UserDefaults

    init() {
        // Use App Group suite name
        self.defaults = UserDefaults(suiteName: "group.com.hadm.PingScope") ?? .standard
    }

    func saveCurrentStatus(_ status: PingStatus) {
        if let encoded = try? JSONEncoder().encode(status) {
            defaults.set(encoded, forKey: "currentPingStatus")
        }
    }

    func loadCurrentStatus() -> PingStatus? {
        guard let data = defaults.data(forKey: "currentPingStatus") else { return nil }
        return try? JSONDecoder().decode(PingStatus.self, from: data)
    }
}
```

### v2.0 New Pattern: Platform-Specific Gateway Detection

```swift
// Services/GatewayDetector.swift
import Foundation
#if os(macOS)
import SystemConfiguration
#endif

actor GatewayDetector {
    #if os(macOS)
    func detectGateway() async -> GatewayInfo {
        // SystemConfiguration implementation
        // SCNetworkReachability code
    }
    #elseif os(iOS)
    func detectGateway() async -> GatewayInfo {
        // Future iOS implementation using NWPathMonitor
        // Return placeholder for now
    }
    #endif
}
```

---

## Xcode Project Structure (v2.0)

Recommended layout for SPM + Xcode + Widget Extension integration:

```
PingScope/
├── Package.swift                          # SPM package (source of truth)
├── Sources/PingScope/                     # App source code (SPM managed)
├── PingScope.xcodeproj/                   # Xcode wrapper
│   └── project.pbxproj                    # References Package.swift
├── PingScope/                             # Xcode app target folder
│   ├── Assets.xcassets/                   # Asset catalog (app icons)
│   │   └── AppIcon.appiconset/
│   ├── Info.plist                         # App Store required keys
│   ├── PingScope.entitlements             # App entitlements (sandbox + network + app groups)
│   └── PrivacyInfo.xcprivacy              # Privacy manifest
├── PingScopeWidget/                       # Widget Extension target (NEW v2.0)
│   ├── PingScopeWidget.swift              # Widget entry point
│   ├── PingTimelineProvider.swift         # Timeline provider
│   ├── WidgetViews/
│   │   ├── SmallWidgetView.swift
│   │   ├── MediumWidgetView.swift
│   │   └── LargeWidgetView.swift
│   ├── Assets.xcassets/                   # Widget assets
│   ├── Info.plist                         # Widget target info
│   └── PingScopeWidget.entitlements       # Widget entitlements (sandbox + app groups)
└── .github/workflows/
    ├── production-release.yml             # Developer ID (existing)
    └── appstore-release.yml               # Mac App Store
```

**Key Integration Points:**
1. Package.swift remains in project root
2. Xcode project adds Package.swift as local package
3. Widget Extension imports PingScope package for model access
4. Asset catalog and Info.plist live in Xcode target folders
5. Both app and widget have separate entitlements files (same app group)
6. Dual CI/CD workflows for dual distribution

**Widget Extension Setup:**
- File → New → Target → Widget Extension
- Widget Kind: PingScopeWidget
- Minimum Deployment: macOS 13.0
- Add PingScope package dependency to widget target
- Configure App Groups entitlement

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

### v2.0 Widget-Specific Anti-Patterns

| Avoid | Why | Use Instead | Confidence |
|-------|-----|-------------|------------|
| Real-time updates in widgets | System enforces 5+ min spacing, 40-70 updates/day budget | 5-15 minute timeline intervals | HIGH |
| Network operations in widget | Widgets have <1 sec runtime limit, no background execution | Read from shared UserDefaults | HIGH |
| Push notifications to widgets | API doesn't exist, widgets use pull model | TimelineProvider with `.atEnd` policy | HIGH |
| Standard UserDefaults in widget | Widget can't access app's sandboxed container | UserDefaults(suiteName: "group.X") | HIGH |
| Long-running tasks | Widget has strict runtime limits | Keep snapshot generation <1 second | HIGH |
| Frequent manual refreshes | Consumes daily refresh budget | Let system manage via timeline policy | MEDIUM |

### App Store-Specific Anti-Patterns

| Avoid | Why | Alternative | Confidence |
|-------|-----|-------------|------------|
| Duplicate SPM code in Xcode target | Two sources of truth, maintenance burden | Reference SPM package in Xcode | HIGH |
| Automatic code signing (App Store) | May select wrong profile with multiple certs | Manual signing with explicit profile | HIGH |
| Embedded updater (Sparkle, etc.) | Violates App Store guidelines | App Store update mechanism | HIGH |
| Third-party installers | App Store requires self-contained .app | Xcode export to .pkg | HIGH |
| Notarization in App Store workflow | Apple notarizes during processing | Only notarize Developer ID builds | HIGH |

### Cross-Platform Anti-Patterns

| Avoid | Why | Use Instead | Confidence |
|-------|-----|-------------|------------|
| AppKit/UIKit in models | Breaks cross-platform reuse | Foundation-only types | HIGH |
| Separate framework targets per platform | Premature separation, maintenance overhead | Compiler directives in shared files | HIGH |
| Platform checks at runtime | Compile-time is safer and more efficient | `#if os(macOS)` directives | HIGH |
| NSImage/UIImage in shared code | Platform-specific types | SF Symbols via system name strings | MEDIUM |

---

## App Sandbox Entitlements

Required entitlements for App Store distribution:

**Main App (PingScope.entitlements):**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.hadm.PingScope</string>
</array>
```

**Widget Extension (PingScopeWidget.entitlements):**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<!-- No network.client - widget doesn't perform network operations -->
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.hadm.PingScope</string>
</array>
```

**Note:** `com.apple.security.network.client` allows outbound connections. Widget extension doesn't need this since it only reads from shared UserDefaults.

**ICMP Reality Check:** There is no entitlement that enables raw ICMP sockets in sandboxed apps. Apple deliberately restricts this. TCP connection timing is the accepted alternative used by App Store network utilities.

---

## Testing Strategy

| Layer | Tool | Approach | Confidence |
|-------|------|----------|------------|
| Unit tests | XCTest + Swift Testing | Protocol-based mocking, dependency injection | HIGH |
| Network mocking | OHHTTPStubs / custom protocols | Inject mock NWConnection wrappers | MEDIUM |
| UI tests | XCUITest | Menu bar interaction testing | MEDIUM |
| Async tests | XCTest async/await | Native async test methods | HIGH |
| **Widget snapshot tests** | **XCTest + WidgetKit** | **Generate timeline entries, verify views** | **MEDIUM** |

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

**v2.0 Widget Testing:**
```swift
func testWidgetTimeline() async {
    let provider = PingTimelineProvider()
    let context = TimelineProviderContext()

    provider.getTimeline(in: context) { timeline in
        XCTAssertEqual(timeline.entries.count, 12) // 1 hour of 5-min intervals
        XCTAssertEqual(timeline.policy, .atEnd)
    }
}
```

---

## Version Constraints Summary

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| macOS Target | 13.0 (Ventura) | 14.0 (Sonoma) | macOS 14 enables @Observable, desktop widgets |
| Swift | 5.9 | 6.0 | Swift 6 for full concurrency checking |
| Xcode | 26+ | 26.1+ | **Mandatory April 28, 2026 for App Store** |
| macOS SDK | 15+ (Sequoia) | Current | Required by Xcode 26 mandate |
| Network.framework | macOS 10.14 | Current | Stable, well-documented, cross-platform |
| MenuBarExtra | macOS 13 | macOS 13 | SwiftUI menu bar API |
| **WidgetKit** | **macOS 11** | **macOS 13** | **Notification Center widgets (11+), desktop widgets (14+)** |
| **App Groups** | **macOS 10.8** | **Current** | **Long-established API, no compatibility concerns** |

**v2.0 Critical Date:** April 28, 2026 - Xcode 26+ becomes mandatory for all App Store submissions.

**v2.0 Widget Recommendation:** Target macOS 13.0 for broad compatibility. Desktop widgets (macOS 14+) are nice-to-have; Notification Center widgets work on 13+.

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

### v2.0 Widget-Specific Alternatives

| Decision | Alternative | When to Use Alternative | Confidence |
|----------|-------------|-------------------------|------------|
| App Groups + UserDefaults | Core Data with shared container | If needing relational queries or large datasets (not needed here) | HIGH |
| TimelineProvider | Manual refresh via WidgetCenter | If updates driven by unpredictable events (not applicable to ping monitoring) | MEDIUM |
| WidgetKit | Live Activities | If needing real-time updates (iOS only, not available on macOS) | HIGH |
| Widget Extension in Xcode | SPM-only approach | Never (SPM doesn't support extension targets) | HIGH |

### App Store-Specific Alternatives

| Decision | Alternative | When to Use Alternative | Confidence |
|----------|-------------|-------------------------|------------|
| Xcode project wrapper | Pure SPM with manual bundle | Never for App Store (bundles don't meet requirements) | HIGH |
| Manual signing | Automatic signing | Never for dual-distribution (can't handle both cert types) | HIGH |
| Transporter | xcrun altool | Use altool for CI/CD; Transporter for manual uploads | HIGH |
| Mac App Store | Developer ID only | If app requires privileged features incompatible with sandbox | HIGH |

### Cross-Platform Alternatives

| Decision | Alternative | When to Use Alternative | Confidence |
|----------|-------------|-------------------------|------------|
| Compiler directives | Separate platform frameworks | If codebase grows to warrant full separation (not yet) | MEDIUM |
| Type aliases | Abstraction protocols | If platform APIs diverge significantly (unlikely for our models) | MEDIUM |
| Shared Package.swift | Platform-specific packages | If targeting non-Apple platforms (Linux, Windows) | LOW |

---

## Quick Start Setup

### Project Configuration

1. **Create new macOS App** in Xcode (SwiftUI lifecycle)
2. **Set deployment target:** macOS 13.0
3. **Enable App Sandbox** in Signing & Capabilities
4. **Add Network entitlement:** `com.apple.security.network.client`
5. **Add App Groups entitlement:** `group.com.hadm.PingScope`
6. **Set activation policy:** `.accessory` (no Dock icon)
7. **Add Widget Extension target** (File → New → Target → Widget Extension)
8. **Configure widget entitlements:** App Sandbox + App Groups (no network client)

### Essential App Structure

```swift
@main
struct PingScopeApp: App {
    var body: some Scene {
        MenuBarExtra("PingScope", systemImage: "network") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

### Essential Widget Structure

```swift
@main
struct PingScopeWidget: Widget {
    let kind: String = "PingScopeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PingTimelineProvider()) { entry in
            PingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ping Monitor")
        .description("Monitor network connectivity.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

### Info.plist Configuration

```xml
<key>LSUIElement</key>
<true/>  <!-- Hides from Dock -->
<key>LSMinimumSystemVersion</key>
<string>13.0.0</string>  <!-- App Store requirement -->
<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>  <!-- App Store category -->
```

---

## Installation (Developers)

### One-Time Setup (v2.0 additions)

```bash
# 1. Download Xcode 26+ from Mac App Store
# (Mandatory starting April 28, 2026 for App Store submissions)

# 2. Install Xcode Command Line Tools
xcode-select --install

# 3. Download Mac App Store certificates from Apple Developer portal
# - 3rd Party Mac Developer Application
# - 3rd Party Mac Developer Installer

# 4. Create Mac App Store provisioning profile
# - App ID: com.hadm.PingScope
# - Type: Mac App Store
# - Entitlements: App Sandbox, Network Client, App Groups

# 5. Create App Group in Apple Developer portal
# - Name: PingScope Shared Data
# - Identifier: group.com.hadm.PingScope

# 6. Install Transporter from Mac App Store (for uploads)
```

### Xcode Project Creation (v2.0 First Time)

```bash
# 1. Create Xcode project in repository root
# File → New → Project → macOS → App
# Save as: PingScope.xcodeproj

# 2. Add local SPM package to project
# File → Add Packages → Add Local
# Select: Package.swift

# 3. Configure main app target
# - Link PingScope executable from SPM
# - Add Assets.xcassets
# - Add Info.plist
# - Add PingScope.entitlements
# - Enable App Groups capability

# 4. Add Widget Extension target
# File → New → Target → Widget Extension
# Target Name: PingScopeWidget
# - Add PingScopeWidget.entitlements
# - Enable App Groups capability (same group as app)
# - Add PingScope package dependency

# 5. Configure signing
# Signing & Capabilities → Manual Signing
# Provisioning Profile: [Select Mac App Store profile]
```

---

## Sources

### Official Apple Documentation
- [TN3151: Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api) - Apple's API selection guidance
- [MenuBarExtra | Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [NWPathMonitor | Apple Developer Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
- [SCNetworkReachability | Apple Developer Documentation](https://developer.apple.com/documentation/systemconfiguration/scnetworkreachability-g7d)
- [Observation | Apple Developer Documentation](https://developer.apple.com/documentation/Observation)
- [Security entitlements | Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/security-entitlements)

### v2.0 WidgetKit Sources
- [WidgetKit - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit) — Framework overview (MEDIUM confidence: WebFetch failed, verified via WebSearch)
- [TimelineProvider - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/timelineprovider) — Update mechanism (MEDIUM confidence)
- [Keeping a widget up to date - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) — Best practices (MEDIUM confidence)
- [Developing a WidgetKit strategy - Apple Developer Documentation](https://developer.apple.com/documentation/WidgetKit/Developing-a-WidgetKit-strategy) — Architecture guidance (MEDIUM confidence)
- [Add and customize widgets on Mac - Apple Support](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac) — Widget sizes (HIGH confidence)
- [WidgetKit Architecture Overview - StudyRaid](https://app.studyraid.com/en/read/6182/136362/widgetkit-architecture-overview) — Architecture patterns (MEDIUM confidence)

### v2.0 App Groups and Data Sharing
- [Sharing UserDefaults with widgets - Apple Developer Forums](https://developer.apple.com/forums/thread/651799) — HIGH confidence
- [Accessing your App's User Defaults from Widgets Extension - Osas Blogs](https://swiftlogic.io/posts/accessing-userdefaults-in-widgets/) — HIGH confidence
- [Sharing Object Data Between an iOS App and Its Widget - Medium](https://michael-kiley.medium.com/sharing-object-data-between-an-ios-app-and-its-widget-a0a1af499c31) — MEDIUM confidence
- [How to load and save a struct in UserDefaults using Codable - Hacking with Swift](https://www.hackingwithswift.com/example-code/system/how-to-load-and-save-a-struct-in-userdefaults-using-codable) — HIGH confidence
- [User Defaults reading and writing in Swift - SwiftLee](https://www.avanderlee.com/swift/user-defaults-preferences/) — HIGH confidence

### v2.0 Cross-Platform Architecture
- [Building a Unified Multiplatform Architecture with SwiftUI - Medium](https://medium.com/@mrhotfix/building-a-unified-multiplatform-architecture-with-swiftui-ios-macos-and-visionos-6214b307466a) — MEDIUM confidence
- [Sharing cross-platform code in SwiftUI apps - Jesse Squires](https://www.jessesquires.com/blog/2022/08/19/sharing-code-in-swiftui-apps/) — MEDIUM confidence
- [Tips and tricks for iOS & macOS cross platform development - Yenovi](https://yenovi.com/blog/ios-macos-crossplatform-development) — MEDIUM confidence
- [Running code on a specific platform or OS version - Apple Developer](https://developer.apple.com/documentation/xcode/running-code-on-a-specific-version) — MEDIUM confidence
- [Setting up a multi-platform SwiftUI project - Scott Logic](https://blog.scottlogic.com/2021/03/04/Multiplatform-SwiftUI.html) — MEDIUM confidence
- [MVVM in SwiftUI for a Better Architecture - Matteo Manferdini](https://matteomanferdini.com/mvvm-pattern-ios-swift/) — MEDIUM confidence

### v2.0 Swift Package Manager + Widget Extensions
- [Is there a way to add Swift Package to app extensions? - Swift Forums](https://forums.swift.org/t/is-there-a-way-to-add-swift-package-to-app-extensions/61379) — HIGH confidence (confirms SPM limitation)
- [How to Use Swift Package Manager - OneUpTime](https://oneuptime.com/blog/post/2026-02-02-swift-package-manager/view) — MEDIUM confidence
- [Package - Swift Package Manager](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) — HIGH confidence
- [Platform specific code in Swift Packages - Pol Piella](https://www.polpiella.dev/platform-specific-code-in-swift-packages/) — MEDIUM confidence

### Mac App Store Distribution
- [Apple Developer - Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) - Xcode 26 mandate for April 2026
- [Apple Developer - Certificates](https://developer.apple.com/support/certificates/) - Certificate types
- [Apple Developer - Submitting to Mac App Store](https://developer.apple.com/library/archive/releasenotes/General/SubmittingToMacAppStore/index.html) - Official requirements
- [Apple Developer - LSMinimumSystemVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/lsminimumsystemversion) - Info.plist
- [9to5Mac - Apple updates minimum SDK requirements](https://9to5mac.com/2026/02/03/apple-to-update-minimum-sdk-requirements-for-all-app-store-submissions/) - April 2026 deadline

### Verified Community Sources
- [Network.Framework ICMP/Ping | Apple Developer Forums](https://developer.apple.com/forums/thread/709256) - Confirms ICMP limitations
- [Swift Concurrency: From GCD to Async/Await](https://medium.com/@kamzksta/swift-concurrency-from-gcd-to-async-await-a-staff-engineers-guide-159d1d90c466)
- [Building a MacOS Menu Bar App with Swift](https://gaitatzis.medium.com/building-a-macos-menu-bar-app-with-swift-d6e293cd48eb)
- [FluidMenuBarExtra GitHub](https://github.com/wadetregaskis/FluidMenuBarExtra) - MenuBarExtra limitations workaround
- [Combine vs async/await in 2025](https://medium.com/@rajputpragat/combine-vs-async-await-in-2025-is-combine-still-relevant-134ef8449a22)
- [Network Reachability With Swift](https://www.marcosantadev.com/network-reachability-swift/)
- [NWPathMonitor usage](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor)
- [The Swift Dev - How to build macOS apps using only SPM](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/) - SPM limitations

### Widget Update and Refresh
- [How to Update or Refresh a Widget? - Swift Senpai](https://swiftsenpai.com/development/refreshing-widget/) — MEDIUM confidence
- [Understanding the Limitations of Widgets Runtime - Medium](https://medium.com/@telawittig/understanding-the-limitations-of-widgets-runtime-in-ios-app-development-and-strategies-for-managing-a3bb018b9f5a) — MEDIUM confidence
- [Building Widgets - Cornell App Dev](https://ios-course.cornellappdev.com/resources/archived-past-semesters/fa23/lectures/widgets/building-widgets) — MEDIUM confidence

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
| **WidgetKit framework usage** | **HIGH** | **Official Apple framework, widely documented** |
| **App Groups for data sharing** | **HIGH** | **Official entitlement, verified in forums and docs** |
| **Widget refresh constraints** | **HIGH** | **System-enforced limits, documented by Apple** |
| **SPM cannot create widget targets** | **HIGH** | **Confirmed in Swift Forums, platform limitation** |
| **Cross-platform compiler directives** | **HIGH** | **Official Apple documentation, standard pattern** |
| **Xcode 26 requirement** | **HIGH** | **Official Apple announcement, April 28, 2026 deadline** |
| **SPM cannot submit to App Store** | **HIGH** | **Community consensus, Apple's bundle requirements** |
| **Mac App Store certificates** | **HIGH** | **Official Apple documentation** |
| Testing approach | MEDIUM | Community patterns, no single authoritative source |
| SystemConfiguration for gateway | MEDIUM | API exists, but modern NWPathMonitor may suffice |
| **Widget snapshot testing** | **MEDIUM** | **XCTest supports it, less documentation** |
| **App Store Connect API** | **MEDIUM** | **Official API exists, less documentation for macOS** |

---

## Open Questions for Implementation

1. **macOS 13 vs 14 minimum:** Is the user base large enough on macOS 13 to justify the complexity of ObservableObject? Consider bumping to macOS 14.

2. **TCP port for probes:** What port to use for TCP "ping"? Port 80 (HTTP) or 443 (HTTPS) are commonly open. Consider making configurable.

3. **Hybrid MenuBarExtra approach:** At what point to drop to NSStatusItem? Dynamic icon color changes may require it.

4. **Privacy manifest:** Ensure UserDefaults usage is documented in PrivacyInfo.xcprivacy before App Store submission.

5. **Widget update frequency:** Should widgets update every 5 minutes (maximum freshness) or 15 minutes (conserve battery)? Consider user preference.

6. **Widget size priority:** Which widget sizes to prioritize? Small (always visible) vs Medium (more info) vs Large (full detail)?

7. **Desktop vs Notification Center:** Should widget design prioritize desktop (macOS 14+) or Notification Center (macOS 13+) use case?

8. **Cross-platform timeline:** When to add iOS support? Should architecture decisions prioritize macOS-first or true multiplatform from day one?

9. **Shared data granularity:** What data should widgets access? Just current status, or historical trends too?

10. **CI/CD workflow split:** Should App Store uploads happen automatically on tagged releases, or require manual approval step in App Store Connect?

11. **Asset catalog migration:** Should existing icon files be migrated to asset catalog for Developer ID builds too, or keep separate for consistency?

# Technology Stack

**Project:** PingMonitor - macOS Menu Bar Network Monitoring App
**Researched:** 2026-02-13
**Updated:** 2026-02-16 (Mac App Store distribution additions)
**Overall Confidence:** HIGH

## Executive Summary

This stack recommendation reflects 2025 best practices for building a native macOS menu bar application with real-time network monitoring. The architecture prioritizes Swift Concurrency over legacy GCD patterns, the modern Observation framework over ObservableObject, and Network.framework over BSD sockets for sandbox-compatible network operations.

**v2.0 Update:** This document now includes Mac App Store distribution requirements, which add Xcode project infrastructure around the existing SPM codebase while preserving all v1.0 technologies.

---

## Recommended Stack

### Core Platform

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift | 6.x | Primary language | Modern concurrency, type safety, macros | HIGH |
| SwiftUI | macOS 13+ | UI framework | MenuBarExtra API, declarative UI, @Observable support | HIGH |
| AppKit | macOS 13+ | NSStatusItem integration | Required for advanced menu bar customization beyond MenuBarExtra limitations | HIGH |
| Xcode | 26+ (mandatory April 28, 2026) | IDE and toolchain | Swift 6 support, modern previews, testing, **Mac App Store submission** | HIGH |

**v2.0 Change:** Xcode 26+ is now mandatory for App Store submissions starting April 28, 2026 (verified official Apple requirement).

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

## Mac App Store Distribution Stack (v2.0)

### Build Infrastructure

| Component | Version | Purpose | Why Required | Confidence |
|-----------|---------|---------|--------------|------------|
| Xcode Project (.xcodeproj) | N/A | Wrapper around SPM | Mac App Store requires Xcode-generated bundles; SPM alone cannot submit | HIGH |
| macOS SDK | 15+ (Sequoia) | Platform SDK | April 2026 deadline requires latest SDK | HIGH |
| Swift Package Manager | 5.9+ | Dependency/target management | Remains source of truth, referenced by Xcode project | HIGH |

**Critical Finding:** Pure SPM cannot submit to Mac App Store. The final application package won't be a proper macOS bundle, lacks code signing infrastructure, and asset catalog support. An Xcode project wrapper is mandatory.

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

### Entitlements (App Store)

| Entitlement Key | Value | Purpose | v1.0 Status | Confidence |
|-----------------|-------|---------|-------------|------------|
| com.apple.security.app-sandbox | true | Enable App Sandbox | Already implemented | HIGH |
| com.apple.security.network.client | true | Outgoing network | Already implemented | HIGH |

**No New Entitlements Required:** PingScope v1.0 already supports sandboxed operation. App Store build uses identical entitlements.

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

---

## Xcode Project Structure (v2.0)

Recommended layout for SPM + Xcode integration:

```
PingScope/
├── Package.swift                          # SPM package (source of truth)
├── Sources/PingScope/                     # App source code (SPM managed)
├── PingScope.xcodeproj/                   # Xcode wrapper (v2.0 addition)
│   └── project.pbxproj                    # References Package.swift
├── PingScope/                             # Xcode target folder (v2.0)
│   ├── Assets.xcassets/                   # Asset catalog (app icons)
│   │   └── AppIcon.appiconset/
│   ├── Info.plist                         # App Store required keys
│   └── PingScope.entitlements             # Sandbox + network entitlements
└── .github/workflows/
    ├── production-release.yml             # Developer ID (existing)
    └── appstore-release.yml               # Mac App Store (v2.0)
```

**Key Integration Points:**
1. Package.swift remains in project root
2. Xcode project adds Package.swift as local package
3. Asset catalog and Info.plist live in Xcode target folder
4. Entitlements file shared between builds (same sandboxing)
5. Dual CI/CD workflows for dual distribution

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

### App Store-Specific Anti-Patterns

| Avoid | Why | Alternative | Confidence |
|-------|-----|-------------|------------|
| Duplicate SPM code in Xcode target | Two sources of truth, maintenance burden | Reference SPM package in Xcode | HIGH |
| Automatic code signing (App Store) | May select wrong profile with multiple certs | Manual signing with explicit profile | HIGH |
| Embedded updater (Sparkle, etc.) | Violates App Store guidelines | App Store update mechanism | HIGH |
| Third-party installers | App Store requires self-contained .app | Xcode export to .pkg | HIGH |
| Notarization in App Store workflow | Apple notarizes during processing | Only notarize Developer ID builds | HIGH |

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
| Xcode | 26+ | 26.1+ | **Mandatory April 28, 2026 for App Store** |
| macOS SDK | 15+ (Sequoia) | Current | Required by Xcode 26 mandate |
| Network.framework | macOS 10.14 | Current | Stable, well-documented |
| MenuBarExtra | macOS 13 | macOS 13 | SwiftUI menu bar API |

**v2.0 Critical Date:** April 28, 2026 - Xcode 26+ becomes mandatory for all App Store submissions.

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

### App Store-Specific Alternatives

| Decision | Alternative | When to Use Alternative | Confidence |
|----------|-------------|-------------------------|------------|
| Xcode project wrapper | Pure SPM with manual bundle | Never for App Store (bundles don't meet requirements) | HIGH |
| Manual signing | Automatic signing | Never for dual-distribution (can't handle both cert types) | HIGH |
| Transporter | xcrun altool | Use altool for CI/CD; Transporter for manual uploads | HIGH |
| Mac App Store | Developer ID only | If app requires privileged features incompatible with sandbox | HIGH |

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
# - App ID: com.hadm.pingscope
# - Type: Mac App Store
# - Entitlements: App Sandbox, Network Client

# 5. Install Transporter from Mac App Store (for uploads)
```

### Xcode Project Creation (v2.0 First Time)

```bash
# 1. Create Xcode project in repository root
# File → New → Project → macOS → App
# Save as: PingScope.xcodeproj

# 2. Add local SPM package to project
# File → Add Packages → Add Local
# Select: Package.swift

# 3. Configure target
# - Link PingScope executable from SPM
# - Add Assets.xcassets
# - Add Info.plist
# - Add PingScope.entitlements

# 4. Configure signing
# Signing & Capabilities → Manual Signing
# Provisioning Profile: [Select Mac App Store profile]
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

### v2.0 Mac App Store Sources
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
| **Xcode 26 requirement** | **HIGH** | **Official Apple announcement, April 28, 2026 deadline** |
| **SPM cannot submit to App Store** | **HIGH** | **Community consensus, Apple's bundle requirements** |
| **Mac App Store certificates** | **HIGH** | **Official Apple documentation** |
| Testing approach | MEDIUM | Community patterns, no single authoritative source |
| SystemConfiguration for gateway | MEDIUM | API exists, but modern NWPathMonitor may suffice |
| **App Store Connect API** | **MEDIUM** | **Official API exists, less documentation for macOS** |

---

## Open Questions for Implementation

1. **macOS 13 vs 14 minimum:** Is the user base large enough on macOS 13 to justify the complexity of ObservableObject? Consider bumping to macOS 14.

2. **TCP port for probes:** What port to use for TCP "ping"? Port 80 (HTTP) or 443 (HTTPS) are commonly open. Consider making configurable.

3. **Hybrid MenuBarExtra approach:** At what point to drop to NSStatusItem? Dynamic icon color changes may require it.

4. **Privacy manifest:** Ensure UserDefaults usage is documented in PrivacyInfo.xcprivacy before App Store submission.

5. **v2.0 - Xcode project integration:** How to structure Xcode project to reference SPM package without duplicating source code? Use "Add Local Package" feature.

6. **v2.0 - CI/CD workflow split:** Should App Store uploads happen automatically on tagged releases, or require manual approval step in App Store Connect?

7. **v2.0 - Asset catalog migration:** Should existing icon files be migrated to asset catalog for Developer ID builds too, or keep separate for consistency?

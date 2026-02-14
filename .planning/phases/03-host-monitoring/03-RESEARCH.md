# Phase 3: Host Monitoring - Research

**Researched:** 2026-02-14
**Domain:** Multi-host monitoring, network gateway detection, per-host configuration, SwiftUI host management
**Confidence:** HIGH

## Summary

Phase 3 extends the existing ping infrastructure to support multiple hosts with per-host configuration. The current codebase already has solid foundations: `Host` model with protocol types, `PingService` with `pingAll`, and `PingScheduler` with staggered execution. This phase adds:

1. **Default gateway detection** using macOS routing table via `sysctl` (not NWPath.gateways which has known issues)
2. **Network change monitoring** using `NWPathMonitor` to detect connectivity changes
3. **WiFi SSID retrieval** using CoreWLAN's `CWWiFiClient` for network-aware gateway naming
4. **Host persistence** using UserDefaults with Codable encoding for custom hosts
5. **Host management UI** with SwiftUI List, sheets for add/edit, and confirmation dialogs for delete

**Primary recommendation:** Extend the existing `Host` model to include per-host overrides (optional interval, timeout, thresholds), add a `GatewayDetector` service that monitors network changes and resolves gateway IP, and create a `HostStore` actor for persistence and CRUD operations.

## Standard Stack

The established libraries/tools for this domain:

### Core (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Network.framework | macOS 10.14+ | NWConnection, NWPathMonitor | Apple's modern networking |
| Foundation | - | UserDefaults, Codable | Built-in persistence |

### New Required
| Library | Purpose | When to Use |
|---------|---------|-------------|
| CoreWLAN | WiFi SSID retrieval | Gateway network naming |
| Darwin (sysctl) | Routing table access | Default gateway IP detection |

### Why Not External Libraries
| Problem | Don't Use | Why |
|---------|-----------|-----|
| Gateway detection | FGRoute, swift-netutils | Adds Objective-C bridging complexity; sysctl is straightforward |
| Network monitoring | Reachability wrappers | NWPathMonitor is modern and sufficient |
| Persistence | Core Data, SwiftData | Overkill for ~10 hosts; Codable+UserDefaults is sufficient |

**Installation:** No new dependencies needed. Import CoreWLAN and Darwin headers.

## Architecture Patterns

### Recommended Project Structure
```
Sources/PingMonitor/
├── Models/
│   ├── Host.swift              # Extend with per-host overrides
│   ├── HostConfiguration.swift # Per-host settings (optional overrides)
│   └── GlobalDefaults.swift    # Global ping settings
├── Services/
│   ├── GatewayDetector.swift   # NEW: Network + gateway monitoring
│   ├── HostStore.swift         # NEW: CRUD + persistence
│   └── ... (existing services)
├── Views/
│   ├── HostListView.swift      # NEW: Main host list
│   ├── AddHostSheet.swift      # NEW: Add/edit form
│   └── HostRowView.swift       # NEW: Single host row
└── ViewModels/
    └── HostListViewModel.swift # NEW: Binds store to UI
```

### Pattern 1: Per-Host Override with Global Fallback
**What:** Each host can override global defaults; nil means use global
**When to use:** Any per-host configurable setting (interval, timeout, thresholds)
**Example:**
```swift
struct HostConfiguration: Codable, Sendable, Equatable {
    var intervalOverride: Duration?
    var timeoutOverride: Duration?
    var greenThresholdMSOverride: Double?
    var yellowThresholdMSOverride: Double?
    var pingMethodOverride: PingMethod?

    func effectiveInterval(global: Duration) -> Duration {
        intervalOverride ?? global
    }

    func effectiveTimeout(global: Duration) -> Duration {
        timeoutOverride ?? global
    }
}
```

### Pattern 2: Gateway Detection with Network Monitoring
**What:** Combine NWPathMonitor (connectivity changes) with sysctl (gateway IP lookup)
**When to use:** Continuous gateway monitoring with network-aware naming
**Example:**
```swift
actor GatewayDetector {
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "GatewayDetector")

    func startMonitoring() -> AsyncStream<GatewayInfo> {
        AsyncStream { continuation in
            pathMonitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else {
                    continuation.yield(.unavailable)
                    return
                }
                Task {
                    if let info = await self?.detectGateway() {
                        continuation.yield(info)
                    }
                }
            }
            pathMonitor.start(queue: monitorQueue)
        }
    }

    private func detectGateway() -> GatewayInfo? {
        // Use sysctl with CTL_NET, PF_ROUTE, NET_RT_FLAGS, RTF_GATEWAY
        // Parse rt_msghdr structures to find default gateway
    }
}
```

### Pattern 3: Codable Persistence with @AppStorage Bridge
**What:** Store Codable array in UserDefaults, optionally expose via typealias for @AppStorage
**When to use:** Persisting custom hosts array
**Example:**
```swift
// Source: https://nilcoalescing.com/blog/SaveCustomCodableTypesInAppStorageOrSceneStorage/
typealias HostList = [Host]

extension HostList: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(HostList.self, from: data)
        else { return nil }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else { return "[]" }
        return result
    }
}
```

### Pattern 4: Sheet-Based Add/Edit Flow
**What:** Single sheet view that handles both add and edit modes
**When to use:** Host creation and modification
**Example:**
```swift
// Source: https://www.avanderlee.com/swiftui/presenting-sheets/
struct AddHostSheet: View {
    enum Mode { case add, edit(Host) }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onSave: (Host) -> Void

    @State private var hostname = ""
    @State private var displayName = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    var body: some View {
        Form {
            Section("Host Details") {
                TextField("Hostname or IP", text: $hostname)
                TextField("Display Name", text: $displayName)
            }
            Section("Test Connection") {
                Button("Test Ping") { testPing() }
                    .disabled(hostname.isEmpty || isTesting)
                if let result = testResult {
                    TestResultRow(result: result)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }
}
```

### Anti-Patterns to Avoid
- **Polling for gateway:** Don't poll routing table on timer; use NWPathMonitor callbacks
- **Storing all hosts in one JSON blob:** While we use JSON encoding, the HostStore should provide clean CRUD API
- **Mixing global/per-host logic in views:** Keep effective value calculation in model layer
- **Blocking main thread for gateway lookup:** sysctl can block; run on background queue

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Network connectivity monitoring | Custom reachability | NWPathMonitor | Apple's modern API, handles all edge cases |
| Gateway IP parsing | String parsing of route output | sysctl + rt_msghdr | Direct kernel access, no shell subprocess |
| WiFi SSID | system_profiler parsing | CWWiFiClient.shared().interface()?.ssid() | Direct API, no subprocess |
| Confirmation dialogs | Custom alert views | .confirmationDialog modifier | Native look, automatic Cancel handling |
| Form validation | Manual if/else chains | Computed property for isValid | Cleaner, reactive |
| JSON persistence | Manual file I/O | UserDefaults + JSONEncoder | Built-in, atomic writes |

**Key insight:** macOS provides native APIs for all networking queries. Avoid shelling out to `route`, `netstat`, or `system_profiler` when direct APIs exist.

## Common Pitfalls

### Pitfall 1: NWPath.gateways Returns Empty After Ready State
**What goes wrong:** The `gateways` property is populated during `.preparing` state but depopulates when path transitions to `.ready`
**Why it happens:** Known Apple bug/design decision
**How to avoid:** Don't use NWPath.gateways for gateway detection; use sysctl routing table query instead
**Warning signs:** Gateway shows as available then immediately disappears

### Pitfall 2: CWWiFiClient SSID Requires Permissions on macOS 15+
**What goes wrong:** SSID returns nil on macOS 15.3+
**Why it happens:** Apple added privacy restrictions requiring location permissions
**How to avoid:** Gracefully degrade to IP-only naming when SSID unavailable; document permission requirements
**Warning signs:** Works in development, fails in production/TestFlight

### Pitfall 3: Per-Host Overrides Create Config Explosion
**What goes wrong:** UI becomes cluttered, users confused about which setting applies
**Why it happens:** Too many optional overrides exposed at once
**How to avoid:** Default to global settings; show per-host overrides only when user explicitly expands "Advanced" section
**Warning signs:** Add host form has 10+ fields

### Pitfall 4: Gateway Updates Thrash During Network Transitions
**What goes wrong:** Multiple rapid gateway changes displayed during network switch
**Why it happens:** NWPathMonitor fires multiple updates during transition
**How to avoid:** Debounce gateway updates (200-300ms); show transitional "Network changing..." state
**Warning signs:** Gateway flickers between IPs rapidly

### Pitfall 5: Default Host Protection Relies on Index Position
**What goes wrong:** Defaults become deletable after reordering
**Why it happens:** Using array index to identify defaults
**How to avoid:** Mark defaults with `isDefault: true` flag on Host model (already exists); filter by flag not position
**Warning signs:** Google DNS suddenly deletable

### Pitfall 6: Test Ping Blocks Save Flow
**What goes wrong:** User can't save host for future use if test fails
**Why it happens:** Making test success a save requirement
**How to avoid:** Warn on failure but allow save anyway (user might be adding host they'll connect to later)
**Warning signs:** "Save" button disabled when ping fails

## Code Examples

Verified patterns from official sources and existing codebase:

### Gateway Detection via sysctl
```swift
// Source: https://gist.github.com/etodd/d8184b91c02306b889c13eb03f81fb6d
// Adapted for Swift from C implementation

import Darwin

struct GatewayInfo: Sendable, Equatable {
    let ipAddress: String
    let interfaceName: String?
    let networkName: String? // WiFi SSID if available

    static let unavailable = GatewayInfo(ipAddress: "", interfaceName: nil, networkName: nil)

    var isAvailable: Bool { !ipAddress.isEmpty }

    var displayName: String {
        if let networkName, !networkName.isEmpty {
            return "\(networkName) Gateway"
        }
        return ipAddress.isEmpty ? "No Network" : ipAddress
    }
}

func getDefaultGateway() -> String? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
    var bufferSize: Int = 0

    // First call to get buffer size
    guard sysctl(&mib, UInt32(mib.count), nil, &bufferSize, nil, 0) == 0 else {
        return nil
    }

    var buffer = [UInt8](repeating: 0, count: bufferSize)

    // Second call to get data
    guard sysctl(&mib, UInt32(mib.count), &buffer, &bufferSize, nil, 0) == 0 else {
        return nil
    }

    // Parse rt_msghdr structures to find default route (destination 0.0.0.0)
    // Return gateway IP as string
    // ... (implementation details involve pointer arithmetic through buffer)
}
```

### WiFi SSID Retrieval
```swift
// Source: https://github.com/chbrown/macos-wifi/blob/master/corewlanlib.swift
import CoreWLAN

func getCurrentSSID() -> String? {
    guard let interface = CWWiFiClient.shared().interface() else {
        return nil
    }
    return interface.ssid()
}
```

### NWPathMonitor Setup
```swift
// Source: https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor
import Network

class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var onPathUpdate: ((NWPath) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onPathUpdate?(path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
```

### Confirmation Dialog for Delete
```swift
// Source: https://swiftwithmajid.com/2021/07/28/confirmation-dialogs-in-swiftui/
struct HostRowView: View {
    let host: Host
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack {
            Text(host.name)
            Spacer()
            Text(host.isDefault ? "" : "")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !host.isDefault {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete \(host.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}
```

### Host Persistence with Codable
```swift
// Source: https://www.hackingwithswift.com/example-code/system/how-to-load-and-save-a-struct-in-userdefaults-using-codable
actor HostStore {
    private let defaults = UserDefaults.standard
    private let key = "savedHosts"

    private(set) var hosts: [Host] = []

    init() {
        hosts = loadHosts()
    }

    private func loadHosts() -> [Host] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Host].self, from: data)
        else {
            return Host.defaults // Google DNS, Cloudflare
        }
        return decoded
    }

    func save(_ hosts: [Host]) {
        self.hosts = hosts
        if let encoded = try? JSONEncoder().encode(hosts) {
            defaults.set(encoded, forKey: key)
        }
    }

    func add(_ host: Host) {
        var current = hosts
        current.append(host)
        save(current)
    }

    func remove(_ host: Host) {
        guard !host.isDefault else { return }
        var current = hosts
        current.removeAll { $0.id == host.id }
        save(current)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SCNetworkReachability | NWPathMonitor | macOS 10.14 | Simpler API, async-friendly |
| Parsing `route -n get default` | sysctl routing table | Always available | No subprocess, faster |
| Manual ICMP sockets | TCP/UDP connection probes | N/A | No root required, firewall-friendly |
| @State arrays for persistence | UserDefaults + Codable | Swift 4 | Built-in, type-safe |

**Deprecated/outdated:**
- `SCNetworkReachability`: Still works but NWPathMonitor is preferred
- `SystemConfiguration.CaptiveNetwork`: Deprecated for SSID; use CoreWLAN on macOS

## Open Questions

Things that couldn't be fully resolved:

1. **SSID Permissions on macOS 15.3+**
   - What we know: Apple restricted SSID access, may require location permissions
   - What's unclear: Exact entitlement requirements for menu bar apps
   - Recommendation: Implement graceful degradation (IP-only naming), test on macOS 15.3+

2. **Optimal Gateway Detection Debounce**
   - What we know: NWPathMonitor fires multiple times during transitions
   - What's unclear: Ideal debounce interval for responsive yet stable UX
   - Recommendation: Start with 200ms, tune based on testing

3. **All Hosts vs Active Host Only Pinging (Claude's Discretion)**
   - What we know: Both are viable; parallel pinging gives richer data
   - What's unclear: Battery/network impact of continuous multi-host pinging
   - Recommendation: Ping all hosts in parallel (user expects multi-host monitoring), but allow per-host disable

## Sources

### Primary (HIGH confidence)
- Existing codebase: `Host.swift`, `PingService.swift`, `PingScheduler.swift`, `ConnectionWrapper.swift`
- Apple Developer Documentation: NWPathMonitor, CWWiFiClient (structure known from training)
- [Hacking with Swift - NWPathMonitor](https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor)
- [GitHub gist - macOS routing table dump](https://gist.github.com/etodd/d8184b91c02306b889c13eb03f81fb6d)
- [Nil Coalescing - Codable with AppStorage](https://nilcoalescing.com/blog/SaveCustomCodableTypesInAppStorageOrSceneStorage/)

### Secondary (MEDIUM confidence)
- [SwiftLee - SwiftUI Sheets](https://www.avanderlee.com/swiftui/presenting-sheets/)
- [Swift with Majid - Confirmation Dialogs](https://swiftwithmajid.com/2021/07/28/confirmation-dialogs-in-swiftui/)
- [GitHub - macos-wifi CoreWLAN](https://github.com/chbrown/macos-wifi/blob/master/corewlanlib.swift)
- [Patrick Ekman - ICMP Sockets](https://ekman.cx/articles/icmp_sockets/)

### Tertiary (LOW confidence)
- WebSearch results for SSID permissions on macOS 15.3+ (conflicting reports, needs testing)
- WebSearch results for NWPath.gateways bug (anecdotal, not officially documented)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Uses only built-in frameworks already in project or standard macOS APIs
- Architecture: HIGH - Patterns derived from existing codebase and established SwiftUI practices
- Gateway detection: MEDIUM - sysctl approach verified, but NWPath.gateways issue is anecdotal
- SSID retrieval: MEDIUM - CoreWLAN API stable but permission requirements changing on latest macOS
- Per-host config: HIGH - Simple model extension pattern
- Pitfalls: MEDIUM - Mix of codebase knowledge and community reports

**Research date:** 2026-02-14
**Valid until:** 2026-03-14 (30 days - stable domain, but monitor macOS 15.x SSID changes)

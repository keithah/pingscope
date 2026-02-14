# Architecture Patterns

**Domain:** macOS Menu Bar Network Monitoring App
**Researched:** 2026-02-13
**Confidence:** HIGH (verified with Apple documentation patterns and community best practices)

## Recommended Architecture

MVVM with Service Layer, using SwiftUI for views and AppKit (NSStatusItem/NSPopover) for menu bar integration.

```
+------------------+     +------------------+     +------------------+
|                  |     |                  |     |                  |
|   Menu Bar       |---->|   ViewModels     |---->|   Services       |
|   Controller     |     |   (per View)     |     |   (Business)     |
|                  |     |                  |     |                  |
+------------------+     +------------------+     +------------------+
        |                        |                        |
        v                        v                        v
+------------------+     +------------------+     +------------------+
|                  |     |                  |     |                  |
|   SwiftUI Views  |     |   AppState       |     |   Models         |
|                  |     |   (Shared)       |     |   (Data)         |
|                  |     |                  |     |                  |
+------------------+     +------------------+     +------------------+
```

### Component Boundaries

| Component | Responsibility | Communicates With | Isolation |
|-----------|---------------|-------------------|-----------|
| **MenuBarController** | NSStatusItem lifecycle, NSPopover management, click handling | ViewModels (reads state), AppDelegate | @MainActor |
| **PingViewModel** | Per-host ping state, latency history, statistics | PingService, Models | @MainActor |
| **SettingsViewModel** | Host configuration, preferences state | PersistenceService, Models | @MainActor |
| **AppState** | Shared app-wide state (selected host, view mode, alerts) | ViewModels (publish), Views (subscribe) | @MainActor |
| **PingService** | Network.framework connections, latency measurement | Models (produces), Network APIs | Actor-isolated |
| **NetworkMonitorService** | NWPathMonitor, connectivity state | AppState (publishes changes) | Actor-isolated |
| **NotificationService** | Alert scheduling, condition evaluation | AppState (reads), UNUserNotificationCenter | @MainActor |
| **PersistenceService** | UserDefaults read/write, data export | Models (serializes) | @MainActor |
| **GatewayService** | SCDynamicStore, default gateway detection | NetworkMonitorService | Actor-isolated |
| **Views (SwiftUI)** | UI rendering, user interaction | ViewModels (via @StateObject/@ObservedObject) | @MainActor |
| **Models** | Data structures (PingResult, HostConfig, etc.) | All layers (passive data) | Sendable |

### Data Flow

```
User Action Flow:
┌──────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────┐
│ View     │───>│ ViewModel    │───>│ Service     │───>│ External │
│ (tap)    │    │ (process)    │    │ (execute)   │    │ (network)│
└──────────┘    └──────────────┘    └─────────────┘    └──────────┘
                       │                    │
                       v                    v
                ┌──────────────┐    ┌─────────────┐
                │ AppState     │<───│ Model       │
                │ (update)     │    │ (result)    │
                └──────────────┘    └─────────────┘
                       │
                       v
                ┌──────────────┐
                │ View         │
                │ (re-render)  │
                └──────────────┘

Timer-Driven Flow (Ping Cycle):
┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│ ViewModel    │───>│ PingService │───>│ NWConnection │
│ (timer fire) │    │ (ping host) │    │ (connect)    │
└──────────────┘    └─────────────┘    └──────────────┘
                           │                  │
                           │<─────────────────┘
                           │    (latency result)
                           v
                    ┌─────────────┐    ┌──────────────┐
                    │ ViewModel   │───>│ View         │
                    │ (update)    │    │ (re-render)  │
                    └─────────────┘    └──────────────┘
```

## Core Components Detail

### 1. MenuBarController (AppKit Bridge)

Manages the NSStatusItem and NSPopover lifecycle. This is the bridge between AppKit's menu bar system and SwiftUI views.

```swift
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let viewModel: PingViewModel

    // Initialize lazily to avoid assertion errors
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Configure button, click handlers
    }

    // Toggle popover on click
    func togglePopover(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    // Lazy popover creation (memory optimization)
    private func showPopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            popover = NSPopover()
            popover?.contentViewController = NSHostingController(rootView: MainView())
            popover?.behavior = .transient
        }
        popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}
```

**Why this pattern:**
- Lazy popover creation saves memory when popover never opened
- @MainActor ensures all UI work happens on main thread
- NSObject inheritance required for menu bar delegate protocols

### 2. ViewModels (@MainActor + @Observable)

Each ViewModel manages state for its domain and coordinates with services.

```swift
@MainActor
@Observable
final class PingViewModel {
    // Published state
    var currentLatency: Double?
    var status: ConnectionStatus = .unknown
    var history: [PingResult] = []
    var statistics: PingStatistics?

    // Dependencies
    private let pingService: PingService
    private var pingTask: Task<Void, Never>?

    // Timer-driven ping cycle
    func startMonitoring() {
        pingTask = Task {
            while !Task.isCancelled {
                await performPing()
                try? await Task.sleep(for: .seconds(pingInterval))
            }
        }
    }

    private func performPing() async {
        do {
            let result = await pingService.ping(host: currentHost)
            // Already on @MainActor, safe to update
            self.currentLatency = result.latency
            self.history.append(result)
            self.updateStatistics()
        } catch {
            self.status = .error(error)
        }
    }

    func stopMonitoring() {
        pingTask?.cancel()
        pingTask = nil
    }
}
```

**Why @MainActor on ViewModels:**
- All @Published/@Observable properties must update on main thread
- SwiftUI observes these properties and requires main thread updates
- Eliminates "Publishing changes from background threads" warnings
- With Swift 6.2's Approachable Concurrency, this is the recommended default

### 3. Services (Actor-Isolated)

Services handle async operations with proper isolation. The PingService is the most critical.

```swift
actor PingService {
    private var activeConnections: [String: NWConnection] = [:]

    func ping(host: HostConfig) async -> PingResult {
        let startTime = ContinuousClock.now

        // Create connection with timeout
        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: host.port),
            using: host.connectionType.parameters
        )

        // Track for cleanup
        activeConnections[host.id] = connection
        defer {
            connection.cancel()
            activeConnections.removeValue(forKey: host.id)
        }

        do {
            try await withTimeout(seconds: host.timeout) {
                try await self.awaitConnection(connection)
            }
            let elapsed = startTime.duration(to: .now)
            return PingResult(
                host: host,
                latency: elapsed.milliseconds,
                timestamp: Date(),
                status: .success
            )
        } catch is TimeoutError {
            return PingResult(
                host: host,
                latency: nil,
                timestamp: Date(),
                status: .timeout
            )
        } catch {
            return PingResult(
                host: host,
                latency: nil,
                timestamp: Date(),
                status: .error(error)
            )
        }
    }

    private func awaitConnection(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    // Cancel all active connections (for cleanup)
    func cancelAll() {
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
    }
}
```

**Why Actor isolation for PingService:**
- Multiple concurrent pings possible (multi-host monitoring)
- Connection dictionary access must be synchronized
- Actor prevents data races without manual locking
- Clean cancellation semantics with Task cancellation

### 4. AppState (Shared Observable)

Single source of truth for app-wide state that multiple views need.

```swift
@MainActor
@Observable
final class AppState {
    // View mode
    var viewMode: ViewMode = .full
    var isFloatingWindow: Bool = false

    // Host selection
    var selectedHostId: String?
    var hosts: [HostConfig] = []

    // Network status
    var networkStatus: NWPath.Status = .satisfied
    var hasInternetAccess: Bool = true

    // Alerts
    var pendingAlerts: [PingAlert] = []
}
```

**Distribution via Environment:**
```swift
@main
struct PingMonitorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MainView()
                .environment(appState)
        } label: {
            StatusItemView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### 5. Models (Sendable Data)

Pure data structures that can safely cross actor boundaries.

```swift
struct PingResult: Sendable, Codable, Identifiable {
    let id: UUID
    let host: HostConfig
    let latency: Double?  // milliseconds, nil if timeout
    let timestamp: Date
    let status: PingStatus
}

struct HostConfig: Sendable, Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var address: String
    var port: UInt16
    var connectionType: ConnectionType
    var timeout: TimeInterval
    var isEnabled: Bool
}

enum ConnectionType: String, Sendable, Codable {
    case tcp
    case udp
    case icmpSimulated  // TCP to port 7 or 80 as ICMP proxy

    var parameters: NWParameters {
        switch self {
        case .tcp, .icmpSimulated: return .tcp
        case .udp: return .udp
        }
    }
}

struct PingStatistics: Sendable {
    let transmitted: Int
    let received: Int
    let packetLoss: Double
    let minLatency: Double
    let avgLatency: Double
    let maxLatency: Double
    let stdDev: Double
}
```

## Patterns to Follow

### Pattern 1: Structured Concurrency for Timers

Use Swift Concurrency instead of Timer or DispatchSourceTimer for cleaner cancellation.

**What:** Replace Timer.scheduledTimer with Task + Task.sleep
**When:** Any repeating background work
**Why:** Automatic cancellation with Task.cancel(), no retain cycles

```swift
@MainActor
final class PingViewModel {
    private var monitoringTask: Task<Void, Never>?

    func startMonitoring() {
        monitoringTask = Task {
            while !Task.isCancelled {
                await performPing()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
    }

    deinit {
        monitoringTask?.cancel()
    }
}
```

### Pattern 2: withTimeout for Network Operations

Wrap async network calls with explicit timeout to prevent hanging.

**What:** Timeout wrapper using Task.sleep race
**When:** Any NWConnection operation
**Why:** NWConnection doesn't have built-in timeout for ready state

```swift
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### Pattern 3: Connection Lifecycle Management

Always track and clean up NWConnections to prevent stale connections.

**What:** Explicit connection tracking with defer cleanup
**When:** Every NWConnection creation
**Why:** Uncancelled connections cause resource leaks and stale state

```swift
actor PingService {
    private var activeConnections: [String: NWConnection] = [:]

    func ping(host: HostConfig) async -> PingResult {
        let connection = createConnection(for: host)
        activeConnections[host.id] = connection

        defer {
            connection.cancel()
            activeConnections.removeValue(forKey: host.id)
        }

        // ... perform ping ...
    }

    func cancelAll() {
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
    }
}
```

### Pattern 4: Lazy Popover Creation

Don't create NSPopover and hosting controller until first use.

**What:** Create popover on first click, not at app launch
**When:** Menu bar apps with potentially unused popovers
**Why:** Memory savings, especially important for background apps

```swift
@MainActor
final class MenuBarController {
    private var popover: NSPopover?

    func showPopover(from button: NSStatusBarButton) {
        let popover = self.popover ?? createPopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func createPopover() -> NSPopover {
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: MainView()
                .environment(appState)
        )
        popover.behavior = .transient
        return popover
    }
}
```

### Pattern 5: Continuation-Based NWConnection

Convert callback-based NWConnection to async/await cleanly.

**What:** Use withCheckedThrowingContinuation for state transitions
**When:** Waiting for NWConnection.ready state
**Why:** Cleaner than DispatchSemaphore, no deadlock risk

```swift
private func awaitReady(_ connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        var resumed = false

        connection.stateUpdateHandler = { state in
            guard !resumed else { return }

            switch state {
            case .ready:
                resumed = true
                continuation.resume()
            case .failed(let error):
                resumed = true
                continuation.resume(throwing: error)
            case .cancelled:
                resumed = true
                continuation.resume(throwing: CancellationError())
            default:
                break
            }
        }

        connection.start(queue: .global())
    }
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: DispatchSemaphore for Async Waiting

**What:** Using semaphore.wait() to block until async operation completes
**Why bad:** Blocks thread, can deadlock, races with timeout handlers
**Consequence:** False timeouts when timeout fires before state handler
**Instead:** Use async/await with continuation

```swift
// BAD - causes race conditions
func pingSync(host: String) -> Double? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Double?

    connection.stateUpdateHandler = { state in
        if state == .ready {
            result = latency
            semaphore.signal()  // May race with timeout
        }
    }

    // Timeout handler
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        semaphore.signal()  // RACE: may fire before ready
    }

    semaphore.wait()
    return result
}

// GOOD - no races
func ping(host: String) async throws -> Double {
    try await withTimeout(seconds: 5) {
        try await awaitReady(connection)
        return latency
    }
}
```

### Anti-Pattern 2: Updating @Published from Background Thread

**What:** Modifying @Published or @Observable properties from non-main thread
**Why bad:** SwiftUI crashes or shows stale UI
**Consequence:** "Publishing changes from background threads" warning, undefined behavior
**Instead:** Mark ViewModel as @MainActor, or use MainActor.run

```swift
// BAD
class PingViewModel: ObservableObject {
    @Published var latency: Double?

    func ping() async {
        let result = await service.ping()
        latency = result  // WARNING: background thread!
    }
}

// GOOD
@MainActor
@Observable
final class PingViewModel {
    var latency: Double?

    func ping() async {
        let result = await service.ping()
        latency = result  // Safe: @MainActor ensures main thread
    }
}
```

### Anti-Pattern 3: Not Cancelling NWConnections

**What:** Creating connections without ensuring cleanup
**Why bad:** Connections stay in .ready state, accumulate over time
**Consequence:** Resource exhaustion, stale connection handlers firing
**Instead:** Track connections, use defer for cleanup, cancel on deinit

### Anti-Pattern 4: Shared Mutable State Without Isolation

**What:** Multiple tasks accessing same dictionary/array
**Why bad:** Data races, undefined behavior
**Consequence:** Crashes, corrupted state
**Instead:** Use actor isolation or @MainActor

### Anti-Pattern 5: Timer in MenuBarExtra View

**What:** Creating Timer directly in SwiftUI view within MenuBarExtra
**Why bad:** Timer may not fire when popover closed (run loop blocked)
**Consequence:** Monitoring stops when popover closes
**Instead:** Timer/Task in ViewModel or Service that persists independently

## Build Order (Dependency Graph)

Components should be built in this order based on dependencies:

```
Phase 1: Foundation
├── Models (no dependencies)
├── Constants/Configuration (no dependencies)
└── Error types (no dependencies)

Phase 2: Services
├── PersistenceService (depends on: Models)
├── GatewayService (depends on: Models)
├── PingService (depends on: Models)
└── NetworkMonitorService (depends on: Models, GatewayService)

Phase 3: State Management
├── AppState (depends on: Models)
└── NotificationService (depends on: Models, AppState)

Phase 4: ViewModels
├── PingViewModel (depends on: PingService, AppState, Models)
├── SettingsViewModel (depends on: PersistenceService, AppState, Models)
└── HistoryViewModel (depends on: AppState, Models)

Phase 5: AppKit Integration
└── MenuBarController (depends on: ViewModels, AppState)

Phase 6: Views
├── MainView (depends on: ViewModels, AppState)
├── GraphView (depends on: Models)
├── HistoryView (depends on: ViewModels)
├── SettingsView (depends on: ViewModels)
├── StatusItemView (depends on: ViewModels)
└── ExportView (depends on: ViewModels)

Phase 7: App Entry
└── PingMonitorApp (depends on: All)
```

**Why this order:**
1. Models first: Everything depends on data structures
2. Services second: Business logic independent of UI
3. State third: Shared state that ViewModels observe
4. ViewModels fourth: Coordinate services with state
5. MenuBar fifth: Needs ViewModels to read state
6. Views sixth: Need ViewModels and AppState
7. App last: Wires everything together

## Concurrency Model Summary

| Component Type | Isolation | Rationale |
|---------------|-----------|-----------|
| ViewModels | @MainActor | UI state must update on main thread |
| AppState | @MainActor | Shared UI state, observed by views |
| Views | @MainActor | SwiftUI requirement |
| MenuBarController | @MainActor | AppKit APIs require main thread |
| PingService | actor | Concurrent pings, connection tracking |
| NetworkMonitorService | actor | NWPathMonitor callback handling |
| GatewayService | actor | SystemConfiguration API isolation |
| PersistenceService | @MainActor | UserDefaults fine on main, simpler API |
| NotificationService | @MainActor | UNUserNotificationCenter requires main |
| Models | Sendable | Cross-boundary data transfer |

## Sources

- [Apple Developer: Building and customizing the menu bar with SwiftUI](https://developer.apple.com/documentation/SwiftUI/Building-and-customizing-the-menu-bar-with-SwiftUI)
- [Clean Architecture for SwiftUI - Alexey Naumov](https://nalexn.github.io/clean-architecture-swiftui/)
- [SwiftLee: MVVM architectural coding pattern for SwiftUI](https://www.avanderlee.com/swiftui/mvvm-architectural-coding-pattern-to-structure-views/)
- [SwiftLee: Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [Donny Wals: Swift 6.2 Main Actor isolation](https://www.donnywals.com/should-you-opt-in-to-swift-6-2s-main-actor-isolation/)
- [Swift by Sundell: MainActor attribute](https://www.swiftbysundell.com/articles/the-main-actor-attribute/)
- [Apple Developer: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Multi Blog: Pushing the limits of NSStatusItem](https://multi.app/blog/pushing-the-limits-nsstatusitem)
- [SwiftyPing: ICMP ping client for Swift](https://github.com/samiyr/SwiftyPing)

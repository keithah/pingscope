# PingMonitor Architecture

## System Overview

PingMonitor follows an MVVM (Model-View-ViewModel) architecture with a service layer for network operations and persistence.

```
┌─────────────────────────────────────────────────────────────┐
│                    MenuBarController                         │
│              (NSStatusItem + Popover/Window)                 │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                     Views Layer                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐    │
│  │ ContentView │ │ CompactView │ │ GraphView/HistoryView│   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘    │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   PingViewModel                              │
│            (ObservableObject, @Published state)              │
└─────────────────────┬───────────────────────────────────────┘
                      │
          ┌───────────┼───────────┬──────────────┐
          ▼           ▼           ▼              ▼
┌─────────────┐ ┌───────────┐ ┌────────────┐ ┌────────────┐
│ PingService │ │NetworkMon │ │Notification│ │Persistence │
│             │ │           │ │Service     │ │Service     │
└─────────────┘ └───────────┘ └────────────┘ └────────────┘
```

## Component Responsibilities

### MenuBarController

**File:** `Views/MenuBar/MenuBarController.swift`

The root controller that manages the menu bar integration:

- Creates and manages `NSStatusItem` for menu bar presence
- Renders status image with color dot and ping time text
- Handles left-click (toggle popover) and right-click (context menu)
- Manages popover vs floating window display modes
- Subscribes to ViewModel state changes via Combine

**Key Methods:**
- `setupMenuBar()` - Initializes NSStatusItem and popover
- `updateStatusDisplay()` - Redraws menu bar image with current ping status
- `createStatusImage()` - Generates NSImage with dot and text
- `handleClick()` - Routes clicks to popover toggle or context menu
- `createFloatingWindow()` - Creates borderless floating window for stay-on-top mode

### PingViewModel

**File:** `ViewModels/PingViewModel.swift`

Central state management using `@MainActor` and `ObservableObject`:

**Published State:**
- `hosts: [Host]` - List of monitored hosts
- `latestResult: PingResult?` - Most recent ping result for active host
- `pingHistory: [PingResult]` - History of all ping results
- `hostLatestResults: [String: PingResult]` - Latest result per host address
- UI toggles: `isCompactMode`, `isStayOnTop`, `showHosts`, `showGraph`, etc.

**Responsibilities:**
- Coordinates all four services
- Handles host CRUD operations
- Manages ping result processing and history
- Auto-saves settings on property changes via `didSet`
- Updates widget data on each ping result

### PingService

**File:** `Services/PingService.swift`

Core network latency measurement engine:

**Ping Methods:**

1. **ICMP (Simulated):** Since App Store sandbox prohibits raw ICMP sockets, this method tries TCP connections to ports 53, 80, 443, 22, 25 in sequence until one succeeds.

2. **UDP:** Uses `NWConnection` with `.udp` protocol. Default port 53 (DNS).

3. **TCP:** Direct TCP connection via `NWConnection`. Default port 80.

**Implementation Pattern:**
```swift
func performPing(host: Host, completion: @escaping (PingResult) -> Void) {
    queue.async {
        let startTime = Date()
        // Create NWConnection, start, wait for .ready state
        // Calculate: pingTime = Date().timeIntervalSince(startTime) * 1000
        // Return PingResult with status based on thresholds
    }
}
```

**Timer Management:**
- Each host has its own Timer for periodic pinging
- Timers stored by host address for cleanup
- Initial ping performed immediately, then at configured interval

### NetworkMonitor

**File:** `Services/NetworkMonitor.swift`

Gateway auto-discovery using SystemConfiguration framework:

```swift
func detectGateway() -> String {
    // 1. Create SCDynamicStore
    // 2. Get kSCDynamicStoreDomainState / kSCEntNetIPv4
    // 3. Extract kSCPropNetIPv4Router
    // 4. Fallback to primary service router
    // 5. Default to 192.168.1.1
}
```

**Features:**
- Refreshes gateway every 30 seconds
- Publishes changes via Combine (`gatewayPublisher`)
- ViewModel subscribes to detect gateway changes and update hosts

### NotificationService

**File:** `Services/NotificationService.swift`

Manages all 7 notification alert types:

| Alert Type | Trigger | Per-Host Setting |
|------------|---------|------------------|
| No Response | Transition from good to timeout/error | `onNoResponse` |
| High Latency | Ping exceeds threshold | `onThreshold`, `thresholdMs` |
| Recovery | Transition from bad to good | `onRecovery` |
| Degradation | Ping increases by X% from baseline | `onDegradation`, `degradationPercent` |
| Intermittent | N failures in M-ping window | `onPattern`, `patternThreshold`, `patternWindow` |
| Network Change | Gateway IP changes | Global setting |
| Internet Loss | All hosts fail simultaneously | Global setting |

**State Tracking:**
- `hostPreviousResults` - Previous result per host for transition detection
- `hostBaselinePing` - Minimum observed ping per host for degradation
- `hostPatternHistory` - Rolling window of success/failure for pattern detection

### PersistenceService

**File:** `Services/PersistenceService.swift`

Handles data persistence:

**UserDefaults Storage:**
- Host configurations (JSON encoded)
- All AppSettings flags

**App Group Shared Container:**
- Widget data file (`pingdata.json`)
- Written on every ping result update

## Data Flow

### Ping Result Flow

```
1. Timer fires for host
       ↓
2. PingService.performPing() executes
       ↓
3. NWConnection attempts connection
       ↓
4. PingResult created with timing
       ↓
5. Callback to PingViewModel.handlePingResult()
       ↓
6. ViewModel updates:
   - hostLatestResults[address]
   - pingHistory (insert at 0)
   - latestResult (if active host)
       ↓
7. NotificationService.checkConditions() runs
       ↓
8. PersistenceService.saveWidgetData() called
       ↓
9. @Published properties trigger SwiftUI updates
       ↓
10. MenuBarController.updateStatusDisplay() redraws icon
```

### Settings Change Flow

```
1. User toggles setting in UI
       ↓
2. @Published property changes
       ↓
3. didSet calls saveSettings()
       ↓
4. PersistenceService writes to UserDefaults
       ↓
5. UI automatically updates via SwiftUI binding
```

## Combine Integration

Key subscriptions in MenuBarController:

```swift
viewModel.$latestResult
    .sink { [weak self] _ in
        self?.updateStatusDisplay()
    }

viewModel.$isCompactMode
    .sink { [weak self] isCompact in
        self?.handleCompactModeChange(isCompact: isCompact)
    }

viewModel.$isStayOnTop
    .sink { [weak self] stayOnTop in
        self?.handleStayOnTopChange(stayOnTop: stayOnTop)
    }
```

Key subscriptions in PingViewModel:

```swift
networkMonitor.gatewayPublisher
    .dropFirst()
    .sink { [weak self] newGateway in
        self?.handleGatewayChange(newGateway)
    }
```

## Concurrency Model

- **PingService:** Uses dedicated `DispatchQueue` with `.utility` QoS
- **NWConnection:** Started on service queue, callbacks on same queue
- **Result Handling:** Dispatched to main thread for UI updates
- **PingViewModel:** `@MainActor` ensures all state changes on main thread
- **Timers:** Run on main thread (default RunLoop)

## Protocol-Based Design

All services have protocols for testability:

```swift
protocol PingServiceProtocol {
    func ping(host: Host) async -> PingResult
    func startPinging(hosts: [Host], resultHandler: @escaping (PingResult, Host) -> Void)
    func stopPinging()
}

protocol NetworkMonitorProtocol {
    var currentGateway: String { get }
    var gatewayPublisher: AnyPublisher<String, Never> { get }
    func startMonitoring()
    func stopMonitoring()
    func refreshGateway() -> String
}
```

Mock implementations provided for unit testing.

# PingMonitor Data Models

## Host

**File:** `Models/Host.swift`

Represents a monitored network host.

```swift
struct Host: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String              // Display name (e.g., "Google", "Cloudflare")
    var address: String           // IP address or hostname
    var isActive: Bool = false    // Currently selected host
    var isDefault: Bool = false   // Default host (cannot be deleted)
    var gatewayMode: GatewayMode = .auto  // Auto-discovered or manual
    var pingSettings: PingSettings = PingSettings()
    var notificationSettings: NotificationSettings = NotificationSettings()
}
```

### Default Hosts

Three default hosts are created on first launch:

```swift
static func defaultHosts(gatewayAddress: String) -> [Host] {
    [
        Host(name: "Google", address: "8.8.8.8", isActive: true, isDefault: true),
        Host(name: "Cloudflare", address: "1.1.1.1", isDefault: true),
        Host(name: "Default Gateway", address: gatewayAddress, isDefault: true, gatewayMode: .auto)
    ]
}
```

### Validation

```swift
var isValidAddress: Bool {
    // Validates IP address (4 octets, 0-255 each)
    // OR validates hostname (alphanumeric with hyphens, dots for subdomains)
}
```

### Display Helpers

```swift
var shortName: String {
    // "Google" → "GGL", "Cloudflare" → "CF", "Default Gateway" → "GW"
}

var isGateway: Bool {
    name == "Default Gateway"
}
```

---

## PingResult

**File:** `Models/PingResult.swift`

Represents a single ping measurement.

```swift
struct PingResult: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let host: String              // Host address that was pinged
    let pingTime: Double?         // Latency in milliseconds (nil for timeout)
    let status: PingStatus        // good, warning, error, timeout
}
```

### Factory Methods

```swift
// For successful ping
static func success(host: String, pingTime: Double, settings: PingSettings) -> PingResult {
    let status = settings.determineStatus(for: pingTime)
    return PingResult(host: host, pingTime: pingTime, status: status)
}

// For timeout
static func timeout(host: String) -> PingResult {
    PingResult(host: host, pingTime: nil, status: .timeout)
}
```

### Computed Properties

```swift
var formattedPingTime: String {
    // "25ms" or "1.5s" or "--" for timeout
}

var formattedTimestamp: String {
    // "14:32:05" (HH:mm:ss format)
}

var isSuccessful: Bool {
    status != .timeout && pingTime != nil
}
```

---

## PingSettings

**File:** `Models/PingSettings.swift`

Per-host ping configuration.

```swift
struct PingSettings: Codable, Equatable {
    var interval: Double = 2.0        // Ping frequency in seconds
    var timeout: Double = 3.0         // Max wait for response in seconds
    var type: PingType = .icmp        // icmp, udp, or tcp
    var goodThreshold: Double = 50.0  // < 50ms = good status
    var warningThreshold: Double = 200.0  // < 200ms = warning, >= 200ms = error
    var port: Int? = nil              // Custom port for UDP/TCP pings
}
```

### Status Determination

```swift
func determineStatus(for pingTime: Double) -> PingStatus {
    if pingTime < goodThreshold {
        return .good
    } else if pingTime < warningThreshold {
        return .warning
    } else {
        return .error
    }
}
```

### Validation

```swift
var isValid: Bool {
    interval > 0 &&
    timeout > 0 &&
    goodThreshold > 0 &&
    warningThreshold > goodThreshold &&
    (port == nil || (port! > 0 && port! <= 65535))
}
```

---

## NotificationSettings

**File:** `Models/NotificationSettings.swift`

Per-host notification configuration for the 7 alert types.

```swift
struct NotificationSettings: Codable, Equatable {
    // Master toggle for this host
    var enabled: Bool = false

    // Alert Type 1: No Response
    var onNoResponse: Bool = false

    // Alert Type 2: High Latency
    var onThreshold: Bool = false
    var thresholdMs: Double = 2000.0

    // Alert Type 3: Recovery
    var onRecovery: Bool = false

    // Alert Type 4: Degradation
    var onDegradation: Bool = false
    var degradationPercent: Double = 50.0

    // Alert Type 5: Intermittent Failures
    var onPattern: Bool = false
    var patternThreshold: Int = 3     // Failures needed to trigger
    var patternWindow: Int = 10       // Window size

    // Alert Type 6: Network Change (handled globally, not per-host)
    var onNetworkChange: Bool = false
}
```

### Preset Configuration

```swift
static var enabledWithDefaults: NotificationSettings {
    var settings = NotificationSettings()
    settings.enabled = true
    settings.onNoResponse = true
    settings.onThreshold = true
    settings.onRecovery = true
    return settings
}
```

---

## AppSettings

**File:** `Services/PersistenceService.swift`

Application-wide settings stored in UserDefaults.

```swift
struct AppSettings: Codable {
    var isCompactMode: Bool = false
    var isStayOnTop: Bool = false
    var startOnLaunch: Bool = false
    var notificationsEnabled: Bool = false
    var notifyNoInternet: Bool = false
    var notifyNetworkChange: Bool = false
    var notifyAllHosts: Bool = false
    var showHosts: Bool = true
    var showGraph: Bool = true
    var showHistory: Bool = true
    var showHistorySummary: Bool = false
}
```

---

## WidgetHostData

**File:** `Services/PersistenceService.swift`

Data structure written to shared container for widget consumption.

```swift
struct WidgetHostData: Codable {
    let hostName: String
    let address: String
    let pingTime: Double?
    let status: String  // "good", "warning", "error", "timeout"
}
```

---

## PingStatistics

**File:** `Utilities/Extensions.swift`

Computed statistics for an array of ping results.

```swift
struct PingStatistics {
    let transmitted: Int      // Total pings sent
    let received: Int         // Successful pings
    let packetLoss: Double    // Percentage (0-100)
    let min: Double           // Minimum latency
    let avg: Double           // Average latency
    let max: Double           // Maximum latency
    let stddev: Double        // Standard deviation
}
```

### Display Methods

```swift
var summaryText: String {
    // "10 transmitted, 9 received, 10.0% packet loss"
}

var rttText: String {
    // "RTT min/avg/max/stddev = 5.123/12.456/25.789/3.210 ms"
}
```

---

## Enumerations

**File:** `Models/Enums.swift`

### PingStatus

```swift
enum PingStatus: String, Codable {
    case good       // Green - latency below good threshold
    case warning    // Yellow - latency between thresholds
    case error      // Red - latency above warning threshold
    case timeout    // Gray - no response received

    var color: NSColor { ... }
    var swiftUIColor: Color { ... }
    var description: String { ... }  // "Good", "Slow", "High", "Down"
}
```

### PingType

```swift
enum PingType: String, CaseIterable, Codable {
    case icmp = "ICMP"  // Simulated via TCP to multiple ports
    case udp = "UDP"    // UDP connection (default port 53)
    case tcp = "TCP"    // TCP connection (default port 80)

    var defaultPort: Int? { ... }
}
```

### GatewayMode

```swift
enum GatewayMode: String, CaseIterable, Codable {
    case auto = "Auto-discovered"   // SystemConfiguration detection
    case manual = "Manual Entry"    // User-specified address
}
```

### TimeFilter

```swift
enum TimeFilter: String, CaseIterable {
    case oneMinute = "1 min"
    case fiveMinutes = "5 min"
    case tenMinutes = "10 min"
    case oneHour = "1 hour"

    var timeInterval: TimeInterval { ... }
}
```

### ExportFormat

```swift
enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"
    case txt = "Text"

    var fileExtension: String { rawValue.lowercased() }
}
```

### ExportTimeRange

```swift
enum ExportTimeRange: String, CaseIterable {
    case lastHour = "Last Hour"
    case last24Hours = "Last 24 Hours"
    case lastWeek = "Last Week"
    case all = "All Time"

    var cutoffDate: Date { ... }
}
```

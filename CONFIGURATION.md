# PingMonitor Configuration

**File:** `Utilities/Constants.swift`

## Application Configuration

```swift
enum Constants {
    enum App {
        static let bundleIdentifier = "com.hadm.pingmonitor"
        static let appGroupIdentifier = "group.com.hadm.pingmonitor.shared"
        static let widgetDataFilename = "pingdata.json"
    }
}
```

---

## Menu Bar Configuration

```swift
enum MenuBar {
    static let statusItemWidth: CGFloat = 40   // Total width of menu bar item
    static let dotSize: CGFloat = 8            // Status indicator dot diameter
    static let fontSize: CGFloat = 9           // Ping time text size
}
```

**Visual Layout:**
```
┌──────────────────────────────────────┐
│         40px wide item               │
│                                      │
│        ● (8px dot, top)              │
│       12ms (9pt text, bottom)        │
│                                      │
└──────────────────────────────────────┘
```

---

## Window Sizes

```swift
enum Window {
    // Full view mode
    static let fullWidth: CGFloat = 450
    static let fullHeight: CGFloat = 500

    // Compact view mode
    static let compactWidth: CGFloat = 280
    static let compactHeight: CGFloat = 220

    // Settings sheet
    static let settingsWidth: CGFloat = 500
    static let settingsHeight: CGFloat = 580

    // Export sheet
    static let exportWidth: CGFloat = 400
    static let exportHeight: CGFloat = 300
}
```

---

## Graph Configuration

```swift
enum Graph {
    // Full view graph
    static let height: CGFloat = 140
    static let horizontalGridLines = 4
    static let verticalGridLines = 5
    static let dataPointSize: CGFloat = 6
    static let lineWidth: CGFloat = 2.5

    // Compact view graph
    static let compactHeight: CGFloat = 60
    static let compactDataPointSize: CGFloat = 4
    static let compactLineWidth: CGFloat = 1.5
}
```

---

## History Configuration

```swift
enum History {
    static let maxResults = 100        // Maximum ping results to retain
    static let fullViewHeight: CGFloat = 160   // Scrollable area height
    static let compactMaxItems = 6     // Results shown in compact mode
}
```

---

## Timing Configuration

```swift
enum Timing {
    static let defaultPingInterval: TimeInterval = 2.0    // Seconds between pings
    static let defaultTimeout: TimeInterval = 3.0         // Max wait for response
    static let gatewayRefreshInterval: TimeInterval = 30.0 // Gateway re-detection
    static let widgetRefreshInterval: TimeInterval = 5.0   // Widget timeline update
}
```

---

## Threshold Configuration

```swift
enum Threshold {
    // Status determination (in milliseconds)
    static let goodPingMs: Double = 50.0      // < 50ms = good (green)
    static let warningPingMs: Double = 200.0  // < 200ms = warning (yellow)
                                               // >= 200ms = error (red)

    // Notification defaults
    static let defaultNotificationThresholdMs: Double = 2000.0
    static let defaultDegradationPercent: Double = 50.0

    // Pattern detection
    static let defaultPatternThreshold = 3     // Failures to trigger alert
    static let defaultPatternWindow = 10       // Window size for detection
    static let patternHistorySize = 20         // Rolling history buffer
}
```

---

## Port Configuration

```swift
enum Ports {
    // Ports tried for ICMP simulation (in order)
    static let icmpProbe: [UInt16] = [53, 80, 443, 22, 25]

    // Default ports for explicit protocols
    static let udpDefault: UInt16 = 53   // DNS
    static let tcpDefault: UInt16 = 80   // HTTP
}
```

**ICMP Simulation Flow:**
1. Try TCP connection to port 53 (DNS)
2. If timeout, try port 80 (HTTP)
3. If timeout, try port 443 (HTTPS)
4. If timeout, try port 22 (SSH)
5. If timeout, try port 25 (SMTP)
6. If all fail, return timeout status

Each probe gets `timeout / 5` seconds to complete.

---

## UserDefaults Keys

```swift
enum UserDefaultsKeys {
    // Host storage
    static let hosts = "pingmonitor.hosts"

    // UI state
    static let isCompactMode = "pingmonitor.isCompactMode"
    static let isStayOnTop = "pingmonitor.isStayOnTop"
    static let startOnLaunch = "pingmonitor.startOnLaunch"

    // Notification settings
    static let notificationsEnabled = "pingmonitor.notificationsEnabled"
    static let notifyNoInternet = "pingmonitor.notifyNoInternet"
    static let notifyNetworkChange = "pingmonitor.notifyNetworkChange"
    static let notifyAllHosts = "pingmonitor.notifyAllHosts"

    // Display settings
    static let showHosts = "pingmonitor.showHosts"
    static let showGraph = "pingmonitor.showGraph"
    static let showHistory = "pingmonitor.showHistory"
    static let showHistorySummary = "pingmonitor.showHistorySummary"
}
```

---

## Default Values Summary

| Setting | Default Value |
|---------|---------------|
| Ping Interval | 2.0 seconds |
| Ping Timeout | 3.0 seconds |
| Good Threshold | < 50 ms |
| Warning Threshold | < 200 ms |
| Error Threshold | >= 200 ms |
| Gateway Refresh | 30 seconds |
| Widget Refresh | 5 seconds |
| Max History | 100 results |
| Compact History | 6 results |
| ICMP Probe Ports | 53, 80, 443, 22, 25 |
| UDP Default Port | 53 |
| TCP Default Port | 80 |
| Notification Threshold | 2000 ms |
| Degradation Percent | 50% |
| Pattern Threshold | 3 failures |
| Pattern Window | 10 pings |

---

## Extensions Helper Utilities

**File:** `Utilities/Extensions.swift`

### Date Formatting

```swift
extension Date {
    var timeString: String {
        // "14:32:05" format
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: self)
    }

    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}
```

### Numeric Formatting

```swift
extension Double {
    var formattedPingTime: String {
        if self < 1000 {
            return String(format: "%.0fms", self)  // "25ms"
        } else {
            return String(format: "%.1fs", self / 1000)  // "1.5s"
        }
    }

    func formatted(decimals: Int) -> String {
        guard isFinite && !isNaN else { return "0.000" }
        return String(format: "%.\(decimals)f", self)
    }
}
```

### Array Statistics

```swift
extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let avg = average
        let variance = map { pow($0 - avg, 2) }.reduce(0, +) / Double(count)
        return variance.isFinite ? sqrt(variance) : 0.0
    }
}
```

### PingResult Array Filtering

```swift
extension Array where Element == PingResult {
    func filtered(by host: String) -> [PingResult] {
        filter { $0.host == host }
    }

    func filtered(since date: Date) -> [PingResult] {
        filter { $0.timestamp >= date }
    }

    func filtered(by timeFilter: TimeFilter) -> [PingResult] {
        let cutoff = Date().addingTimeInterval(-timeFilter.timeInterval)
        return filter { $0.timestamp >= cutoff }
    }

    var successfulPingTimes: [Double] {
        compactMap { $0.pingTime }
    }

    var statistics: PingStatistics {
        PingStatistics(from: self)
    }
}
```

### Color Palette

```swift
extension Color {
    static let pingGood = Color.green
    static let pingWarning = Color.yellow
    static let pingError = Color.red
    static let pingTimeout = Color.gray
}
```

### Conditional View Modifier

```swift
extension View {
    func conditionalModifier<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        Group {
            if condition {
                transform(self)
            } else {
                self
            }
        }
    }
}
```

---

## Entitlements

**File:** `entitlements-appstore.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <key>com.apple.security.network.client</key>
    <true/>

    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.hadm.pingmonitor.shared</string>
    </array>
</dict>
</plist>
```

### Entitlement Purposes

| Entitlement | Purpose |
|-------------|---------|
| `app-sandbox` | Required for App Store distribution |
| `network.client` | Allows outgoing network connections for pings |
| `files.user-selected.read-write` | Allows exporting data to user-selected files |
| `application-groups` | Enables shared container for widget data |

---

## Info.plist Configuration

```xml
<key>CFBundleIdentifier</key>
<string>com.hadm.pingmonitor</string>

<key>CFBundleDisplayName</key>
<string>PingScope</string>

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>LSUIElement</key>
<true/>  <!-- No dock icon, menu bar app only -->

<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>
```

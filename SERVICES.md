# PingMonitor Services

## PingService

**File:** `Services/PingService.swift`

Core network latency measurement engine using Network.framework.

### Protocol

```swift
protocol PingServiceProtocol {
    func ping(host: Host) async -> PingResult
    func startPinging(hosts: [Host], resultHandler: @escaping (PingResult, Host) -> Void)
    func stopPinging()
}
```

### Implementation Details

#### Queue Management

```swift
private var timers: [String: Timer] = [:]           // Keyed by host address
private var activeConnections: [String: NWConnection] = [:]
private let queue = DispatchQueue(label: "com.hadm.pingmonitor.pingservice", qos: .utility)
```

#### Starting Pings

```swift
func startPinging(host: Host, resultHandler: @escaping (PingResult, Host) -> Void) {
    // 1. Cancel existing timer for this host
    timers[host.address]?.invalidate()

    // 2. Create repeating timer at host.pingSettings.interval
    let timer = Timer.scheduledTimer(withTimeInterval: host.pingSettings.interval, repeats: true) { _ in
        self.performPing(host: host, completion: resultHandler)
    }
    timers[host.address] = timer

    // 3. Perform initial ping immediately
    performPing(host: host, completion: resultHandler)
}
```

#### ICMP Ping (Sandbox-Compatible)

Since true ICMP requires raw sockets (not allowed in App Store sandbox), ICMP pings are simulated via TCP connections to common ports:

```swift
private func performICMPPing(host: Host) -> PingResult {
    let startTime = Date()

    // Try ports: 53 (DNS), 80 (HTTP), 443 (HTTPS), 22 (SSH), 25 (SMTP)
    for port in Constants.Ports.icmpProbe {
        let timeout = host.pingSettings.timeout / Double(Constants.Ports.icmpProbe.count)
        let result = tryTCPConnection(host: host.address, port: port, timeout: timeout, ...)

        if result.status != .timeout {
            return result
        }
    }

    return .timeout(host: host.address)
}
```

#### UDP Ping

```swift
private func performUDPPing(host: Host) -> PingResult {
    let port = UInt16(host.pingSettings.port ?? Constants.Ports.udpDefault)  // Default: 53
    let startTime = Date()

    let connection = NWConnection(
        host: NWEndpoint.Host(host.address),
        port: NWEndpoint.Port(integerLiteral: port),
        using: .udp
    )

    connection.start(queue: queue)

    // Wait for .ready state or timeout
    // Calculate pingTime = Date().timeIntervalSince(startTime) * 1000
}
```

#### TCP Ping

```swift
private func performTCPPing(host: Host) -> PingResult {
    let port = UInt16(host.pingSettings.port ?? Constants.Ports.tcpDefault)  // Default: 80

    let connection = NWConnection(
        host: NWEndpoint.Host(host.address),
        port: NWEndpoint.Port(integerLiteral: port),
        using: .tcp
    )

    // Similar to UDP but with .tcp protocol
}
```

#### TCP Connection Helper

Common pattern for both TCP pings and ICMP simulation:

```swift
private func tryTCPConnection(host: String, port: UInt16, timeout: TimeInterval,
                               startTime: Date, settings: PingSettings) -> PingResult {
    var result: PingResult?
    let semaphore = DispatchSemaphore(value: 0)

    let connection = NWConnection(...)
    connection.start(queue: queue)

    // Timeout handler
    queue.asyncAfter(deadline: .now() + timeout) {
        connection.cancel()
        if result == nil {
            result = .timeout(host: host)
            semaphore.signal()
        }
    }

    // State handler
    connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
            let pingTime = Date().timeIntervalSince(startTime) * 1000
            result = .success(host: host, pingTime: pingTime, settings: settings)
            connection.cancel()
            semaphore.signal()
        case .failed, .cancelled:
            if result == nil {
                result = .timeout(host: host)
                semaphore.signal()
            }
        default:
            break
        }
    }

    semaphore.wait()
    return result ?? .timeout(host: host)
}
```

---

## NetworkMonitor

**File:** `Services/NetworkMonitor.swift`

Gateway auto-discovery and network monitoring using SystemConfiguration framework.

### Protocol

```swift
protocol NetworkMonitorProtocol {
    var currentGateway: String { get }
    var gatewayPublisher: AnyPublisher<String, Never> { get }
    func startMonitoring()
    func stopMonitoring()
    func refreshGateway() -> String
}
```

### Gateway Detection

Uses SystemConfiguration to read system network state:

```swift
private func detectGateway() -> String {
    // 1. Create SCDynamicStore reference
    guard let store = SCDynamicStoreCreate(nil, "PingMonitor" as CFString, nil, nil) else {
        return fallbackGateway
    }

    // 2. Get global IPv4 configuration key
    let globalIPv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
        nil,
        kSCDynamicStoreDomainState,
        kSCEntNetIPv4
    )

    // 3. Read global IPv4 dictionary
    guard let globalIPv4Dict = SCDynamicStoreCopyValue(store, globalIPv4Key) as? [String: Any] else {
        return fallbackGateway
    }

    // 4. Try to get router from global dict
    if let primaryRouter = globalIPv4Dict[kSCPropNetIPv4Router as String] as? String {
        return primaryRouter
    }

    // 5. Fallback: get from primary service
    guard let serviceKey = globalIPv4Dict[kSCDynamicStorePropNetPrimaryService as String] as? String else {
        return fallbackGateway
    }

    let serviceIPv4Key = SCDynamicStoreKeyCreateNetworkServiceEntity(
        nil,
        kSCDynamicStoreDomainState,
        serviceKey as CFString,
        kSCEntNetIPv4
    )

    // 6. Read service-specific router
    guard let serviceIPv4Dict = SCDynamicStoreCopyValue(store, serviceIPv4Key) as? [String: Any],
          let routerIP = serviceIPv4Dict[kSCPropNetIPv4Router as String] as? String else {
        return fallbackGateway
    }

    return routerIP
}
```

### Periodic Refresh

```swift
func startMonitoring() {
    refreshTimer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.gatewayRefreshInterval,
                                         repeats: true) { [weak self] _ in
        _ = self?.refreshGateway()
    }
}
```

Default refresh interval: 30 seconds.

---

## NotificationService

**File:** `Services/NotificationService.swift`

Alert management for all 7 notification types using UNUserNotificationCenter.

### Protocol

```swift
protocol NotificationServiceProtocol {
    var isEnabled: Bool { get set }
    func requestPermission() async -> Bool
    func checkConditions(result: PingResult, host: Host, previousResult: PingResult?)
    func sendNotification(title: String, body: String)
}
```

### State Tracking

```swift
private var hostPreviousResults: [String: PingResult] = [:]  // For transition detection
private var hostFailureCount: [String: Int] = [:]             // (unused but available)
private var hostBaselinePing: [String: Double] = [:]          // For degradation detection
private var hostPatternHistory: [String: [Bool]] = [:]        // Success/failure rolling window
```

### Permission Request

```swift
func requestPermission() async -> Bool {
    do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await MainActor.run {
            self.isEnabled = granted
        }
        return granted
    } catch {
        return false
    }
}
```

### Alert Type Checks

#### Alert 1: No Response

```swift
private func checkNoResponse(result: PingResult, host: Host, previousResult: PingResult?,
                              settings: NotificationSettings) {
    guard settings.onNoResponse else { return }
    guard result.status == .timeout || result.status == .error else { return }

    // Only alert on transition from good to bad
    if previousResult?.status == .good || previousResult == nil {
        sendNotification(title: "\(host.name) Not Responding",
                        body: "Unable to reach \(host.address)")
    }
}
```

#### Alert 2: High Latency

```swift
private func checkHighLatency(result: PingResult, host: Host, settings: NotificationSettings) {
    guard settings.onThreshold else { return }
    guard let pingTime = result.pingTime else { return }

    if pingTime > settings.thresholdMs {
        sendNotification(title: "\(host.name) High Latency",
                        body: "Ping time: \(pingTime)ms (threshold: \(settings.thresholdMs)ms)")
    }
}
```

#### Alert 3: Recovery

```swift
private func checkRecovery(result: PingResult, host: Host, previousResult: PingResult?,
                           settings: NotificationSettings) {
    guard settings.onRecovery else { return }
    guard result.status == .good else { return }
    guard let previous = previousResult else { return }

    if previous.status == .timeout || previous.status == .error {
        sendNotification(title: "\(host.name) Recovered",
                        body: "Connection restored to \(host.address)")
    }
}
```

#### Alert 4: Degradation

```swift
private func checkDegradation(result: PingResult, host: Host, settings: NotificationSettings) {
    guard settings.onDegradation else { return }
    guard let pingTime = result.pingTime else { return }
    guard let baseline = hostBaselinePing[host.address] else { return }

    let percentIncrease = ((pingTime - baseline) / baseline) * 100

    if percentIncrease > settings.degradationPercent {
        sendNotification(title: "\(host.name) Performance Degraded",
                        body: "Ping increased by \(percentIncrease)%")
    }
}
```

#### Alert 5: Intermittent Pattern

```swift
private func checkPattern(host: Host, settings: NotificationSettings) {
    guard settings.onPattern else { return }
    guard let history = hostPatternHistory[host.address] else { return }
    guard history.count >= settings.patternWindow else { return }

    let recentHistory = Array(history.suffix(settings.patternWindow))
    let failures = recentHistory.filter { !$0 }.count

    if failures >= settings.patternThreshold {
        sendNotification(title: "\(host.name) Intermittent Failures",
                        body: "\(failures) failures in last \(settings.patternWindow) pings")
    }
}
```

#### Alert 6: Network Change (Global)

```swift
func checkNetworkChange(oldGateway: String, newGateway: String) {
    guard isEnabled && notifyNetworkChange else { return }

    sendNotification(title: "Network Change Detected",
                    body: "Gateway changed from \(oldGateway) to \(newGateway)")
}
```

#### Alert 7: Internet Loss (Global)

```swift
func checkInternetLoss(hosts: [Host], latestResults: [String: PingResult]) {
    guard isEnabled && notifyNoInternet else { return }

    let failingHosts = hosts.filter { host in
        guard let result = latestResults[host.address] else { return false }
        return result.status == .timeout || result.status == .error
    }

    if failingHosts.count == hosts.count {
        sendNotification(title: "Internet Connection Lost",
                        body: "All monitored hosts are unreachable")
    }
}
```

---

## PersistenceService

**File:** `Services/PersistenceService.swift`

Settings storage and widget data sharing.

### Protocol

```swift
protocol PersistenceServiceProtocol {
    func saveHosts(_ hosts: [Host])
    func loadHosts() -> [Host]?
    func saveSettings(_ settings: AppSettings)
    func loadSettings() -> AppSettings
    func saveWidgetData(_ data: [WidgetHostData])
}
```

### UserDefaults Storage

Host configurations are JSON-encoded:

```swift
func saveHosts(_ hosts: [Host]) {
    let data = try encoder.encode(hosts)
    defaults.set(data, forKey: Constants.UserDefaultsKeys.hosts)
}

func loadHosts() -> [Host]? {
    guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.hosts) else { return nil }
    return try decoder.decode([Host].self, from: data)
}
```

Settings are stored as individual keys:

```swift
func saveSettings(_ settings: AppSettings) {
    defaults.set(settings.isCompactMode, forKey: Constants.UserDefaultsKeys.isCompactMode)
    defaults.set(settings.isStayOnTop, forKey: Constants.UserDefaultsKeys.isStayOnTop)
    // ... etc for all settings
}
```

### Widget Data Sharing

Uses App Group container for cross-process data sharing:

```swift
private var sharedContainerURL: URL? {
    FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Constants.App.appGroupIdentifier
    )
}

func saveWidgetData(_ data: [WidgetHostData]) {
    guard let sharedURL = sharedContainerURL else { return }

    try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)
    let fileURL = sharedURL.appendingPathComponent(Constants.App.widgetDataFilename)
    let jsonData = try encoder.encode(data)
    try jsonData.write(to: fileURL)
}
```

File written: `pingdata.json` in App Group container.

# Phase 6: Notifications & Settings - Research

**Researched:** 2026-02-15
**Domain:** macOS Notifications (UserNotifications framework) and Settings/Preferences UI (SwiftUI)
**Confidence:** HIGH

## Summary

Phase 6 implements two interconnected subsystems: an intelligent notification service that alerts users to network status changes, and a comprehensive settings panel that consolidates host, notification, and display configuration. The app already has UserDefaults-backed persistence patterns established in `HostStore`, `ModePreferenceStore`, and `DisplayPreferencesStore`. The notification system uses Apple's `UserNotifications` framework (macOS 10.14+), which is well-suited for the app's macOS 13.0+ target.

The primary technical challenge is implementing smart notification logic that detects 7 distinct alert conditions (no response, high latency, recovery, degradation, intermittent failures, network change, internet loss) without spamming the user. This requires cooldown/debounce logic and state tracking per host. The settings UI can leverage SwiftUI's native `Settings` scene with `TabView` for a platform-standard preferences window.

**Primary recommendation:** Build a `NotificationService` actor that observes ping results via the existing scheduler callback, maintains per-host alert state, and emits notifications through `UNUserNotificationCenter` with configurable cooldown periods.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| UserNotifications | macOS 10.14+ | Local notification delivery | Apple's standard notification framework; async/await compatible |
| Foundation (UserDefaults) | Built-in | Settings persistence | Already in use; simple key-value storage |
| SwiftUI (Settings scene) | macOS 13.0+ | Settings UI | Native preferences window; responds to Cmd+, |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Combine | Built-in | Reactive bindings | @AppStorage sync with runtime state (already in use) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| UserNotifications | NSUserNotification (deprecated) | NSUserNotification removed in macOS 11; must use UN* framework |
| UserDefaults | SwiftData/Core Data | Overkill for simple key-value preferences; UserDefaults sufficient |
| TabView Settings | Custom NSWindow | TabView in Settings scene is native; custom window loses Cmd+, integration |

**Installation:**
No external dependencies. All frameworks are built-in.

## Architecture Patterns

### Recommended Project Structure

```
Sources/PingScope/
├── Services/
│   └── NotificationService.swift    # Actor for notification logic
├── Models/
│   ├── NotificationPreferences.swift  # Per-host and global notification settings
│   └── AlertType.swift              # Enum for 7 alert types
├── MenuBar/
│   └── NotificationPreferencesStore.swift  # UserDefaults persistence
└── Views/
    └── Settings/
        ├── HostSettingsView.swift      # Host management tab
        ├── NotificationSettingsView.swift  # Notification config tab
        └── DisplaySettingsView.swift   # Already exists; enhance for tab
```

### Pattern 1: Actor-Based Notification Service

**What:** Encapsulate notification state and emission logic in a Swift actor
**When to use:** Anytime you need thread-safe state tracking for per-host alert conditions
**Example:**

```swift
// Source: Project architecture pattern (existing HostStore, PingScheduler actors)
actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var alertState: [UUID: HostAlertState] = [:]
    private var globalEnabled: Bool = true
    private var cooldownPeriod: Duration = .seconds(60)

    func evaluate(result: PingResult, for host: Host, isHostUp: Bool) async {
        guard globalEnabled, host.notificationsEnabled else { return }

        let state = alertState[host.id] ?? HostAlertState()
        let alerts = detectAlerts(result: result, host: host, isHostUp: isHostUp, state: state)

        for alert in alerts {
            if state.canSend(alert: alert, cooldown: cooldownPeriod) {
                await sendNotification(alert: alert, host: host)
                state.recordSent(alert: alert)
            }
        }

        alertState[host.id] = state
    }
}
```

### Pattern 2: TabView Settings with Form

**What:** Use SwiftUI's Settings scene with TabView and Form for native preferences
**When to use:** Building the main settings window
**Example:**

```swift
// Source: Apple SwiftUI documentation, serialcoder.dev tutorial
@main
struct PingScopeApp: App {
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            HostSettingsView()
                .tabItem { Label("Hosts", systemImage: "server.rack") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "display") }
        }
        .frame(width: 480, height: 400)
    }
}
```

### Pattern 3: Codable Notification Preferences

**What:** Store notification preferences as Codable struct in UserDefaults
**When to use:** Per-host notification settings persistence
**Example:**

```swift
// Source: Project pattern (HostStore, DisplayPreferencesStore)
struct NotificationPreferences: Codable, Sendable {
    var globalEnabled: Bool = true
    var cooldownSeconds: TimeInterval = 60
    var alertTypes: Set<AlertType> = Set(AlertType.allCases)
    var hostOverrides: [UUID: HostNotificationConfig] = [:]
}

final class NotificationPreferencesStore {
    private let userDefaults: UserDefaults
    private let key = "notifications.preferences"

    func load() -> NotificationPreferences {
        guard let data = userDefaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data)
        else { return NotificationPreferences() }
        return prefs
    }

    func save(_ prefs: NotificationPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        userDefaults.set(data, forKey: key)
    }
}
```

### Anti-Patterns to Avoid

- **Notification spam without cooldown:** Always debounce repeated alerts of the same type for the same host
- **Synchronous notification center access:** Use async/await APIs for requestAuthorization and add()
- **Hardcoded alert thresholds:** Make all thresholds configurable (latency threshold, failure count, degradation %)
- **Mixed actor isolation in delegate:** UNUserNotificationCenterDelegate methods must be `nonisolated` in Swift 6

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Notification permission | Custom permission dialog | UNUserNotificationCenter.requestAuthorization | System-standard flow; respects user preferences |
| Settings window lifecycle | NSWindowController for settings | SwiftUI Settings scene | Auto-handles Cmd+,; system-standard behavior |
| Notification sound | Custom audio player | UNNotificationSound.default | System-consistent; respects user sound settings |
| Tab-based preferences | Custom segmented control | TabView in Settings scene | Native macOS appearance |

**Key insight:** Apple's Settings scene and UserNotifications framework handle most boilerplate. Focus implementation on the alert detection logic and per-host state tracking.

## Common Pitfalls

### Pitfall 1: Notification Authorization Not Requested

**What goes wrong:** Notifications silently fail because authorization was never requested
**Why it happens:** Assuming macOS auto-grants permission or forgetting to call requestAuthorization()
**How to avoid:** Request authorization at app launch; check notificationSettings() before sending
**Warning signs:** Zero notifications appear despite code executing

### Pitfall 2: Delegate Method Isolation in Swift 6

**What goes wrong:** Compilation errors with UNUserNotificationCenterDelegate methods in Swift 6
**Why it happens:** Delegate methods need `nonisolated` but may need main actor for UI updates
**How to avoid:** Mark delegate methods as `nonisolated`, then dispatch to main actor for state updates
**Warning signs:** "Non-sendable type crossing actor boundary" errors

### Pitfall 3: Notification Spam During Flaky Network

**What goes wrong:** User receives dozens of alerts during brief network instability
**Why it happens:** Every failed ping triggers an alert without cooldown
**How to avoid:** Implement per-host, per-alert-type cooldown tracking (60-120 second minimum)
**Warning signs:** Notification center flooded during brief connectivity blips

### Pitfall 4: Settings State Desync

**What goes wrong:** Toggle state in settings UI doesn't match runtime behavior
**Why it happens:** @AppStorage and runtime state managed separately
**How to avoid:** Use existing pattern: @AppStorage reads, Binding setter updates both UserDefaults and runtime
**Warning signs:** Restarting app shows different toggle states than expected

### Pitfall 5: Missing Privacy Manifest

**What goes wrong:** App rejected from App Store
**Why it happens:** UserDefaults usage requires privacy manifest declaration since May 2024
**How to avoid:** Create PrivacyInfo.xcprivacy with NSPrivacyAccessedAPICategoryUserDefaults and CA92.1 reason
**Warning signs:** ITMS-91053 rejection during App Store submission

## Code Examples

### UNUserNotificationCenter Authorization (async/await)

```swift
// Source: Apple Developer Documentation, createwithswift.com
import UserNotifications

func requestNotificationPermission() async throws -> Bool {
    let center = UNUserNotificationCenter.current()
    let granted = try await center.requestAuthorization(options: [.alert, .sound])
    return granted
}

func checkAuthorizationStatus() async -> UNAuthorizationStatus {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus
}
```

### Sending Local Notification

```swift
// Source: hackingwithswift.com
func sendNotification(title: String, body: String, identifier: String) async throws {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    // Immediate delivery with small delay
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    try await UNUserNotificationCenter.current().add(request)
}
```

### Alert Detection Logic

```swift
// Source: Project architecture (derived from requirements)
enum AlertType: String, Codable, CaseIterable {
    case noResponse       // NOTF-02: Host transitions from good to no response
    case highLatency      // NOTF-03: Ping exceeds configurable threshold
    case recovery         // NOTF-04: Host recovers from failure
    case degradation      // NOTF-05: Latency increases by X%
    case intermittent     // NOTF-06: N failures in M-ping window
    case networkChange    // NOTF-07: Gateway IP changes
    case internetLoss     // NOTF-08: All hosts fail
}

struct HostAlertState: Sendable {
    var previousLatencyMS: Double?
    var wasDown: Bool = false
    var recentFailures: [Date] = []
    var lastAlertTimes: [AlertType: Date] = [:]

    mutating func canSend(alert: AlertType, cooldown: Duration) -> Bool {
        guard let lastSent = lastAlertTimes[alert] else { return true }
        return Date().timeIntervalSince(lastSent) >= cooldown.timeInterval
    }

    mutating func recordSent(alert: AlertType) {
        lastAlertTimes[alert] = Date()
    }
}
```

### Privacy Manifest (PrivacyInfo.xcprivacy)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSUserNotification | UNUserNotificationCenter | macOS 10.14 | NSUserNotification deprecated, removed in macOS 11 |
| Completion handlers | async/await for notifications | Swift 5.5/macOS 12 | Cleaner code; requestAuthorization(options:) is async |
| Manual preferences window | SwiftUI Settings scene | SwiftUI 3.0 (macOS 12) | Automatic Cmd+, integration |
| No privacy manifest | PrivacyInfo.xcprivacy required | May 2024 | App Store rejection without manifest |

**Deprecated/outdated:**
- NSUserNotification: Removed in macOS 11; use UNUserNotificationCenter
- Completion handler APIs: Still work but async/await versions are preferred

## Open Questions

1. **Notification grouping behavior**
   - What we know: UNNotificationContent has threadIdentifier for grouping
   - What's unclear: Best grouping strategy (by host? by alert type?)
   - Recommendation: Group by host using host.id as threadIdentifier

2. **Degradation percentage threshold**
   - What we know: NOTF-05 requires alerting on "X% increase"
   - What's unclear: What percentage is sensible default? Over what time window?
   - Recommendation: Default to 50% increase over 5-minute average; make configurable

3. **Intermittent failure window size**
   - What we know: NOTF-06 requires "N failures in M-ping window"
   - What's unclear: What N/M values provide useful signal vs. noise?
   - Recommendation: Default to 3 failures in 10-ping window; make configurable

## Sources

### Primary (HIGH confidence)
- [UNUserNotificationCenter | Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) - Core notification APIs
- [Hacking with Swift - Local Notifications](https://www.hackingwithswift.com/example-code/system/how-to-set-local-alerts-using-unnotificationcenter) - Code examples verified
- Project codebase: `HostStore.swift`, `DisplayPreferencesStore.swift`, `ModePreferenceStore.swift` - Existing UserDefaults patterns

### Secondary (MEDIUM confidence)
- [SerialCoder.dev - macOS Preferences Window](https://serialcoder.dev/text-tutorials/macos-tutorials/presenting-the-preferences-window-on-macos-using-swiftui/) - Settings scene pattern
- [Create with Swift - Async Notification Authorization](https://www.createwithswift.com/notifications-tutorial-requesting-user-authorization-for-notifications-with-async-await/) - async/await pattern
- [mszpro - Privacy Manifest](https://mszpro.com/itms-91053-missing-api-declaration-for-accessing-userdefaults-timestamps-other-apis) - CA92.1 reason code

### Tertiary (LOW confidence)
- Web search results for Swift 6 notification delegate isolation - Pattern needs validation with actual Swift 6 compilation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Using only Apple frameworks (UserNotifications, Foundation, SwiftUI)
- Architecture: HIGH - Actor pattern proven in codebase; Settings scene is standard
- Pitfalls: MEDIUM - Swift 6 isolation issues reported but not personally verified
- Alert detection logic: MEDIUM - Requirements clear but threshold tuning needs user feedback

**Research date:** 2026-02-15
**Valid until:** 2026-03-15 (30 days - stable Apple frameworks)

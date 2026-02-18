# Phase 17: Widget Foundation - Research

**Researched:** 2026-02-17
**Domain:** macOS WidgetKit integration with App Groups shared data
**Confidence:** HIGH

## Summary

Phase 17 implements WidgetKit widgets for macOS displaying live ping status from the main app via shared UserDefaults. The technical domain is well-established with WidgetKit being mature since iOS 14 and macOS Big Sur. The core architecture follows a standard pattern: main app writes ping results to App Group shared container, widget extension reads cached data via TimelineProvider, system schedules updates within budget constraints (40-70 updates/24hr).

**Critical macOS Sequoia requirement:** App Group identifiers MUST use Team ID prefix format (`TEAMID.group.name`) instead of iOS-style `group.` prefix. This is a breaking change from previous macOS versions and will cause permission errors if not followed.

The project currently uses SPM + Xcode hybrid structure. Widget extensions MUST be added as Xcode targets (not SPM targets) because WidgetKit extensions require bundle ID hierarchy, entitlements, and info.plist configurations that SPM cannot provide.

**Primary recommendation:** Add WidgetKit extension as Xcode target, configure App Groups with Team ID prefix for macOS Sequoia, use shared UserDefaults suite for data transfer, implement StaticConfiguration with TimelineProvider, space timeline entries 5-15 minutes apart to respect system budget.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None - user has not locked any implementation decisions.

### Claude's Discretion

User has granted full design discretion for this phase. Research and planning agents should:

- **Visual presentation**: Choose appropriate layout density, color coding scheme, typography, and status indicators based on macOS WidgetKit design patterns and system conventions
- **Information hierarchy**: Determine what data shows in each widget size based on available space and importance (latency, packet loss, timestamp, host names)
- **Host selection logic**: Decide which hosts appear in medium widget (3 hosts) — priority based on status/importance/user configuration
- **Stale data handling**: Define visual treatment for stale data (>15min old) — dimming, graying, badge, or other indicator
- **Status color scheme**: Choose colors for good/warning/critical states — should follow macOS system colors and accessibility guidelines
- **Update timing**: Respect WidgetKit budget (40-70 updates/day) while balancing freshness
- **Dark mode support**: Ensure proper contrast and readability in both light and dark appearances

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

(Future widget enhancements documented in REQUIREMENTS.md Future section)

</user_constraints>

<phase_requirements>
## Phase Requirements

This phase must address all Widget Infrastructure (WI-*) and Widget UI (WUI-*) requirements.

| ID | Description | Research Support |
|----|-------------|-----------------|
| WI-01 | App Groups entitlement configured with correct Team ID prefix for macOS Sequoia | macOS Sequoia requires `TEAMID.group.name` format (not `group.` prefix) |
| WI-02 | Shared UserDefaults accessible from both main app and widget extension | `UserDefaults(suiteName: "TEAMID.group.identifier")` standard pattern |
| WI-03 | Widget Extension target created in Xcode with proper bundle ID and entitlements | Must be Xcode target (not SPM); bundle ID = `com.hadm.PingScope.widget` |
| WI-04 | WidgetDataStore service writes ping results to shared UserDefaults | JSONEncoder with shared suite, write after each ping cycle |
| WI-05 | WidgetCenter reloadTimelines() called after UserDefaults writes | `WidgetCenter.shared.reloadTimelines(ofKind:)` on data change |
| WI-06 | TimelineProvider reads cached ping data from shared UserDefaults | `getTimeline(in:completion:)` reads from shared suite |
| WI-07 | Timeline entries spaced 5+ minutes apart to respect system budget (40-70/day) | Budget = 40-70 updates/day; 5-15min spacing optimal |
| WUI-01 | Small widget displays single host status with color-coded indicator | `.systemSmall` family, single tap area |
| WUI-02 | Small widget shows current ping latency value | Display latency in ms from cached PingResult |
| WUI-03 | Medium widget displays multi-host summary (3 hosts horizontal) | `.systemMedium` family, horizontal layout |
| WUI-04 | Medium widget shows status indicators for each host | Color-coded status per host (green/yellow/red) |
| WUI-05 | Large widget displays all configured hosts in list format | `.systemLarge` family, vertical list |
| WUI-06 | Large widget shows statistics (packet loss, avg latency) per host | Aggregate statistics from cached results |
| WUI-07 | All widget sizes display last update timestamp | Include timestamp in TimelineEntry, display via Text |
| WUI-08 | Tapping any widget opens main app | `.widgetURL(_:)` modifier with deep link |
| WUI-09 | Widgets show stale data indicator when >15 minutes old | Visual treatment: reduce opacity to 0.6, add "⚠️ Stale" badge |
| WUI-10 | Widget views support both light and dark mode | Use system colors (Color.primary, Color.secondary), test both schemes |

</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WidgetKit | System (macOS 13+) | Widget framework | Apple's official and only widget API for macOS |
| SwiftUI | System (macOS 13+) | Widget UI | Required by WidgetKit, no UIKit alternative |
| Foundation | System | Data serialization, UserDefaults | Standard library for shared data |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| JSONEncoder/JSONDecoder | System | Encode PingResult/Host for sharing | When sharing complex Codable types |
| App Groups | macOS entitlement | Shared container access | Required for widget data sharing |
| WidgetCenter | System | Trigger widget reloads | After writing new data to shared storage |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Shared UserDefaults | Core Data with shared container | Core Data adds complexity; UserDefaults sufficient for small datasets |
| JSONEncoder | Property list encoder | JSON more debuggable, industry standard |
| WidgetKit | None | WidgetKit is the only widget API on macOS |

**Project Structure:**

Current: SPM-based with Xcode project wrapper
Required: Xcode target for widget extension (WidgetKit extensions cannot be SPM targets)

```
PingScope.xcodeproj/
├── PingScope (main app target)          # Existing
├── PingScopeWidget (extension target)   # NEW - must be Xcode target
└── Shared/                              # Existing Sources/ folder
    ├── Models/                          # Host, PingResult (already Codable)
    ├── Services/                        # PingService, HostStore
    └── Widget/                          # NEW - WidgetDataStore
```

## Architecture Patterns

### Recommended Project Structure

```
Sources/PingScope/
├── Widget/
│   ├── WidgetDataStore.swift       # Writes to shared UserDefaults
│   └── WidgetData.swift            # Simplified Codable model
└── ... (existing structure)

PingScopeWidget/                     # NEW Xcode target
├── PingScopeWidget.swift           # @main Widget
├── PingScopeWidgetProvider.swift   # TimelineProvider
├── PingScopeWidgetEntry.swift      # TimelineEntry
├── Views/
│   ├── SmallWidgetView.swift       # systemSmall
│   ├── MediumWidgetView.swift      # systemMedium
│   └── LargeWidgetView.swift       # systemLarge
└── Info.plist                      # Extension metadata
```

### Pattern 1: App Groups Configuration (macOS Sequoia)

**What:** Share data between main app and widget using App Group shared container
**When to use:** Required for widget data access
**Critical:** macOS Sequoia requires Team ID prefix

**Example entitlements (main app and widget):**
```xml
<!-- com.hadm.PingScope.entitlements and com.hadm.PingScope.widget.entitlements -->
<key>com.apple.security.application-groups</key>
<array>
    <string>TEAMID.group.com.hadm.PingScope</string>
</array>
```

**Access shared UserDefaults:**
```swift
// Source: Apple Developer Forums (macOS Sequoia requirement)
let shared = UserDefaults(suiteName: "TEAMID.group.com.hadm.PingScope")!
```

### Pattern 2: WidgetDataStore Service

**What:** Service that writes ping results to shared container
**When to use:** After each ping cycle in main app
**Example:**
```swift
// Source: Verified pattern from web search results
actor WidgetDataStore {
    private let shared: UserDefaults

    init(suiteName: String) {
        self.shared = UserDefaults(suiteName: suiteName)!
    }

    func savePingResults(_ results: [PingResult], hosts: [Host]) async {
        let data = WidgetData(
            results: results,
            hosts: hosts,
            lastUpdate: Date()
        )

        guard let encoded = try? JSONEncoder().encode(data) else { return }
        shared.set(encoded, forKey: "widgetData")

        // Trigger widget reload
        WidgetCenter.shared.reloadTimelines(ofKind: "PingScopeWidget")
    }
}
```

### Pattern 3: TimelineProvider Implementation

**What:** Provides timeline entries to WidgetKit
**When to use:** Required for all widgets
**Example:**
```swift
// Source: Official WidgetKit pattern
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let entry = WidgetEntry(date: Date(), data: loadData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let data = loadData()
        let entry = WidgetEntry(date: Date(), data: data)

        // Next update in 5-15 minutes (respects budget)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
    }

    private func loadData() -> WidgetData? {
        let shared = UserDefaults(suiteName: "TEAMID.group.com.hadm.PingScope")!
        guard let data = shared.data(forKey: "widgetData"),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return nil
        }
        return decoded
    }
}
```

### Pattern 4: Widget Configuration

**What:** Define widget with supported families and configuration
**When to use:** Main widget definition
**Example:**
```swift
// Source: Standard WidgetKit pattern
@main
struct PingScopeWidget: Widget {
    let kind: String = "PingScopeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PingScopeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("PingScope")
        .description("Monitor ping status")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

### Pattern 5: Widget Family Switching

**What:** Display different layouts per widget size
**When to use:** All widgets with multiple families
**Example:**
```swift
// Source: Common WidgetKit pattern
struct PingScopeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        @unknown default:
            EmptyView()
        }
    }
}
```

### Pattern 6: Deep Linking

**What:** Open app when tapping widget
**When to use:** All widgets
**Example:**
```swift
// Source: WidgetKit documentation
SmallWidgetView(entry: entry)
    .widgetURL(URL(string: "pingscope://open"))
```

Handle in AppDelegate:
```swift
func application(_ application: NSApplication, open urls: [URL]) {
    // Handle pingscope://open
}
```

### Pattern 7: Dark Mode Support

**What:** Support both light and dark appearance
**When to use:** All widget views
**Example:**
```swift
// Source: SwiftUI system colors best practice
VStack {
    Text("Ping: \(latency)ms")
        .foregroundColor(.primary)  // Auto-adapts

    Circle()
        .fill(statusColor)  // Use semantic colors
}
.containerBackground(for: .widget) {
    Color(nsColor: .controlBackgroundColor)
}

var statusColor: Color {
    // Use system colors for accessibility
    switch status {
    case .good: return Color.green
    case .warning: return Color.yellow
    case .critical: return Color.red
    }
}
```

### Pattern 8: Stale Data Indicator

**What:** Visually indicate when data is >15 minutes old
**When to use:** All widget sizes
**Recommendation:** Reduce opacity and add warning badge
**Example:**
```swift
var isStale: Bool {
    Date().timeIntervalSince(entry.data.lastUpdate) > 15 * 60
}

VStack {
    content
        .opacity(isStale ? 0.6 : 1.0)

    if isStale {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Stale")
                .font(.caption2)
        }
    }
}
```

### Anti-Patterns to Avoid

- **Frequent timeline reloads:** Don't call `reloadTimelines()` more often than data actually changes (triggers budget limits)
- **Network calls in widget:** Widgets run in constrained environment; always use cached data
- **UIKit in widgets:** WidgetKit only supports SwiftUI (no `UIViewRepresentable`)
- **Keychain access:** Widgets cannot access Keychain reliably (errSecInteractionNotAllowed)
- **Complex animations:** Widgets don't support animations; keep UI static
- **<5 minute timeline spacing:** System enforces 5-minute minimum between timeline entries
- **iOS-style App Group ID on macOS Sequoia:** Must use `TEAMID.group.name` format

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Widget update scheduling | Custom timer/refresh logic | TimelineProvider + Timeline policy | System manages battery/performance; custom timers killed |
| Data serialization | Custom binary format | JSONEncoder/Decoder with Codable | Type-safe, debuggable, standard |
| Shared storage | File-based coordination | App Groups + UserDefaults | System-managed permissions, atomic writes |
| Widget previews | Manual screenshot workflow | Xcode preview with #Preview macro | Live previews in Xcode canvas |
| Dark mode switching | Manual color management | System Color + @Environment(\.colorScheme) | Automatic, accessibility-compliant |
| Widget reload triggers | Polling/observation | WidgetCenter.shared.reloadTimelines() | System-optimized, budget-aware |

**Key insight:** WidgetKit is highly opinionated and system-controlled. Fighting the framework (custom timers, network calls, complex state) leads to battery drain, crashes, or widgets that stop updating. The correct approach is "write data to shared container, let system handle scheduling."

## Common Pitfalls

### Pitfall 1: App Group ID Format on macOS Sequoia

**What goes wrong:** Widget fails to launch with permission errors or data not shared between app and widget
**Why it happens:** macOS Sequoia changed App Group ID requirements from `group.` prefix to Team ID prefix
**How to avoid:**
- Use format `TEAMID.group.com.hadm.PingScope` where TEAMID is your Apple Developer Team ID
- Apply to BOTH main app and widget extension entitlements
- Verify in Xcode Signing & Capabilities that group appears correctly
**Warning signs:**
- Widget shows "Unable to load" or crashes immediately
- Console.app shows "App Group access REJECTED" errors
- Main app writes data but widget shows placeholder/no data

**Source:** [Apple Developer Forums - macOS Sequoia App Groups](https://developer.apple.com/forums/thread/758358)

### Pitfall 2: Widget Timeline Budget Exhaustion

**What goes wrong:** Widget stops updating after working initially
**Why it happens:** System limits widgets to 40-70 updates per 24-hour period; excessive reloadTimelines() calls exhaust budget
**How to avoid:**
- Call `reloadTimelines()` only when data actually changes
- Space timeline entries 5-15 minutes apart (not every minute)
- Use `.after(date)` or `.atEnd` timeline policy, not `.never` with constant reloads
- Test on physical device (simulator doesn't enforce budget)
**Warning signs:**
- Widget updates fine in Xcode debugger but freezes on device
- Console.app shows "widget budget exceeded" warnings
- Widget works for first hour then stops updating

**Source:** [Keeping a widget up to date - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

### Pitfall 3: Bundle ID Hierarchy Mismatch

**What goes wrong:** Widget extension fails to install or crashes on launch
**Why it happens:** Widget bundle ID must be child of main app bundle ID
**How to avoid:**
- Main app: `com.hadm.PingScope`
- Widget: `com.hadm.PingScope.widget` (append suffix to parent ID)
- Never use different base domains
- Verify in Xcode target settings
**Warning signs:**
- "Unable to install bundle" error
- Widget appears in widget gallery but crashes when added
- Code signing errors mentioning bundle identifier

**Source:** [WidgetKit bundle ID naming convention](https://developer.apple.com/forums/thread/739235)

### Pitfall 4: Widget UI Limitations

**What goes wrong:** Runtime crashes or widgets showing blank/frozen content
**Why it happens:** WidgetKit doesn't support UIViewRepresentable, Keychain access, or animations
**How to avoid:**
- Use only pure SwiftUI views (no UIKit bridges)
- Never access Keychain in widget code (use shared UserDefaults instead)
- Avoid .animation() modifiers and animated transitions
- Don't use network calls (cache all data in shared container)
- Test extensively on device (simulator hides some limitations)
**Warning signs:**
- Widget works in preview but crashes on device
- `errSecInteractionNotAllowed` errors in Console.app
- Widget shows empty view or frozen content

**Source:** [WidgetKit pitfalls - Medium](https://medium.com/techpro-studio/widgetkit-some-pitfalls-i-found-55a404b2d8df)

### Pitfall 5: Timeline Not Updating After .atEnd or .after(date)

**What goes wrong:** Widget timeline policy set to .atEnd or .after(date) but widget never requests new timeline
**Why it happens:** System-controlled refresh is unreliable; policies don't always trigger when expected
**How to avoid:**
- Always call `WidgetCenter.shared.reloadTimelines(ofKind:)` from main app when data changes
- Don't rely solely on timeline policy for updates
- Use `.after(date)` with reasonable intervals (10-15 minutes)
- Consider hybrid: policy for baseline + manual reload on data change
**Warning signs:**
- Timeline entries expire but getTimeline() not called
- Widget shows stale data despite policy being .atEnd
- Removing and re-adding widget forces update

**Source:** [WidgetKit Timeline Updates - Apple Developer Forums](https://developer.apple.com/forums/thread/653265)

### Pitfall 6: Codable Type Changes Breaking Shared Data

**What goes wrong:** Widget shows no data after app update
**Why it happens:** Changing Codable struct fields breaks decoding of previously saved data
**How to avoid:**
- Version your shared data model
- Add CodingKeys and custom init(from:) to handle migration
- Clear shared UserDefaults on app update if necessary
- Test upgrade path from previous version
**Warning signs:**
- Widget works on fresh install but breaks on upgrade
- JSONDecoder throwing errors in Console.app
- Widget shows placeholder after app update

**Prevention pattern:**
```swift
struct WidgetData: Codable {
    let version: Int = 1  // Add versioning
    let results: [PingResult]
    let hosts: [Host]
    let lastUpdate: Date

    // Custom decoder handles version migration
}
```

### Pitfall 7: Shared UserDefaults Not Synchronizing

**What goes wrong:** Main app writes data but widget doesn't see updates
**Why it happens:** UserDefaults not explicitly synchronized or suite name mismatch
**How to avoid:**
- Use exact same suiteName in app and widget
- Call `shared.synchronize()` after writes (though usually not required)
- Verify App Group entitlement enabled in BOTH targets
- Check spelling/capitalization of suite name
**Warning signs:**
- App writes data, widget shows placeholder
- `shared.data(forKey:)` returns nil in widget
- Data appears in app's UserDefaults but not shared container

**Debug check:**
```bash
# Check actual UserDefaults location
po UserDefaults(suiteName: "TEAMID.group.com.hadm.PingScope")?.dictionaryRepresentation()
```

## Code Examples

Verified patterns from research and documentation:

### Complete TimelineEntry Definition

```swift
// Source: Standard WidgetKit pattern
struct WidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?

    // Optional: Smart Stack relevance
    var relevance: TimelineEntryRelevance? {
        guard let data = data else { return nil }

        // Higher score for unhealthy hosts
        let hasIssues = data.results.contains { !$0.isSuccess }
        return TimelineEntryRelevance(
            score: hasIssues ? 100 : 50,
            duration: 15 * 60  // 15 minutes
        )
    }
}
```

### WidgetData Shared Model

```swift
// Source: Codable best practices for widget sharing
struct WidgetData: Codable, Equatable {
    let version: Int = 1
    let results: [PingResult]
    let hosts: [Host]
    let lastUpdate: Date

    static let placeholder = WidgetData(
        results: [],
        hosts: [],
        lastUpdate: Date()
    )

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 15 * 60
    }
}
```

### Small Widget View (Single Host)

```swift
// Source: WidgetKit single-tap area pattern
struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = entry.data,
               let host = data.hosts.first,
               let result = data.results.first {

                HStack {
                    Circle()
                        .fill(statusColor(for: result))
                        .frame(width: 12, height: 12)

                    Text(host.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let latency = result.latency {
                    Text("\(formatLatency(latency))")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                } else {
                    Text("Timeout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("No Data")
                    .foregroundColor(.secondary)
            }
        }
        .opacity(entry.data?.isStale == true ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            Color(nsColor: .controlBackgroundColor)
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    private func statusColor(for result: PingResult) -> Color {
        if !result.isSuccess { return .red }
        guard let latency = result.latency else { return .gray }

        let ms = Double(latency.components.seconds) * 1000
        if ms < 50 { return .green }
        if ms < 100 { return .yellow }
        return .red
    }

    private func formatLatency(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1000 +
                 Double(duration.components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f ms", ms)
    }
}
```

### Medium Widget View (3 Hosts)

```swift
// Source: WidgetKit medium family pattern
struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.data {
                ForEach(Array(zip(data.hosts.prefix(3), data.results.prefix(3))), id: \.0.id) { host, result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(for: result))
                                .frame(width: 8, height: 8)

                            Text(host.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }

                        if let latency = result.latency {
                            Text(formatLatency(latency))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Timeout")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .opacity(entry.data?.isStale == true ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            Color(nsColor: .controlBackgroundColor)
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    // Same helper methods as SmallWidgetView
}
```

### Large Widget View (All Hosts)

```swift
// Source: WidgetKit large family pattern
struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PingScope")
                    .font(.headline)

                Spacer()

                if let data = entry.data {
                    Text(data.lastUpdate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            if let data = entry.data {
                ForEach(Array(zip(data.hosts, data.results)), id: \.0.id) { host, result in
                    HStack {
                        Circle()
                            .fill(statusColor(for: result))
                            .frame(width: 10, height: 10)

                        Text(host.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        if let latency = result.latency {
                            Text(formatLatency(latency))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Timeout")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Spacer()
        }
        .opacity(entry.data?.isStale == true ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            Color(nsColor: .controlBackgroundColor)
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    // Same helper methods
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `group.` prefix for App Groups | Team ID prefix on macOS | macOS Sequoia (2024) | Breaking change; old format causes permission errors |
| Manual widget refresh | System-managed budget | iOS 14/macOS 11 (2020) | Widgets stop updating if budget exceeded |
| `.background()` modifier | `.containerBackground(for:)` | iOS 17/macOS 14 (2023) | Required for proper widget appearance |
| IntentConfiguration | StaticConfiguration or AppIntentConfiguration | iOS 16+ | StaticConfiguration simpler for non-configurable widgets |

**Deprecated/outdated:**
- **iOS-style App Groups on macOS Sequoia:** `group.identifier` no longer works; must use `TEAMID.group.identifier`
- **UIKit in widgets:** Never supported, but developers often tried; WidgetKit is SwiftUI-only
- **Continuous widget updates:** Early WidgetKit didn't have clear budget limits; now strictly enforced at 40-70/day

## Design Recommendations

Based on research of macOS monitoring widgets and system conventions:

### Status Color Scheme

Use macOS system semantic colors for consistency and accessibility:

- **Good/Healthy:** `Color.green` (latency <50ms)
- **Warning:** `Color.yellow` (latency 50-100ms)
- **Critical/Error:** `Color.red` (latency >100ms or timeout)
- **Unknown/Stale:** `Color.secondary` with 60% opacity

### Information Hierarchy

**Small widget (systemSmall):**
- Primary: Single host name + status indicator
- Secondary: Current latency value
- Tertiary: Last update timestamp (relative)

**Medium widget (systemMedium):**
- Show 3 hosts horizontally
- Host selection priority: (1) Unhealthy hosts first, (2) Default hosts, (3) User-added hosts by order
- Each host shows: name, status dot, latency value

**Large widget (systemLarge):**
- All configured hosts in vertical list
- Include statistics: packet loss %, avg latency
- Header with app name and last update
- Scrolling not supported; truncate to fit

### Stale Data Handling

Recommended visual treatment when data >15 minutes old:
- Reduce entire widget opacity to 0.6
- Add orange warning badge in corner
- Keep data visible (don't replace with "No Data")

### Update Timing

Balance freshness vs. system budget:
- Timeline entry spacing: 10 minutes (fits 144 entries/day, well within 40-70 budget)
- Manual reload: Call `WidgetCenter.shared.reloadTimelines()` after each ping cycle completes
- Policy: `.after(date)` with next update 10 minutes from now
- System will coalesce if app triggers too frequently

### Typography

- Widget title: `.headline`
- Host names: `.subheadline` (large) or `.caption` (medium)
- Latency values: `.system(.title2, design: .rounded)` with bold weight
- Timestamps: `.caption2` in secondary color

## Open Questions

1. **Team ID Discovery**
   - What we know: Team ID is in Apple Developer account, also in project settings
   - What's unclear: Exact Xcode path to find it programmatically
   - Recommendation: Document lookup path in plan (Xcode > Project > Signing & Capabilities shows Team ID)

2. **Existing Host/PingResult Codable Compatibility**
   - What we know: Host and PingResult are already Codable in codebase
   - What's unclear: Whether they encode cleanly for widget sharing or need simplified WidgetData wrapper
   - Recommendation: Test encoding existing models; if issues, create WidgetData wrapper with subset of fields

3. **Deep Link URL Scheme Registration**
   - What we know: Need `pingscope://` URL scheme, handle in AppDelegate
   - What's unclear: Whether this requires Info.plist changes or just implementation
   - Recommendation: Add CFBundleURLTypes to Info.plist for URL scheme registration

4. **Packet Loss Calculation**
   - What we know: Large widget should show packet loss %
   - What's unclear: Whether main app currently tracks packet loss over time
   - Recommendation: Review PingService/HostHealthTracker for existing stats; if not present, defer to future enhancement

## Sources

### Primary (HIGH confidence)

- [WidgetKit - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit) - Framework overview
- [Keeping a widget up to date - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) - Update budget (40-70/day)
- [TimelineProvider - Apple Developer Documentation](https://developer.apple.com/documentation/widgetkit/timelineprovider) - Core protocol
- [Sequoia Group Container for Mac - Apple Developer Forums](https://developer.apple.com/forums/thread/758358) - Team ID prefix requirement
- [macOS Widgets won't launch with app group set - Apple Developer Forums](https://developer.apple.com/forums/thread/758478) - macOS Sequoia breaking change
- [App Groups Entitlement - Apple Developer Documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups) - Official entitlement spec

### Secondary (MEDIUM confidence)

- [Sharing UserDefaults with widgets - Apple Developer Forums](https://developer.apple.com/forums/thread/651799) - Shared UserDefaults pattern
- [Accessing UserDefaults in Widgets - SwiftLogic.io](https://swiftlogic.io/posts/accessing-userdefaults-in-widgets/) - Implementation guide
- [WidgetKit bundle ID naming - Apple Developer Forums](https://developer.apple.com/forums/thread/739235) - Bundle ID hierarchy
- [Understanding Container Background for Widget - Swift Senpai](https://swiftsenpai.com/development/widget-container-background/) - iOS 17+ pattern
- [How to Update or Refresh a Widget - Swift Senpai](https://swiftsenpai.com/development/refreshing-widget/) - Reload patterns
- [WidgetKit pitfalls - Medium](https://medium.com/techpro-studio/widgetkit-some-pitfalls-i-found-55a404b2d8df) - Common mistakes

### Tertiary (LOW confidence - for awareness)

- [MONIT Widget](https://mmonit.com/widget/) - macOS monitoring widget example
- [iStatistica](https://www.imagetasks.com/istatistica/) - System monitor widget patterns
- [Fanny Widget](https://www.fannywidget.com/) - Notification Center widget example

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - WidgetKit is the only option, well-documented by Apple
- Architecture: HIGH - Patterns verified from official docs and multiple community sources
- Pitfalls: HIGH - Sourced from Apple Developer Forums and recent macOS Sequoia issues
- Design recommendations: MEDIUM - Based on existing app examples and HIG guidelines, but with Claude discretion

**Research date:** 2026-02-17
**Valid until:** 2026-03-17 (30 days - WidgetKit is stable, but macOS system requirements may change)

**Critical dependency:** Team ID from Apple Developer account required before implementation can begin.

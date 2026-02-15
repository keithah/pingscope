# PingMonitor Widget Extension

**File:** `PingMonitorWidget/PingMonitorWidget.swift`

## Overview

The PingMonitor widget extension displays real-time ping status on the macOS desktop using WidgetKit. It supports three widget sizes and reads data from a shared App Group container.

## App Group Data Sharing

The main app writes ping data to a shared container that the widget reads:

**App Group ID:** `group.com.hadm.pingmonitor.shared`

**Data File:** `pingdata.json`

**Data Format:**
```json
[
  {
    "hostName": "Google",
    "address": "8.8.8.8",
    "pingTime": 12.3,
    "status": "good"
  },
  {
    "hostName": "Cloudflare",
    "address": "1.1.1.1",
    "pingTime": 8.7,
    "status": "good"
  },
  {
    "hostName": "Gateway",
    "address": "192.168.1.1",
    "pingTime": 2.1,
    "status": "good"
  }
]
```

---

## Widget Data Models

### PingEntry

Timeline entry for WidgetKit:

```swift
struct PingEntry: TimelineEntry {
    let date: Date
    let pingResults: [PingWidgetData]
}
```

### PingWidgetData

Widget-specific host data:

```swift
struct PingWidgetData {
    let hostName: String
    let address: String
    let pingTime: Double?
    let status: PingWidgetStatus
}
```

### PingWidgetStatus

Widget-specific status enum:

```swift
enum PingWidgetStatus {
    case good, warning, error, timeout

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .error: return .red
        case .timeout: return .gray
        }
    }

    var description: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Slow"
        case .error: return "Error"
        case .timeout: return "Timeout"
        }
    }

    static func fromString(_ string: String) -> PingWidgetStatus {
        switch string.lowercased() {
        case "good": return .good
        case "warning": return .warning
        case "error": return .error
        default: return .timeout
        }
    }
}
```

---

## Timeline Provider

```swift
struct PingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PingEntry {
        // Static placeholder data for widget gallery
        PingEntry(date: Date(), pingResults: [
            PingWidgetData(hostName: "Google", address: "8.8.8.8", pingTime: 12.3, status: .good),
            PingWidgetData(hostName: "Cloudflare", address: "1.1.1.1", pingTime: 8.7, status: .good),
            PingWidgetData(hostName: "Gateway", address: "192.168.1.1", pingTime: 2.1, status: .good)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (PingEntry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let pingData = loadPingData()
        let entry = PingEntry(date: Date(), pingResults: pingData)

        // Refresh every 5 seconds
        let nextUpdateDate = Calendar.current.date(byAdding: .second, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))

        completion(timeline)
    }

    private func loadPingData() -> [PingWidgetData] {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.hadm.pingmonitor.shared"
        ) else {
            return defaultPingData()
        }

        let fileURL = sharedURL.appendingPathComponent("pingdata.json")

        guard let data = try? Data(contentsOf: fileURL),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return defaultPingData()
        }

        return jsonArray.compactMap { dict in
            guard let hostName = dict["hostName"] as? String,
                  let address = dict["address"] as? String else { return nil }

            let pingTime = dict["pingTime"] as? Double
            let statusString = dict["status"] as? String ?? "timeout"
            let status = PingWidgetStatus.fromString(statusString)

            return PingWidgetData(hostName: hostName, address: address,
                                  pingTime: pingTime, status: status)
        }
    }

    private func defaultPingData() -> [PingWidgetData] {
        // Fallback when no data available
        return [
            PingWidgetData(hostName: "Google", address: "8.8.8.8", pingTime: nil, status: .timeout),
            PingWidgetData(hostName: "Cloudflare", address: "1.1.1.1", pingTime: nil, status: .timeout),
            PingWidgetData(hostName: "Gateway", address: "192.168.1.1", pingTime: nil, status: .timeout)
        ]
    }
}
```

---

## Widget Sizes

### Small Widget (Single Host)

Displays the first/primary host only:

```swift
struct SmallWidgetView: View {
    let entry: PingEntry

    var primaryHost: PingWidgetData {
        entry.pingResults.first ?? PingWidgetData(hostName: "Offline", address: "",
                                                   pingTime: nil, status: .timeout)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Status indicator (16x16 circle)
            Circle()
                .fill(primaryHost.status.color)
                .frame(width: 16, height: 16)

            // Host name
            Text(primaryHost.hostName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            // Address
            Text(primaryHost.address)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)

            // Ping time or status
            Text(pingTimeText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(primaryHost.status.color)

            // Last update time
            Text("Updated \(entry.date, style: .time)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
```

### Medium Widget (3 Hosts Horizontal)

Displays up to 3 hosts side by side:

```swift
struct MediumWidgetView: View {
    let entry: PingEntry

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(entry.pingResults.prefix(3).enumerated()), id: \.offset) { index, host in
                VStack(spacing: 3) {
                    // Status indicator (12x12)
                    Circle()
                        .fill(host.status.color)
                        .frame(width: 12, height: 12)

                    // Short host name ("GGL", "CF", "GW")
                    Text(shortHostName(host.hostName))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))

                    // Ping time
                    Text(pingTimeText(host))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(host.status.color)
                }
                .frame(maxWidth: .infinity)

                if index < min(entry.pingResults.count, 3) - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func shortHostName(_ name: String) -> String {
        switch name {
        case "Google": return "GGL"
        case "Cloudflare": return "CF"
        case "Default Gateway", "Gateway": return "GW"
        default: return String(name.prefix(3)).uppercased()
        }
    }
}
```

### Large Widget (Detailed List)

Full table with all hosts:

```swift
struct LargeWidgetView: View {
    let entry: PingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("PING MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Host list
            ForEach(Array(entry.pingResults.enumerated()), id: \.offset) { index, host in
                HStack(spacing: 8) {
                    // Status indicator (8x8)
                    Circle()
                        .fill(host.status.color)
                        .frame(width: 8, height: 8)

                    // Host info
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.hostName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text(host.address)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Ping time (40px right-aligned)
                    Text(pingTimeText(host))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(host.status.color)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 2)

                if index < entry.pingResults.count - 1 {
                    Divider()
                }
            }

            Spacer()
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
```

---

## Widget Configuration

```swift
struct PingMonitorWidget: Widget {
    let kind: String = "PingMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PingProvider()) { entry in
            PingMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ping Monitor")
        .description("Monitor network latency to key hosts")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

---

## Widget Bundle Entry Point

```swift
@main
struct PingMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        PingMonitorWidget()
    }
}
```

---

## Key Considerations

1. **Refresh Rate:** Widgets refresh every 5 seconds via `.after(nextUpdateDate)` policy.

2. **Data Freshness:** Widget reads from shared container file, which the main app updates on every ping result.

3. **Fallback Data:** If shared data unavailable, widget shows timeout status for all hosts.

4. **Background Styling:** Uses `.containerBackground(.fill.tertiary, for: .widget)` for system-appropriate appearance.

5. **Monospace Font:** All text uses `.monospaced` design for consistent alignment.

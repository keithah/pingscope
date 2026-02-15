# PingMonitor Views

## View Hierarchy

```
MenuBarController (AppKit)
    ├── NSPopover
    │   └── ContentView (SwiftUI)
    │       ├── Full View Mode
    │       │   ├── hostTabsSection
    │       │   ├── graphSection → GraphView
    │       │   ├── historySection → HistoryRow
    │       │   └── statisticsSection
    │       └── Compact View Mode
    │           └── CompactView
    │               ├── CompactGraphView
    │               └── CompactHistoryRow
    └── NSWindow (floating, when stay-on-top)
        └── Same view hierarchy
```

---

## MenuBarController

**File:** `Views/MenuBar/MenuBarController.swift`

NSStatusItem management and window coordination.

### Status Item Setup

```swift
private func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: Constants.MenuBar.statusItemWidth)

    guard let button = statusItem.button else { return }
    button.action = #selector(handleClick)
    button.sendAction(on: [.leftMouseUp, .rightMouseUp]
    button.target = self
    button.toolTip = "PingMonitor"

    // Popover setup
    popover.contentSize = NSSize(width: 450, height: 500)
    popover.behavior = .transient
    popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))
}
```

### Status Image Rendering

```swift
private func createStatusImage(color: NSColor, pingText: String) -> NSImage {
    let size = NSSize(width: 40, height: 22)
    let image = NSImage(size: size)

    image.lockFocus()

    // Draw status dot (8x8 circle) at top center
    color.setFill()
    let dotRect = NSRect(x: (40 - 8) / 2, y: 13, width: 8, height: 8)
    let dotPath = NSBezierPath(ovalIn: dotRect)
    dotPath.fill()

    // Draw ping text below dot
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
        .foregroundColor: NSColor.labelColor
    ]
    pingText.draw(in: textRect, withAttributes: textAttributes)

    image.unlockFocus()
    return image
}
```

### Click Handling

```swift
@objc private func handleClick() {
    guard let event = NSApp.currentEvent else { return }

    if event.type == .rightMouseUp ||
        event.modifierFlags.contains(.control) ||
        event.modifierFlags.contains(.command) {
        showContextMenu()
    } else {
        togglePopover()
    }
}
```

### Floating Window Mode

When "Stay on Top" is enabled:

```swift
private func createFloatingWindow(compact: Bool) {
    let size = compact ?
        NSSize(width: 280, height: 220) :
        NSSize(width: 450, height: 500)

    floatingWindow = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    // Configure floating behavior
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces]
    window.isMovableByWindowBackground = true

    // Position near status item
    let buttonFrame = buttonWindow.convertToScreen(button.frame)
    window.setFrameOrigin(NSPoint(
        x: buttonFrame.midX - size.width / 2,
        y: buttonFrame.minY - size.height - 20
    ))
}
```

### Context Menu

```swift
private func showContextMenu() {
    let menu = NSMenu()

    // Host selection submenu
    let hostMenu = NSMenu()
    for (index, host) in viewModel.hosts.enumerated() {
        let item = NSMenuItem(title: "\(host.name) (\(host.address))", ...)
        item.state = host.isActive ? .on : .off
        hostMenu.addItem(item)
    }

    // Mode toggles
    menu.addItem(NSMenuItem(title: "Compact Mode", ...))  // Checkmark if enabled
    menu.addItem(NSMenuItem(title: "Stay on Top", ...))   // Checkmark if enabled

    // Settings and Quit
    menu.addItem(NSMenuItem(title: "Settings", ...))
    menu.addItem(NSMenuItem(title: "Quit", ...))

    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
}
```

---

## ContentView

**File:** `Views/Main/ContentView.swift`

Main full-size view with conditional sections.

### State

```swift
@ObservedObject var viewModel: PingViewModel
@State private var selectedHostIndex = 0
@State private var showingSettings = false
@State private var showingExport = false
@State private var selectedTimeFilter: TimeFilter = .fiveMinutes
```

### View Body

```swift
var body: some View {
    if viewModel.isCompactMode {
        CompactView(viewModel: viewModel, showingSettings: $showingSettings)
    } else {
        fullView
    }
}

private var fullView: some View {
    VStack(spacing: 0) {
        if viewModel.showHosts { hostTabsSection }
        if viewModel.showGraph { graphSection }
        if viewModel.showHistory { historySection }
    }
    .frame(width: 450, height: calculateDynamicHeight())
}
```

### Host Tabs Section

Horizontal scrolling host selector:

```swift
private var hostTabsSection: some View {
    VStack(spacing: 0) {
        Text("Monitored Hosts").font(.headline)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.hosts.enumerated()) { index, host in
                    hostTab(for: host, index: index)
                }
                settingsMenu  // Gear icon menu
            }
        }
    }
}

private func hostTab(for host: Host, index: Int) -> some View {
    Button(action: { selectedHostIndex = index; viewModel.selectHost(at: index) }) {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.getHostStatusColor(host: host))
                .frame(width: 10, height: 10)
            Text(host.name)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selectedHostIndex == index ? Color.accentColor : Color(NSColor.controlColor)))
    }
}
```

### Graph Section

```swift
private var graphSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            VStack(alignment: .leading) {
                Text("Ping History").font(.headline)
                Text("Real-time network latency").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            timeFilterMenu  // "Last 5 min" dropdown
        }

        GraphView(history: filteredHistory)
            .frame(height: 140)
    }
}
```

### History Section

```swift
private var historySection: some View {
    VStack(alignment: .leading, spacing: 8) {
        // Header with title and buttons
        HStack {
            Text("Recent Results").font(.headline)
            Spacer()
            Button(action: { viewModel.showHistorySummary.toggle() }) {
                Image(systemName: "info.circle")
            }
            Button(action: { showingExport = true }) {
                Image(systemName: "square.and.arrow.up")
            }
        }

        // Column headers
        historyHeader  // TIME | HOST | PING | STATUS

        // Scrollable results
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredHistory) { result in
                    HistoryRow(result: result)
                }
            }
        }
        .frame(height: 160)

        // Optional statistics
        if viewModel.showHistorySummary {
            statisticsSection
        }
    }
}
```

### Statistics Section

```swift
private var statisticsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
        let stats = filteredHistory.statistics

        Text("--- \(currentHost?.address ?? "unknown") ping statistics ---")
            .font(.system(size: 11, design: .monospaced))

        Text(stats.summaryText)  // "10 transmitted, 9 received, 10.0% packet loss"

        Text(stats.rttText)  // "RTT min/avg/max/stddev = ..."
    }
    .padding(12)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
}
```

---

## CompactView

**File:** `Views/Main/CompactView.swift`

Compact display mode (280x220).

### Layout

```swift
var body: some View {
    VStack(spacing: 0) {
        // Host picker + control buttons
        if viewModel.showHosts {
            controlsWithHostPicker
        } else {
            controlsOnly
        }

        // Mini graph
        if viewModel.showGraph {
            compactGraphSection
        }

        // Recent results (6 max)
        if viewModel.showHistory {
            compactHistorySection
        }
    }
    .frame(width: 280, height: calculateCompactHeight())
}
```

### Compact Controls

```swift
private var controlsWithHostPicker: some View {
    HStack {
        Picker("", selection: $selectedHostIndex) {
            ForEach(viewModel.hosts.enumerated()) { index, host in
                Text(host.name).tag(index)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .frame(width: 130)

        Spacer()

        controlButtons  // Settings gear + expand button
    }
}
```

---

## CompactGraphView

**File:** `Views/Main/CompactView.swift` (embedded)

Simplified sparkline graph for compact mode.

```swift
struct CompactGraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)

                if !history.isEmpty {
                    gridLines(in: geometry.size)
                    dataLine(in: geometry.size, maxY: maxY)
                    dataPoints(in: geometry.size, maxY: maxY)
                }
            }
        }
    }

    private func dataLine(in size: CGSize, maxY: Double) -> some View {
        Path { path in
            for (index, result) in history.enumerated() {
                guard let pingTime = result.pingTime else { continue }

                let x = size.width * (1.0 - CGFloat(index) / CGFloat(max(history.count - 1, 1)))
                let y = size.height * (1.0 - CGFloat(pingTime) / CGFloat(maxY))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Color.blue, lineWidth: 1.5)
    }
}
```

---

## GraphView

**File:** `Views/Main/GraphView.swift`

Full ping history graph with gradient fill.

### Structure

```swift
struct GraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with rounded corners and border
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1))

                gridLines(in: geometry.size)

                if !history.isEmpty {
                    dataVisualization(in: geometry.size)
                } else {
                    emptyState
                }

                yAxisLabels(in: geometry.size)
            }
        }
    }
}
```

### Grid Lines

```swift
private func gridLines(in size: CGSize) -> some View {
    Path { path in
        let padding: CGFloat = 30
        let graphWidth = size.width - padding
        let graphHeight = size.height - 20

        // 4 horizontal lines
        for i in 0...4 {
            let y = 10 + graphHeight * CGFloat(i) / 4
            path.move(to: CGPoint(x: padding, y: y))
            path.addLine(to: CGPoint(x: size.width - 10, y: y))
        }

        // 5 vertical lines
        for i in 0...5 {
            let x = padding + graphWidth * CGFloat(i) / 5
            path.move(to: CGPoint(x: x, y: 10))
            path.addLine(to: CGPoint(x: x, y: 10 + graphHeight))
        }
    }
    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
}
```

### Data Visualization

```swift
private func dataVisualization(in size: CGSize) -> some View {
    let validData = history.compactMap { result -> (index: Int, ping: Double)? in
        guard let pingTime = result.pingTime else { return nil }
        return (history.firstIndex(where: { $0.id == result.id }) ?? 0, pingTime)
    }

    return Group {
        if !validData.isEmpty {
            fillPath(...)      // Gradient fill under curve
            linePath(...)      // Blue line
            dataPoints(...)    // Circle points
        }
    }
}
```

### Fill Path (Gradient Under Curve)

```swift
private func fillPath(...) -> some View {
    Path { path in
        // Build closed path from data points
        path.move(to: CGPoint(x: firstPoint.x, y: baseline))
        path.addLine(to: firstPoint)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: lastPoint.x, y: baseline))
        path.closeSubpath()
    }
    .fill(LinearGradient(
        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
        startPoint: .top,
        endPoint: .bottom
    ))
}
```

---

## HistoryRow

**File:** `Views/Main/HistoryView.swift`

Single row in the history list.

```swift
struct HistoryRow: View {
    let result: PingResult

    var body: some View {
        HStack(spacing: 0) {
            // Time column (60px)
            Text(result.formattedTimestamp)
                .font(.system(size: 11, weight: .regular))
                .frame(width: 60, alignment: .leading)

            // Host column (100px)
            Text(result.host)
                .font(.system(size: 11, weight: .regular))
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            // Ping time column (60px)
            if let pingTime = result.pingTime {
                Text(String(format: "%.1f ms", pingTime))
                    .foregroundColor(result.status.swiftUIColor)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("--")
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

            // Status column (60px)
            HStack(spacing: 4) {
                Circle()
                    .fill(result.status.swiftUIColor)
                    .frame(width: 6, height: 6)
                Text(result.status.description)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(result.status.swiftUIColor)
            }
            .frame(width: 60, alignment: .center)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }
}
```

---

## CompactHistoryRow

**File:** `Views/Main/CompactView.swift` (embedded)

Abbreviated history row for compact mode.

```swift
struct CompactHistoryRow: View {
    let result: PingResult

    var body: some View {
        HStack(spacing: 8) {
            // Time (50px)
            Text(result.timestamp, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 50, alignment: .leading)

            // Short host name (60px)
            Text(shortHostName)  // "Google" → "GGL", etc.
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            Spacer()

            // Status dot + ping time
            HStack(spacing: 4) {
                Circle()
                    .fill(result.status.swiftUIColor)
                    .frame(width: 6, height: 6)
                Text(result.formattedPingTime)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private var shortHostName: String {
        if result.host.contains("8.8.8.8") { return "Google" }
        if result.host.contains("1.1.1.1") { return "Cloudflare" }
        if result.host.hasPrefix("192.168") { return "Gateway" }
        return String(result.host.prefix(8))
    }
}
```

---

## Dynamic Height Calculation

### Full View

```swift
private func calculateDynamicHeight() -> CGFloat {
    var height: CGFloat = 60  // Base padding

    if viewModel.showHosts { height += 120 }
    if viewModel.showGraph { height += 170 }
    if viewModel.showHistory {
        height += 200
        if viewModel.showHistorySummary { height += 120 }
    }

    return height
}
```

### Compact View

```swift
private func calculateCompactHeight() -> CGFloat {
    var height: CGFloat = 40  // Base

    if viewModel.showHosts { height += 40 }
    if viewModel.showGraph { height += 80 }
    if viewModel.showHistory { height += 100 }

    return height
}
```

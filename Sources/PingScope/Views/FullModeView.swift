import AppKit
import SwiftUI

struct FullModeView: View {
    @ObservedObject var viewModel: DisplayViewModel
    @State private var showingStats: Bool = false
    @State private var showCopiedFeedback: Bool = false
    var onToggleCompact: (() -> Void)?
    var onToggleStayOnTop: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var isCompactEnabled: Bool = false
    var isStayOnTopEnabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hostPills
            graphSection
            historySection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.setDisplayMode(.full)
        }
    }

    private var hostPills: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Monitored Hosts")
                    .font(.headline)

                Spacer()

                // Switch to compact
                Button {
                    onToggleCompact?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Switch to Compact")

                settingsMenu
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.hosts) { host in
                        let isSelected = viewModel.selectedHostID == host.id

                        Button {
                            viewModel.selectHost(id: host.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(host.name)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(isSelected ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                onToggleCompact?()
            } label: {
                if isCompactEnabled {
                    Label("Compact Mode", systemImage: "checkmark")
                } else {
                    Text("Compact Mode")
                }
            }

            Button {
                onToggleStayOnTop?()
            } label: {
                if isStayOnTopEnabled {
                    Label("Stay on Top", systemImage: "checkmark")
                } else {
                    Text("Stay on Top")
                }
            }

            Divider()

            Button("Settings...") {
                onOpenSettings?()
            }

            Divider()

            Button("Quit") {
                onQuit?()
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.body)
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Ping History")
                    .font(.headline)

                timeRangePicker

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleGraphVisible()
                    }
                } label: {
                    Image(systemName: viewModel.modeState(for: .full).graphVisible ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.modeState(for: .full).graphVisible ? "Hide graph" : "Show graph")
            }

            if viewModel.modeState(for: .full).graphVisible {
                DisplayGraphView(points: viewModel.selectedHostGraphPoints)
                    .frame(height: 150)
            }
        }
    }

    private var timeRangePicker: some View {
        Menu {
            ForEach(DisplayTimeRange.allCases, id: \.self) { range in
                Button {
                    viewModel.setTimeRange(range)
                } label: {
                    if viewModel.selectedTimeRange == range {
                        Label(range.displayName, systemImage: "checkmark")
                    } else {
                        Text(range.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.selectedTimeRange.displayName)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Results")
                    .font(.headline)

                Spacer()

                Button {
                    copyScreenshotToClipboard()
                } label: {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.body)
                        .foregroundColor(showCopiedFeedback ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy screenshot to clipboard")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingStats.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundColor(showingStats ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Show statistics")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleHistoryVisible()
                    }
                } label: {
                    Image(systemName: viewModel.modeState(for: .full).historyVisible ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.modeState(for: .full).historyVisible ? "Hide results" : "Show results")
            }

            if viewModel.modeState(for: .full).historyVisible {
                // Column headers
                HStack(spacing: 10) {
                    Text("TIME")
                        .frame(minWidth: 65, alignment: .leading)
                    Text("HOST")
                    Spacer()
                    Text("STATUS")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

                RecentResultsListView(
                    rows: viewModel.selectedHostRecentResults,
                    maxVisibleRows: 10,
                    compact: false,
                    showHostName: true
                )
            }

            if showingStats {
                statsView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsView: some View {
        let results = viewModel.selectedHostRecentResults
        let hostAddress = viewModel.hosts.first { $0.id == viewModel.selectedHostID }?.address ?? "0.0.0.0"

        let transmitted = results.count
        let received = results.filter { $0.latencyMS != nil }.count
        let lossPercent = transmitted > 0 ? Double(transmitted - received) / Double(transmitted) * 100 : 0

        let latencies = results.compactMap(\.latencyMS)
        let minLatency = latencies.min() ?? 0
        let maxLatency = latencies.max() ?? 0
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let stddev = latencies.isEmpty ? 0 : sqrt(latencies.map { pow($0 - avgLatency, 2) }.reduce(0, +) / Double(latencies.count))

        return VStack(alignment: .leading, spacing: 4) {
            Text("--- \(hostAddress) ping statistics ---")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("\(transmitted) packets transmitted, \(received) packets received, \(String(format: "%.1f", lossPercent))% packet loss")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)

            Text("round-trip min/avg/max/stddev = \(String(format: "%.3f", minLatency))/\(String(format: "%.3f", avgLatency))/\(String(format: "%.3f", maxLatency))/\(String(format: "%.3f", stddev)) ms")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyScreenshotToClipboard() {
        let hostName = viewModel.hosts.first { $0.id == viewModel.selectedHostID }?.name ?? "Unknown"
        let screenshotView = ScreenshotView(
            hostName: hostName,
            timeRange: viewModel.selectedTimeRange.displayName,
            graphPoints: viewModel.selectedHostGraphPoints,
            recentResults: Array(viewModel.selectedHostRecentResults.prefix(10))
        )

        let renderer = ImageRenderer(content: screenshotView)
        renderer.scale = 2.0

        guard let nsImage = renderer.nsImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])

        withAnimation {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }
}

private struct ScreenshotView: View {
    let hostName: String
    let timeRange: String
    let graphPoints: [DisplayViewModel.GraphPoint]
    let recentResults: [DisplayViewModel.RecentResultRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PingScope - \(hostName)")
                    .font(.headline)
                Spacer()
                Text(timeRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DisplayGraphView(points: graphPoints)
                .frame(width: 400, height: 150)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("TIME")
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Text("STATUS")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(Array(recentResults.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(Self.timeFormatter.string(from: row.timestamp))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(for: row))
                                .frame(width: 6, height: 6)
                            Text(latencyText(for: row))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(statusColor(for: row))
                        }
                        .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 432)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusColor(for row: DisplayViewModel.RecentResultRow) -> Color {
        guard let latencyMS = row.latencyMS else { return .red }
        if latencyMS <= 80 { return .green }
        else if latencyMS <= 150 { return .yellow }
        else { return .red }
    }

    private func latencyText(for row: DisplayViewModel.RecentResultRow) -> String {
        guard let latencyMS = row.latencyMS else { return "Failed" }
        return "\(Int(latencyMS.rounded()))ms"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()
}

private extension DisplayTimeRange {
    var displayName: String {
        switch self {
        case .oneMinute:
            return "Last 1 min"
        case .fiveMinutes:
            return "Last 5 min"
        case .tenMinutes:
            return "Last 10 min"
        case .oneHour:
            return "Last 1 hour"
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview-full-mode")!
    let store = DisplayPreferencesStore(userDefaults: defaults, keyPrefix: "preview.full")
    let viewModel = DisplayViewModel(preferencesStore: store)

    let hosts = [
        Host(name: "Google", address: "8.8.8.8"),
        Host(name: "Cloudflare", address: "1.1.1.1"),
        Host(name: "Default Gateway", address: "192.168.1.1")
    ]
    viewModel.setHosts(hosts)
    viewModel.selectHost(id: hosts[0].id)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-20), latencyMS: 42)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date().addingTimeInterval(-10), latencyMS: 49)
    viewModel.ingestSample(hostID: hosts[0].id, timestamp: Date(), latencyMS: 37)

    return FullModeView(viewModel: viewModel)
        .frame(width: 420, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
}

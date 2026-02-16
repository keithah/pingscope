import AppKit
import Combine
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
        GeometryReader { proxy in
            let layout = FullModeLayout(
                containerHeight: proxy.size.height,
                showsHosts: viewModel.showsMonitoredHosts,
                historyVisible: viewModel.modeState(for: .full).historyVisible,
                showsStats: showingStats
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.showsMonitoredHosts {
                        hostPills
                    }
                    graphSection(graphHeight: layout.graphHeight)
                    historySection(maxVisibleRows: layout.historyVisibleRows)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .onAppear {
            viewModel.setDisplayMode(.full)
            showingStats = viewModel.showsHistorySummary
        }
        .onReceive(viewModel.$showsHistorySummary) { newValue in
            showingStats = newValue
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
                                    .fill(statusColor(for: viewModel.hostStatus(for: host.id)))
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

    private func statusColor(for status: DisplayViewModel.HostStatus) -> Color {
        switch status {
        case .good:
            return .green
        case .warning:
            return .yellow
        case .poor, .failure:
            return .red
        case .unknown:
            return .gray
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

    private func graphSection(graphHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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

                Text("Ping History")
                    .font(.headline)

                timeRangePicker

                Spacer()
            }

            if viewModel.modeState(for: .full).graphVisible {
                DisplayGraphView(points: viewModel.selectedHostGraphPoints)
                    .frame(height: graphHeight)
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

    private func historySection(maxVisibleRows: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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

            }

            if viewModel.modeState(for: .full).historyVisible {
                // Column headers
                HStack(spacing: 10) {
                    Text("TIME")
                        .frame(width: 65, alignment: .leading)
                    Text("HOST")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PING")
                        .frame(width: 56, alignment: .trailing)
                    Text("STATUS")
                        .frame(width: 64, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

                RecentResultsListView(
                    rows: viewModel.selectedHostRecentResults,
                    maxVisibleRows: maxVisibleRows,
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 6) {
                statsMetric(title: "Transmitted", value: "\(transmitted)")
                statsMetric(title: "Received", value: "\(received)")
                statsMetric(title: "Packet Loss", value: "\(String(format: "%.1f", lossPercent))%")
                statsMetric(title: "Min", value: "\(String(format: "%.3f", minLatency)) ms")
                statsMetric(title: "Avg", value: "\(String(format: "%.3f", avgLatency)) ms")
                statsMetric(title: "Max", value: "\(String(format: "%.3f", maxLatency)) ms")
                statsMetric(title: "Stddev", value: "\(String(format: "%.3f", stddev)) ms")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statsMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct FullModeLayout {
    let graphHeight: CGFloat
    let historyVisibleRows: Int?

    init(containerHeight: CGFloat, showsHosts: Bool, historyVisible: Bool, showsStats: Bool) {
        let clampedHeight = max(280, containerHeight)

        let graphTarget = clampedHeight * 0.3
        graphHeight = min(180, max(96, graphTarget))

        guard historyVisible else {
            historyVisibleRows = nil
            return
        }

        let fixedSectionsHeight: CGFloat = (showsHosts ? 86 : 0) + graphHeight + (showsStats ? 118 : 0) + 120
        let availableForRows = max(80, clampedHeight - fixedSectionsHeight)
        historyVisibleRows = max(3, Int(availableForRows / 26))
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

#if DEBUG
struct FullModeView_Previews: PreviewProvider {
    static var previews: some View {
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
}
#endif

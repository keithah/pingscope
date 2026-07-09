import Foundation
import PingScopeCore
import SwiftUI

public enum PingScopeIOSRunControlAction: Equatable, Sendable {
    case start(MonitorSessionDuration)
    case stop

    public static func selectionChanged(to duration: MonitorSessionDuration?) -> PingScopeIOSRunControlAction {
        guard let duration else { return .stop }
        return .start(duration)
    }
}

#if os(iOS)
public struct PingScopeIOSRootView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case monitor = "Monitor"
        case hosts = "Hosts"
        case history = "History"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .monitor: "waveform.path.ecg"
            case .hosts: "server.rack"
            case .history: "clock.arrow.circlepath"
            }
        }
    }

    private enum DisplayMode {
        case signal
        case ring
    }

    @State private var selectedTab: Tab = .monitor
    @State private var editingHost: HostConfig?
    @State private var isHostSwitcherPresented = false
    @State private var isMonitorSettingsPresented = false
    @State private var scrubbedLatencyMilliseconds: Double?
    @State private var displayMode: DisplayMode = .signal

    public var hosts: [HostConfig]
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth
    public var samples: [PingResult]
    public var graphPresentation: PingScopeIOSGraphPresentation
    public var historySamples: [PingResult]
    public var selectedGraphRange: TimeRange
    public var gatewayDetectionText: String?
    public var backgroundKeepAliveEnabled: Bool
    public var backgroundKeepAliveStatus: String
    public var selectedHostID: UUID
    public var onSelectHost: (UUID) -> Void
    public var onSaveHost: (HostConfig) -> Void
    public var onDeleteHost: (UUID) -> Void
    public var onMoveHosts: (IndexSet, Int) -> Void
    public var onSelectGraphRange: (TimeRange) -> Void
    public var onUseDefaultGateway: () -> Void
    public var onSetBackgroundKeepAlive: (Bool) -> Void
    public var onRequestBackgroundKeepAlivePermission: () -> Void
    public var onStart: (MonitorSessionDuration) -> Void
    public var onStop: () -> Void

    public init(
        hosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts,
        host: HostConfig = .defaultInternet,
        session: MonitorSessionState? = nil,
        health: HostHealth = HostHealth(hostID: HostConfig.defaultInternet.id, thresholds: HostConfig.defaultInternet.thresholds),
        samples: [PingResult] = [],
        graphPresentation: PingScopeIOSGraphPresentation? = nil,
        historySamples: [PingResult] = [],
        selectedGraphRange: TimeRange = .fiveMinutes,
        gatewayDetectionText: String? = nil,
        backgroundKeepAliveEnabled: Bool = false,
        backgroundKeepAliveStatus: String = "Disabled",
        selectedHostID: UUID? = nil,
        onSelectHost: @escaping (UUID) -> Void = { _ in },
        onSaveHost: @escaping (HostConfig) -> Void = { _ in },
        onDeleteHost: @escaping (UUID) -> Void = { _ in },
        onMoveHosts: @escaping (IndexSet, Int) -> Void = { _, _ in },
        onSelectGraphRange: @escaping (TimeRange) -> Void = { _ in },
        onUseDefaultGateway: @escaping () -> Void = {},
        onSetBackgroundKeepAlive: @escaping (Bool) -> Void = { _ in },
        onRequestBackgroundKeepAlivePermission: @escaping () -> Void = {},
        onStart: @escaping (MonitorSessionDuration) -> Void = { _ in },
        onStop: @escaping () -> Void = {}
    ) {
        self.hosts = hosts
        self.host = host
        self.session = session
        self.health = health
        self.samples = samples
        self.graphPresentation = graphPresentation ?? PingScopeIOSGraphPresentation(samples: samples, range: selectedGraphRange)
        self.historySamples = historySamples
        self.selectedGraphRange = selectedGraphRange
        self.gatewayDetectionText = gatewayDetectionText
        self.backgroundKeepAliveEnabled = backgroundKeepAliveEnabled
        self.backgroundKeepAliveStatus = backgroundKeepAliveStatus
        self.selectedHostID = selectedHostID ?? host.id
        self.onSelectHost = onSelectHost
        self.onSaveHost = onSaveHost
        self.onDeleteHost = onDeleteHost
        self.onMoveHosts = onMoveHosts
        self.onSelectGraphRange = onSelectGraphRange
        self.onUseDefaultGateway = onUseDefaultGateway
        self.onSetBackgroundKeepAlive = onSetBackgroundKeepAlive
        self.onRequestBackgroundKeepAlivePermission = onRequestBackgroundKeepAlivePermission
        self.onStart = onStart
        self.onStop = onStop
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .monitor:
                        monitorTab
                    case .hosts:
                        hostsTab
                    case .history:
                        historyTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                floatingTabBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(item: $editingHost) { draft in
                PingScopeIOSHostEditor(
                    host: draft,
                    canDelete: hosts.count > 1 && hosts.contains(where: { $0.id == draft.id }),
                    onSave: { updated in
                        onSaveHost(updated)
                        editingHost = nil
                    },
                    onDelete: {
                        onDeleteHost(draft.id)
                        editingHost = nil
                    },
                    onCancel: {
                        editingHost = nil
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isHostSwitcherPresented) {
                hostSwitcher
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isMonitorSettingsPresented) {
                monitorSettings
                    .presentationDetents([.medium])
            }
        }
    }

    private var monitorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monitorHeader
                readingRow
                heroDisplay
                    .frame(height: 206)
                rangePicker
                statsStrip
                runControl
                otherHostsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
    }

    private var monitorHeader: some View {
        HStack {
            Text("PingScope")
                .font(.system(size: 34, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                isMonitorSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Monitor settings")
        }
    }

    private var readingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isHostSwitcherPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(host.displayName)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue.opacity(0.72))
                    }
                    Text(endpointText(host))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                latencyReading(milliseconds: displayLatencyMilliseconds, size: 34)
                PingScopeIOSStatusPill(status: health.status)
            }
        }
    }

    @ViewBuilder
    private var heroDisplay: some View {
        switch displayMode {
        case .signal:
            SignalHeroGraphCard(
                renderData: graphPresentation.renderData,
                range: selectedGraphRange,
                status: health.status,
                scrubbedLatencyMilliseconds: $scrubbedLatencyMilliseconds,
                onStepRange: stepRange,
                onSwipeHost: swipeHost
            )
        case .ring:
            EmptyView()
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(
            get: { selectedGraphRange },
            set: { onSelectGraphRange($0) }
        )) {
            ForEach([TimeRange.oneMinute, .fiveMinutes, .tenMinutes]) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Graph range")
    }

    private var statsStrip: some View {
        let stats = graphPresentation.stats
        return HStack(spacing: 0) {
            iosStat("Min", latencyValue(stats.minimumMilliseconds))
            iosStat("Avg", latencyValue(stats.averageMilliseconds))
            iosStat("Max", latencyValue(stats.maximumMilliseconds))
            iosStat("Loss", "\(Int(stats.lossPercent.rounded()))%")
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func iosStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var runControl: some View {
        Picker("Run", selection: Binding(
            get: { session?.phase() == .ended ? nil : session?.duration },
            set: { duration in
                switch PingScopeIOSRunControlAction.selectionChanged(to: duration) {
                case .start(let duration):
                    onStart(duration)
                case .stop:
                    onStop()
                }
            }
        )) {
            Text("Live").tag(Optional(MonitorSessionDuration.continuous))
            Text("30s").tag(Optional(MonitorSessionDuration.thirtySeconds))
            Text("1m").tag(Optional(MonitorSessionDuration.oneMinute))
            Text("Stop").tag(Optional<MonitorSessionDuration>.none)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Run duration")
    }

    private var otherHostsCard: some View {
        let others = hosts.filter { $0.id != host.id }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Other hosts")
            if others.isEmpty {
                Text("Add another host from the Hosts tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(others)) { host in
                    Button {
                        onSelectHost(host.id)
                    } label: {
                        hostRow(host, isActive: false, showsSparkline: true)
                    }
                    .buttonStyle(.plain)
                    if host.id != others.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var hostsTab: some View {
        List {
            Section {
                ForEach(hosts) { listedHost in
                    Button {
                        editingHost = listedHost
                    } label: {
                        hostRow(listedHost, isActive: listedHost.id == host.id, showsSparkline: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            onSelectHost(listedHost.id)
                        } label: {
                            Label("Set Active", systemImage: "star.fill")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        onDeleteHost(hosts[index].id)
                    }
                }
                .onMove(perform: onMoveHosts)
            } header: {
                Text("Monitored hosts")
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 90)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingHost = HostConfig(displayName: "", address: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add host")
            }
        }
        .navigationTitle("Hosts")
    }

    private var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("History")
                            .font(.largeTitle.bold())
                        Text(host.displayName)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(historySamples.isEmpty ? "Rolling" : "\(historySamples.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                SignalHeroGraphCard(
                    renderData: PingScopeIOSGraphPresentation(samples: historySamples, range: selectedGraphRange).renderData,
                    range: selectedGraphRange,
                    status: health.status,
                    scrubbedLatencyMilliseconds: .constant(nil),
                    onStepRange: { _ in },
                    onSwipeHost: { _ in }
                )
                .frame(height: 220)

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Notable events")
                    if notableHistorySamples.isEmpty {
                        Text(historySamples.isEmpty ? "Samples appear here after monitoring starts." : "No degraded or failed samples in this rolling window.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(notableHistorySamples) { sample in
                            historyRow(sample)
                            if sample.id != notableHistorySamples.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
            .padding(.bottom, 104)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var hostSwitcher: some View {
        NavigationStack {
            List(hosts) { listedHost in
                Button {
                    onSelectHost(listedHost.id)
                    isHostSwitcherPresented = false
                } label: {
                    hostRow(listedHost, isActive: listedHost.id == host.id, showsSparkline: false)
                }
            }
            .navigationTitle("Switch Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isHostSwitcherPresented = false
                    }
                }
            }
        }
    }

    private var monitorSettings: some View {
        NavigationStack {
            Form {
                Section("Gateway") {
                    Button("Use Default Gateway", action: onUseDefaultGateway)
                    if let gatewayDetectionText {
                        Text(gatewayDetectionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Background Keep Alive") {
                    Toggle(isOn: Binding(
                        get: { backgroundKeepAliveEnabled },
                        set: { onSetBackgroundKeepAlive($0) }
                    )) {
                        Label("Background Keep Alive", systemImage: "location.fill")
                    }
                    Text(backgroundKeepAliveStatus)
                        .font(.caption.weight(.semibold))
                    Button("Request Always Permission", action: onRequestBackgroundKeepAlivePermission)
                }
                Section("Session") {
                    Text(session?.phase().rawValue.capitalized ?? "Ready")
                    Text(remainingText)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .navigationTitle("Monitor")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isMonitorSettingsPresented = false
                    }
                }
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private func hostRow(_ listedHost: HostConfig, isActive: Bool, showsSparkline: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? Color(iosStatusColor: health.status.iosStatusColor) : .gray.opacity(0.45))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(listedHost.displayName.isEmpty ? "New Host" : listedHost.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isActive {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
                Text(endpointText(listedHost))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showsSparkline {
                PingScopeIOSSparkline(renderData: isActive ? graphPresentation.renderData : PingScopeIOSLatencyGraphData(samples: [], range: selectedGraphRange), color: isActive ? .blue : .secondary)
                    .frame(width: 58, height: 28)
            }
            Text(isActive ? latencyValue(health.latestResult?.latency?.milliseconds) : "--")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ sample: PingResult) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(sample.isSuccess ? .yellow : .red)
                .frame(width: 8, height: 8)
            Text(sample.timestamp, style: .time)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
            Spacer()
            Text(sample.latency.map { "\(Int($0.milliseconds.rounded()))ms" } ?? sample.failureReason?.userMessage ?? "Failed")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(sample.isSuccess ? Color.secondary : Color.red)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func latencyReading(milliseconds: Double?, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(milliseconds.map { "\(Int($0.rounded()))" } ?? "--")
                .font(.system(size: size, weight: .semibold, design: .monospaced))
            Text("ms")
                .font(.system(size: size * 0.42, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var displayLatencyMilliseconds: Double? {
        scrubbedLatencyMilliseconds ?? health.latestResult?.latency?.milliseconds
    }

    private var notableHistorySamples: [PingResult] {
        Array(historySamples.filter { sample in
            if !sample.isSuccess { return true }
            return (sample.latency?.milliseconds ?? 0) >= host.thresholds.degradedMilliseconds
        }.suffix(12).reversed())
    }

    private var remainingText: String {
        guard let session else { return "Starting..." }
        if session.phase() == .ended { return "Ended" }
        if session.duration == .continuous { return "App open" }
        return "\(Int(ceil(session.remainingDuration().seconds)))s left"
    }

    private func latencyValue(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "--" }
        return "\(Int(milliseconds.rounded()))ms"
    }

    private func endpointText(_ host: HostConfig) -> String {
        "\(host.method.rawValue.uppercased()) \(host.address)"
    }

    private func stepRange(_ direction: Int) {
        let ranges: [TimeRange] = [.oneMinute, .fiveMinutes, .tenMinutes]
        guard let index = ranges.firstIndex(of: selectedGraphRange) else { return }
        let nextIndex = min(max(index + direction, 0), ranges.count - 1)
        guard nextIndex != index else { return }
        onSelectGraphRange(ranges[nextIndex])
    }

    private func swipeHost(_ direction: Int) {
        guard hosts.count > 1, let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        let nextIndex = (index + direction + hosts.count) % hosts.count
        onSelectHost(hosts[nextIndex].id)
    }
}

private struct PingScopeIOSStatusPill: View {
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var color: Color {
        Color(iosStatusColor: status.iosStatusColor)
    }

    private var label: String {
        switch status {
        case .noData: "No Data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

private struct SignalHeroGraphCard: View {
    let renderData: PingScopeIOSLatencyGraphData
    let range: TimeRange
    let status: HealthStatus
    @Binding var scrubbedLatencyMilliseconds: Double?
    let onStepRange: (Int) -> Void
    let onSwipeHost: (Int) -> Void

    private let yAxisWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                yAxisLabels
                    .frame(width: yAxisWidth)
                GeometryReader { proxy in
                    Canvas { context, size in
                        drawGrid(context: &context, size: size)
                        drawFill(context: &context, size: size)
                        drawLine(context: &context, size: size)
                    }
                    .gesture(graphDrag(size: proxy.size))
                    .simultaneousGesture(magnifyGesture)
                }
            }
            HStack {
                Color.clear.frame(width: yAxisWidth + 8)
                Text(renderData.startDate, style: .time)
                Spacer()
                Text("now")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(height: 18)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing) {
            ForEach(Array(renderData.scale.tickMilliseconds.enumerated()), id: \.offset) { _, tick in
                Text(renderData.scale.label(for: tick))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                if tick != renderData.scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var graphColor: Color {
        status == .healthy ? .blue : Color(iosStatusColor: status.iosStatusColor)
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                if value > 1.08 {
                    onStepRange(1)
                } else if value < 0.92 {
                    onStepRange(-1)
                }
            }
    }

    private func graphDrag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(max(value.location.x, 0), max(size.width, 1))
                scrubbedLatencyMilliseconds = latency(atX: x, width: size.width)
            }
            .onEnded { value in
                if abs(value.translation.width) > 72, abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    onSwipeHost(value.translation.width < 0 ? 1 : -1)
                }
                scrubbedLatencyMilliseconds = nil
            }
    }

    private func latency(atX x: CGFloat, width: CGFloat) -> Double? {
        guard !renderData.points.isEmpty else { return nil }
        let ratio = min(max(Double(x / max(width, 1)), 0), 1)
        let targetDate = renderData.startDate.addingTimeInterval(range.duration * ratio)
        return renderData.points.min {
            abs($0.timestamp.timeIntervalSince(targetDate)) < abs($1.timestamp.timeIntervalSince(targetDate))
        }?.latencyMilliseconds
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.0, 0.5, 1.0] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.14)), lineWidth: 1)
    }

    private func drawLinePath(size: CGSize) -> Path? {
        guard renderData.points.count > 1 else { return nil }
        var path = Path()
        let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
        for (index, pointValue) in renderData.points.enumerated() {
            let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
            let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
            let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
            let point = CGPoint(x: x, y: y)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }

    private func drawFill(context: inout GraphicsContext, size: CGSize) {
        guard renderData.points.count > 1, var fillPath = drawLinePath(size: size) else { return }
        let last = renderData.points.last!
        let first = renderData.points.first!
        let lastX = size.width * CGFloat(min(max(last.timestamp.timeIntervalSince(renderData.startDate) / range.duration, 0), 1))
        let firstX = size.width * CGFloat(min(max(first.timestamp.timeIntervalSince(renderData.startDate) / range.duration, 0), 1))
        fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
        fillPath.addLine(to: CGPoint(x: firstX, y: size.height))
        fillPath.closeSubpath()
        context.fill(fillPath, with: .linearGradient(
            Gradient(colors: [graphColor.opacity(0.28), graphColor.opacity(0.0)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))
    }

    private func drawLine(context: inout GraphicsContext, size: CGSize) {
        guard let path = drawLinePath(size: size) else { return }
        context.stroke(path, with: .color(graphColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

private struct PingScopeIOSSparkline: View {
    let renderData: PingScopeIOSLatencyGraphData
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard renderData.points.count > 1 else { return }
            var path = Path()
            let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
            for (index, pointValue) in renderData.points.enumerated() {
                let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
                let x = size.width * CGFloat(min(max(elapsed / max(renderData.endDate.timeIntervalSince(renderData.startDate), 1), 0), 1))
                let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PingScopeIOSHostEditor: View {
    @State private var draft: PingScopeIOSHostDraft

    let canDelete: Bool
    let onSave: (HostConfig) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        host: HostConfig,
        canDelete: Bool,
        onSave: @escaping (HostConfig) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: PingScopeIOSHostDraft(host: host))
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $draft.displayName)
                    TextField("Address", text: $draft.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Probe") {
                    Picker("Method", selection: methodBinding) {
                        ForEach(PingMethod.appStoreAvailableCases, id: \.self) { method in
                            Text(method.rawValue.uppercased()).tag(method)
                        }
                    }

                    TextField("Port", text: portText)
                        .keyboardType(.numberPad)
                        .disabled(draft.method == .icmp)
                }

                Section("Timing") {
                    Stepper(value: $draft.intervalMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Interval", value: "\(Int(draft.intervalMilliseconds))ms")
                    }
                    Stepper(value: $draft.timeoutMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Timeout", value: "\(Int(draft.timeoutMilliseconds))ms")
                    }
                }

                Section("Health") {
                    Stepper(value: $draft.degradedMilliseconds, in: 1...2_000, step: 25) {
                        LabeledContent("Degraded", value: "\(Int(draft.degradedMilliseconds))ms")
                    }
                    Stepper(value: $draft.downAfterFailures, in: 1...10) {
                        LabeledContent("Down after", value: "\(draft.downAfterFailures) failures")
                    }
                }

                if canDelete {
                    Section {
                        Button("Delete Host", role: .destructive) {
                            onDelete()
                        }
                    }
                }
            }
            .navigationTitle(draft.displayName.isEmpty ? "New Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.finalizedHost)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var methodBinding: Binding<PingMethod> {
        Binding(
            get: { draft.method },
            set: { method in
                draft.apply(method: method)
            }
        )
    }

    private var portText: Binding<String> {
        Binding(
            get: { draft.portText },
            set: { draft.portText = $0.filter(\.isNumber) }
        )
    }

    private var canSave: Bool {
        draft.canSave
    }
}

private extension HealthStatus {
    var iosStatusColor: StatusColor {
        switch self {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }
}

private extension Color {
    init(iosStatusColor: StatusColor) {
        switch iosStatusColor {
        case .gray: self = .gray
        case .green: self = .green
        case .yellow: self = .yellow
        case .red: self = .red
        }
    }
}
#endif

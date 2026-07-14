import Foundation
import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

public enum PingScopeIOSRunControlAction: Equatable, Sendable {
    case start(MonitorSessionDuration)
    case stop

    public static func selectionChanged(to duration: MonitorSessionDuration?) -> PingScopeIOSRunControlAction {
        guard let duration else { return .stop }
        return .start(duration)
    }
}

public enum PingScopeIOSLiveActivityDecision: Equatable, Sendable {
    case none
    case update
    case restart

    public static func decide(
        isSessionActive: Bool,
        previousScope: PingScopeIOSHostScope,
        newScope: PingScopeIOSHostScope,
        previousFocusedHostID: UUID,
        newFocusedHostID: UUID
    ) -> Self {
        guard isSessionActive else { return .none }
        guard previousScope == newScope else { return .restart }
        guard newScope == .allHosts || previousFocusedHostID == newFocusedHostID else {
            return .restart
        }
        return .update
    }
}

public struct PingScopeIOSHostGraphSeries: Identifiable, Equatable, Sendable {
    public let hostID: UUID
    public let samples: [PingResult]

    public var id: UUID { hostID }

    public init(hostID: UUID, samples: [PingResult]) {
        self.hostID = hostID
        self.samples = samples
    }
}

public struct PingScopeIOSAllHostsGraphRenderSeries: Equatable, Sendable {
    public let hostID: UUID
    public let startDate: Date
    public let endDate: Date
    public let samples: [PingResult]

    public init(hostID: UUID, startDate: Date, endDate: Date, samples: [PingResult]) {
        self.hostID = hostID
        self.startDate = startDate
        self.endDate = endDate
        self.samples = samples
    }
}

public struct PingScopeIOSAllHostsRowPresentation: Equatable, Sendable {
    public let displayStatus: HealthStatus
    public let latencyText: String
    public let accessibilityLabel: String
    public let focusAccessibilityHint: String

    public init(
        displayStatus: HealthStatus,
        latencyText: String,
        accessibilityLabel: String,
        focusAccessibilityHint: String
    ) {
        self.displayStatus = displayStatus
        self.latencyText = latencyText
        self.accessibilityLabel = accessibilityLabel
        self.focusAccessibilityHint = focusAccessibilityHint
    }
}

public enum PingScopeIOSDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case signal
    case ring

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .signal: "Signal"
        case .ring: "Ring"
        }
    }
}

public extension UserDefaults {
    var pingScopeIOSDisplayMode: PingScopeIOSDisplayMode {
        get {
            guard let rawValue = string(forKey: "pingScopeIOSDisplayMode"),
                  let mode = PingScopeIOSDisplayMode(rawValue: rawValue) else {
                return .signal
            }
            return mode
        }
        set {
            set(newValue.rawValue, forKey: "pingScopeIOSDisplayMode")
        }
    }

    var pingScopeIOSHistoryRange: HistoryRange {
        get {
            guard let rawValue = string(forKey: "pingScopeIOSHistoryRange"),
                  let range = HistoryRange(rawValue: rawValue) else {
                return .defaultValue
            }
            return range
        }
        set {
            set(newValue.rawValue, forKey: "pingScopeIOSHistoryRange")
        }
    }

    var pingScopeIOSHistoryLens: HistoryLens {
        get {
            guard let rawValue = string(forKey: "pingScopeIOSHistoryLens"),
                  let lens = HistoryLens(rawValue: rawValue) else {
                return .defaultValue
            }
            return lens
        }
        set {
            set(newValue.rawValue, forKey: "pingScopeIOSHistoryLens")
        }
    }

    var pingScopeIOSHistoryMapLensOverride: HistoryMapLens? {
        get {
            guard let rawValue = string(forKey: "pingScopeIOSHistoryMapLensOverride") else {
                return nil
            }
            return HistoryMapLens(rawValue: rawValue)
        }
        set {
            if let newValue {
                set(newValue.rawValue, forKey: "pingScopeIOSHistoryMapLensOverride")
            } else {
                removeObject(forKey: "pingScopeIOSHistoryMapLensOverride")
            }
        }
    }
}

public enum PingScopeIOSAllHostsMonitorPresentation {
    public static func displayMode(
        _ displayMode: PingScopeIOSDisplayMode,
        hostScope: PingScopeIOSHostScope
    ) -> PingScopeIOSDisplayMode {
        displayMode.resolvedForHostScope(showsAllHosts: hostScope == .allHosts)
    }

    public static func rows(
        hostScope: PingScopeIOSHostScope,
        allHostRows: [PingScopeIOSHostRowSnapshot]
    ) -> [PingScopeIOSHostRowSnapshot] {
        hostScope == .allHosts ? allHostRows : []
    }

    public static func graphSeries(
        hostScope: PingScopeIOSHostScope,
        allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    ) -> [PingScopeIOSHostGraphSeries] {
        hostScope == .allHosts ? allHostGraphSeries : []
    }

    public static func graphSamples(
        for row: PingScopeIOSHostRowSnapshot,
        allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    ) -> [PingResult] {
        allHostGraphSeries.first { $0.hostID == row.hostID }?.samples ?? row.samples
    }

    public static func graphRenderSeries(
        from series: [PingScopeIOSHostGraphSeries],
        range: TimeRange,
        endDate: Date
    ) -> [PingScopeIOSAllHostsGraphRenderSeries] {
        let startDate = endDate.addingTimeInterval(-range.duration)
        return series.map { source in
            PingScopeIOSAllHostsGraphRenderSeries(
                hostID: source.hostID,
                startDate: startDate,
                endDate: endDate,
                samples: samples(in: range, endingAt: endDate, from: source.samples)
            )
        }
    }

    public static func statistics(
        for series: [PingScopeIOSHostGraphSeries],
        range: TimeRange,
        endDate: Date
    ) -> SampleStats {
        SampleStats(samples: graphRenderSeries(from: series, range: range, endDate: endDate).flatMap(\.samples))
    }

    public static func combinedLatencyMilliseconds(
        from rows: [PingScopeIOSHostRowSnapshot]
    ) -> Double? {
        let latencies = rows.compactMap { row in
            row.isStale ? nil : row.latestLatencyMilliseconds
        }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    public static func rowPresentation(for row: PingScopeIOSHostRowSnapshot) -> PingScopeIOSAllHostsRowPresentation {
        let displayName = row.displayName.isEmpty ? "Unnamed Host" : row.displayName
        let isUnavailable = row.isStale || row.latestLatencyMilliseconds == nil
        let displayStatus: HealthStatus = row.isStale ? .noData : row.status
        let latencyText = isUnavailable ? "--ms" : row.latencyText
        let statusText = row.isStale ? "Stale" : accessibilityStatusText(for: row.status)
        let latencyDescription = isUnavailable
            ? "unavailable"
            : "\(Int((row.latestLatencyMilliseconds ?? 0).rounded())) milliseconds"
        return PingScopeIOSAllHostsRowPresentation(
            displayStatus: displayStatus,
            latencyText: latencyText,
            accessibilityLabel: "\(displayName), \(row.endpointCaption), \(statusText), \(latencyDescription)",
            focusAccessibilityHint: "Double-tap to focus \(displayName)."
        )
    }

    public static func stableColorIndex(for hostID: UUID, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let bytes = hostID.uuid
        let value = [
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        ].reduce(UInt64.zero) { partialResult, byte in
            (partialResult &* 31) &+ UInt64(byte)
        }
        return Int(value % UInt64(paletteCount))
    }

    private static func samples(in range: TimeRange, endingAt endDate: Date, from samples: [PingResult]) -> [PingResult] {
        let startDate = endDate.addingTimeInterval(-range.duration)
        return samples.filter { sample in
            sample.timestamp >= startDate && sample.timestamp <= endDate
        }
    }

    private static func accessibilityStatusText(for status: HealthStatus) -> String {
        switch status {
        case .noData: "No data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

public enum PingScopeIOSRootTab: String, CaseIterable, Identifiable, Sendable {
    case monitor = "Monitor"
    case hosts = "Hosts"
    case history = "History"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .monitor: "waveform.path.ecg"
        case .hosts: "server.rack"
        case .history: "clock.arrow.circlepath"
        }
    }

    public var hidesNavigationBar: Bool {
        self != .hosts
    }
}

#if os(iOS)
public struct PingScopeIOSRootView: View {
    @State private var selectedTab: PingScopeIOSRootTab = .monitor
    @State private var editingHost: HostConfig?
    @State private var isHostSwitcherPresented = false
    @State private var isMonitorSettingsPresented = false
    @State private var scrubbedLatencyMilliseconds: Double?

    public var hosts: [HostConfig]
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth
    public var samples: [PingResult]
    public var graphPresentation: PingScopeIOSGraphPresentation
    public var historySamples: [PingResult]
    public var historyRange: HistoryRange
    public var historyPresentationState: PingScopeIOSHistoryPresentationState
    public var historyLens: HistoryLens
    public var historyMapLens: HistoryMapLens
    public var historyLocationAuthorization: PingScopeIOSHistoryLocationAuthorization
    public var historyLocationTaggingOptIn: Bool
    public var historyMapContent: (PingScopeIOSHistorySelection, PingScopeIOSResolvedHistoryPresentation, HistoryMapLens) -> AnyView
    public var selectedGraphRange: TimeRange
    public var gatewayDetectionText: String?
    public var backgroundKeepAliveEnabled: Bool
    public var backgroundKeepAliveStatus: String
    public var displayMode: PingScopeIOSDisplayMode
    public var hostScope: PingScopeIOSHostScope
    public var allHostRows: [PingScopeIOSHostRowSnapshot]
    public var allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    public var allHostsPresentationEndDate: Date
    public var selectedHostID: UUID
    public var onSelectDisplayMode: (PingScopeIOSDisplayMode) -> Void
    public var onSelectAllHosts: () -> Void
    public var onSelectHost: (UUID) -> Void
    public var onSaveHost: (HostConfig) -> Void
    public var onDeleteHost: (UUID) -> Void
    public var onMoveHosts: (IndexSet, Int) -> Void
    public var onSelectGraphRange: (TimeRange) -> Void
    public var onSelectHistoryRange: (HistoryRange) -> Void
    public var onSelectHistoryLens: (HistoryLens) -> Void
    public var onSelectHistoryMapLens: (HistoryMapLens) -> Void
    public var onRequestHistoryMapPermission: () -> Void
    public var onShareHistory: (HistoryExportFormat) -> Void
    public var onShareHistoryReport: (HistoryReportFormat) -> Void
    public var onRefreshHistory: (UUID, HistoryRange) async -> Void
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
        historyRange: HistoryRange = .defaultValue,
        historyPresentationState: PingScopeIOSHistoryPresentationState? = nil,
        historyLens: HistoryLens = .defaultValue,
        historyMapLens: HistoryMapLens? = nil,
        historyLocationAuthorization: PingScopeIOSHistoryLocationAuthorization = .undetermined,
        historyLocationTaggingOptIn: Bool = false,
        historyMapContent: @escaping (PingScopeIOSHistorySelection, PingScopeIOSResolvedHistoryPresentation, HistoryMapLens) -> AnyView = { _, _, _ in AnyView(EmptyView()) },
        selectedGraphRange: TimeRange = .fiveMinutes,
        gatewayDetectionText: String? = nil,
        backgroundKeepAliveEnabled: Bool = false,
        backgroundKeepAliveStatus: String = "Disabled",
        displayMode: PingScopeIOSDisplayMode = .signal,
        hostScope: PingScopeIOSHostScope = .focused,
        allHostRows: [PingScopeIOSHostRowSnapshot] = [],
        allHostGraphSeries: [PingScopeIOSHostGraphSeries] = [],
        allHostsPresentationEndDate: Date? = nil,
        selectedHostID: UUID? = nil,
        onSelectDisplayMode: @escaping (PingScopeIOSDisplayMode) -> Void = { _ in },
        onSelectAllHosts: @escaping () -> Void = {},
        onSelectHost: @escaping (UUID) -> Void = { _ in },
        onSaveHost: @escaping (HostConfig) -> Void = { _ in },
        onDeleteHost: @escaping (UUID) -> Void = { _ in },
        onMoveHosts: @escaping (IndexSet, Int) -> Void = { _, _ in },
        onSelectGraphRange: @escaping (TimeRange) -> Void = { _ in },
        onSelectHistoryRange: @escaping (HistoryRange) -> Void = { _ in },
        onSelectHistoryLens: @escaping (HistoryLens) -> Void = { _ in },
        onSelectHistoryMapLens: @escaping (HistoryMapLens) -> Void = { _ in },
        onRequestHistoryMapPermission: @escaping () -> Void = {},
        onShareHistory: @escaping (HistoryExportFormat) -> Void = { _ in },
        onShareHistoryReport: @escaping (HistoryReportFormat) -> Void = { _ in },
        onRefreshHistory: @escaping (UUID, HistoryRange) async -> Void = { _, _ in },
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
        let resolvedGraphPresentation = graphPresentation ?? PingScopeIOSGraphPresentation(samples: samples, range: selectedGraphRange)
        self.graphPresentation = resolvedGraphPresentation
        self.historySamples = historySamples
        self.historyRange = historyRange
        let resolvedSelectedHostID = selectedHostID ?? host.id
        self.historyPresentationState = historyPresentationState ?? .loading(
            selection: PingScopeIOSHistorySelection(hostID: resolvedSelectedHostID, range: historyRange)
        )
        self.historyLens = historyLens
        self.historyMapLens = historyMapLens ?? .defaultValue(for: historyRange)
        self.historyLocationAuthorization = historyLocationAuthorization
        self.historyLocationTaggingOptIn = historyLocationTaggingOptIn
        self.historyMapContent = historyMapContent
        self.selectedGraphRange = selectedGraphRange
        self.gatewayDetectionText = gatewayDetectionText
        self.backgroundKeepAliveEnabled = backgroundKeepAliveEnabled
        self.backgroundKeepAliveStatus = backgroundKeepAliveStatus
        self.displayMode = displayMode
        self.hostScope = hostScope
        self.allHostRows = allHostRows
        self.allHostGraphSeries = allHostGraphSeries
        self.allHostsPresentationEndDate = allHostsPresentationEndDate ?? resolvedGraphPresentation.renderData.endDate
        self.selectedHostID = resolvedSelectedHostID
        self.onSelectDisplayMode = onSelectDisplayMode
        self.onSelectAllHosts = onSelectAllHosts
        self.onSelectHost = onSelectHost
        self.onSaveHost = onSaveHost
        self.onDeleteHost = onDeleteHost
        self.onMoveHosts = onMoveHosts
        self.onSelectGraphRange = onSelectGraphRange
        self.onSelectHistoryRange = onSelectHistoryRange
        self.onSelectHistoryLens = onSelectHistoryLens
        self.onSelectHistoryMapLens = onSelectHistoryMapLens
        self.onRequestHistoryMapPermission = onRequestHistoryMapPermission
        self.onShareHistory = onShareHistory
        self.onShareHistoryReport = onShareHistoryReport
        self.onRefreshHistory = onRefreshHistory
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
            .toolbar(selectedTab.hidesNavigationBar ? .hidden : .visible, for: .navigationBar)
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
                monitorHostRows
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

    @ViewBuilder
    private var readingRow: some View {
        if hostScope == .allHosts {
            allHostsReadingRow
        } else {
            focusedHostReadingRow
        }
    }

    private var focusedHostReadingRow: some View {
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

    private var allHostsReadingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isHostSwitcherPresented = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text("All Hosts")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.blue.opacity(0.72))
                    }
                    Text("\(allHostsMonitorRows.count) enabled")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            latencyReading(
                milliseconds: scrubbedLatencyMilliseconds ?? allHostsCombinedLatencyMilliseconds,
                size: 34
            )
        }
    }

    @ViewBuilder
    private var heroDisplay: some View {
        switch effectiveDisplayMode {
        case .signal:
            if hostScope == .allHosts {
                PingScopeIOSAllHostsSignalHeroGraphCard(
                    series: allHostsMonitorGraphSeries,
                    range: selectedGraphRange,
                    endDate: allHostsPresentationEndDate,
                    scrubbedLatencyMilliseconds: $scrubbedLatencyMilliseconds,
                    onStepRange: stepRange
                )
            } else {
                SignalHeroGraphCard(
                    renderData: graphPresentation.renderData,
                    range: selectedGraphRange,
                    status: health.status,
                    scrubbedLatencyMilliseconds: $scrubbedLatencyMilliseconds,
                    onStepRange: stepRange,
                    onSwipeHost: swipeHost
                )
            }
        case .ring:
            PingScopeIOSRingHero(
                latencyMilliseconds: displayLatencyMilliseconds,
                status: health.status,
                statusLabel: health.status.displayName,
                progress: ringProgress,
                onHostSwitch: {
                    isHostSwitcherPresented = true
                }
            )
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
        let stats = monitorStats
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

    @ViewBuilder
    private var monitorHostRows: some View {
        if hostScope == .allHosts {
            allHostsCard
        } else {
            otherHostsCard
        }
    }

    private var allHostsCard: some View {
        let rows = allHostsMonitorRows
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Hosts")
                .padding(.bottom, 8)
            if rows.isEmpty {
                Text("No enabled hosts to monitor.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 54)
            } else {
                ForEach(rows, id: \.hostID) { row in
                    let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row)
                    Button {
                        onSelectHost(row.hostID)
                    } label: {
                        allHostsRow(row, presentation: presentation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation.accessibilityLabel)
                    .accessibilityHint(presentation.focusAccessibilityHint)
                    if row.hostID != rows.last?.hostID {
                        Divider()
                            .padding(.leading, 20)
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
        let selection = PingScopeIOSHistorySelection(hostID: host.id, range: historyRange)
        let decision = PingScopeIOSHistoryContainerDecision(
            requestedLens: historyLens,
            authorization: historyLocationAuthorization,
            taggingOptIn: historyLocationTaggingOptIn,
            selection: selection,
            presentationState: historyPresentationState
        )
        return PingScopeIOSHistoryView(
            hostName: host.displayName,
            selectedRange: historyRange,
            requestedLens: historyLens,
            selectedMapLens: historyMapLens,
            decision: decision,
            mapContent: historyMapContent(selection, decision.resolvedPresentation, historyMapLens),
            onSelectRange: onSelectHistoryRange,
            onSelectLens: onSelectHistoryLens,
            onSelectMapLens: onSelectHistoryMapLens,
            onRequestMapPermission: onRequestHistoryMapPermission,
            onShare: onShareHistory,
            onShareReport: onShareHistoryReport
        )
        .task(id: selection) {
            await onRefreshHistory(selection.hostID, selection.range)
        }
    }

    private var hostSwitcher: some View {
        NavigationStack {
            List {
                Button {
                    onSelectAllHosts()
                    isHostSwitcherPresented = false
                } label: {
                    allHostsSwitcherRow
                }
                .buttonStyle(.plain)

                ForEach(hosts) { listedHost in
                    Button {
                        onSelectHost(listedHost.id)
                        isHostSwitcherPresented = false
                    } label: {
                        hostRow(
                            listedHost,
                            isActive: hostScope == .focused && listedHost.id == selectedHostID,
                            showsSparkline: false
                        )
                    }
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

    private var allHostsSwitcherRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text("All Hosts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Monitor enabled hosts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if hostScope == .allHosts {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
            }
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var monitorSettings: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Picker("Display", selection: Binding(
                        get: { displayMode },
                        set: { onSelectDisplayMode($0) }
                    )) {
                        ForEach(PingScopeIOSDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
            ForEach(PingScopeIOSRootTab.allCases) { tab in
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

    private func allHostsRow(
        _ row: PingScopeIOSHostRowSnapshot,
        presentation: PingScopeIOSAllHostsRowPresentation
    ) -> some View {
        let color = Color(iosStatusColor: presentation.displayStatus.iosStatusColor)
        let graphData = PingScopeIOSLatencyGraphData(
            samples: PingScopeIOSAllHostsMonitorPresentation.graphSamples(
                for: row,
                allHostGraphSeries: allHostsMonitorGraphSeries
            ),
            range: selectedGraphRange,
            endDate: allHostsPresentationEndDate
        )
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName.isEmpty ? "Unnamed Host" : row.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.endpointCaption)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PingScopeIOSSparkline(renderData: graphData, color: color)
                .frame(width: 64, height: 28)
                .opacity(graphData.points.count > 1 ? 1 : 0.18)
            Text(presentation.latencyText)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 56, alignment: .trailing)
        }
        .frame(height: 54)
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

    private var effectiveDisplayMode: PingScopeIOSDisplayMode {
        PingScopeIOSAllHostsMonitorPresentation.displayMode(displayMode, hostScope: hostScope)
    }

    private var allHostsMonitorRows: [PingScopeIOSHostRowSnapshot] {
        PingScopeIOSAllHostsMonitorPresentation.rows(hostScope: hostScope, allHostRows: allHostRows)
    }

    private var allHostsMonitorGraphSeries: [PingScopeIOSHostGraphSeries] {
        PingScopeIOSAllHostsMonitorPresentation.graphSeries(
            hostScope: hostScope,
            allHostGraphSeries: allHostGraphSeries
        )
    }

    private var allHostsCombinedLatencyMilliseconds: Double? {
        PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(from: allHostsMonitorRows)
    }

    private var monitorStats: SampleStats {
        guard hostScope == .allHosts else { return graphPresentation.stats }
        return PingScopeIOSAllHostsMonitorPresentation.statistics(
            for: allHostsMonitorGraphSeries,
            range: selectedGraphRange,
            endDate: allHostsPresentationEndDate
        )
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

    private var ringProgress: Double {
        guard let latency = displayLatencyMilliseconds else { return 0 }
        let threshold = max(host.thresholds.degradedMilliseconds, 1)
        return min(max(latency / threshold, 0), 1)
    }
}

private extension HealthStatus {
    var displayName: String {
        switch self {
        case .noData: "No Data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
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

private struct PingScopeIOSRingHero: View {
    let latencyMilliseconds: Double?
    let status: HealthStatus
    let statusLabel: String
    let progress: Double
    let onHostSwitch: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 16)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(latencyMilliseconds.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(.system(size: 46, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                    Text("ms")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(statusLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ringColor)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05), lineWidth: 1))
        .contentShape(Rectangle())
        .onLongPressGesture(perform: onHostSwitch)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusLabel), \(latencyMilliseconds.map { "\(Int($0.rounded())) milliseconds" } ?? "no latency")")
    }

    private var ringColor: Color {
        Color(iosStatusColor: status.iosStatusColor)
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
        let points = graphPoints(size: size)
        return Path(LatencyCurve.smoothedPath(points: points, closed: false))
    }

    private func graphPoints(size: CGSize) -> [CGPoint] {
        let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
        return renderData.points.map { pointValue in
            let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
            let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
            let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
            return CGPoint(x: x, y: y)
        }
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

private struct PingScopeIOSAllHostsSignalHeroGraphCard: View {
    private struct RenderSeries {
        let hostID: UUID
        let renderData: PingScopeIOSLatencyGraphData
        let color: Color
    }

    private static let graphColors: [Color] = [
        .blue,
        .cyan,
        .orange,
        .pink,
        .mint,
        .indigo
    ]

    let series: [PingScopeIOSHostGraphSeries]
    let range: TimeRange
    let endDate: Date
    @Binding var scrubbedLatencyMilliseconds: Double?
    let onStepRange: (Int) -> Void

    private let yAxisWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                yAxisLabels
                    .frame(width: yAxisWidth)
                GeometryReader { proxy in
                    ZStack {
                        Canvas { context, size in
                            drawGrid(context: &context, size: size)
                            for series in renderSeries {
                                drawLine(series, context: &context, size: size)
                            }
                        }
                        if !hasLatencyData {
                            Text("No samples in range")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .gesture(graphDrag(size: proxy.size))
                    .simultaneousGesture(magnifyGesture)
                }
            }
            HStack {
                Color.clear.frame(width: yAxisWidth + 8)
                Text(startDate, style: .time)
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
        .accessibilityLabel("All hosts latency graph")
    }

    private var renderSeries: [RenderSeries] {
        PingScopeIOSAllHostsMonitorPresentation.graphRenderSeries(
            from: series,
            range: range,
            endDate: endDate
        ).map { source in
            let colorIndex = PingScopeIOSAllHostsMonitorPresentation.stableColorIndex(
                for: source.hostID,
                paletteCount: Self.graphColors.count
            )
            return RenderSeries(
                hostID: source.hostID,
                renderData: PingScopeIOSLatencyGraphData(
                    samples: source.samples,
                    range: range,
                    endDate: source.endDate
                ),
                color: Self.graphColors[colorIndex]
            )
        }
    }

    private var scale: LatencyGraphScale {
        LatencyGraphScale(latencies: renderSeries.flatMap { series in
            series.renderData.points.map(\.latencyMilliseconds)
        })
    }

    private var startDate: Date {
        endDate.addingTimeInterval(-range.duration)
    }

    private var hasLatencyData: Bool {
        renderSeries.contains { !$0.renderData.points.isEmpty }
    }

    private var yAxisLabels: some View {
        VStack(alignment: .trailing) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, tick in
                Text(scale.label(for: tick))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                if tick != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
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
            .onEnded { _ in
                scrubbedLatencyMilliseconds = nil
            }
    }

    private func latency(atX x: CGFloat, width: CGFloat) -> Double? {
        let points = renderSeries.flatMap { $0.renderData.points }
        guard !points.isEmpty else { return nil }
        let ratio = min(max(Double(x / max(width, 1)), 0), 1)
        let targetDate = startDate.addingTimeInterval(range.duration * ratio)
        return points.min {
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

    private func drawLine(_ series: RenderSeries, context: inout GraphicsContext, size: CGSize) {
        guard series.renderData.points.count > 1 else { return }
        let axisMaximum = max(scale.axisMaximumMilliseconds, 1)
        let points = series.renderData.points.map { pointValue in
            let elapsed = pointValue.timestamp.timeIntervalSince(startDate)
            let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
            let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMaximum, 1)))
            return CGPoint(x: x, y: y)
        }
        context.stroke(
            Path(LatencyCurve.smoothedPath(points: points, closed: false)),
            with: .color(series.color),
            style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round)
        )
    }
}

private struct PingScopeIOSSparkline: View {
    let renderData: PingScopeIOSLatencyGraphData
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard renderData.points.count > 1 else { return }
            let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)
            let points = renderData.points.map { pointValue in
                let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
                let x = size.width * CGFloat(min(max(elapsed / max(renderData.endDate.timeIntervalSince(renderData.startDate), 1), 0), 1))
                let y = size.height - (size.height * CGFloat(min(pointValue.latencyMilliseconds / axisMax, 1)))
                return CGPoint(x: x, y: y)
            }
            let path = Path(LatencyCurve.smoothedPath(points: points, closed: false))
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
                    Toggle("Enabled", isOn: $draft.isEnabled)
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

extension HealthStatus {
    var iosStatusColor: StatusColor {
        switch self {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }
}

extension Color {
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

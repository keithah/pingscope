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
    public let resolvedColor: ResolvedHostDisplayColor

    public var id: UUID { hostID }

    public init(hostID: UUID, samples: [PingResult]) {
        self.hostID = hostID
        self.samples = samples
        self.resolvedColor = ResolvedHostDisplayColor(hostID: hostID, displayColor: nil)
    }

    public init(host: HostConfig, samples: [PingResult]) {
        self.hostID = host.id
        self.samples = samples
        self.resolvedColor = ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
    }
}

public struct PingScopeIOSFocusedPeerPresentation: Equatable, Sendable {
    public let rows: [PingScopeIOSHostRowSnapshot]
    public let graphSeries: [PingScopeIOSHostGraphSeries]

    public init(
        hosts: [HostConfig],
        selectedHostID: UUID,
        selectedHealth: HostHealth?,
        samplesByHost: [UUID: [PingResult]]
    ) {
        let enabledHosts = PingScopeIOSHostScopePresentation.enabledHosts(from: hosts)
        let cachedHostIDs = Set<UUID>(enabledHosts.compactMap { host in
            guard host.id != selectedHostID, samplesByHost[host.id]?.isEmpty == false else {
                return nil
            }
            return host.id
        })
        rows = PingScopeIOSHostScopePresentation.rows(
            from: enabledHosts,
            healthByHost: selectedHealth.map { [selectedHostID: $0] } ?? [:],
            samplesByHost: samplesByHost,
            cachedHostIDs: cachedHostIDs
        )
        graphSeries = enabledHosts.map {
            PingScopeIOSHostGraphSeries(host: $0, samples: samplesByHost[$0.id] ?? [])
        }
    }

    public static func transitioning(
        to selectedHostID: UUID,
        from hosts: [HostConfig],
        outgoingHostID: UUID,
        outgoingSamples: [PingResult],
        previousGraphSeries: [PingScopeIOSHostGraphSeries]
    ) -> Self {
        var samplesByHost = previousGraphSeries.reduce(into: [UUID: [PingResult]]()) {
            $0[$1.hostID] = $1.samples
        }
        var outgoingSamplesByID = Dictionary(
            uniqueKeysWithValues: (samplesByHost[outgoingHostID] ?? []).map { ($0.id, $0) }
        )
        for sample in outgoingSamples {
            outgoingSamplesByID[sample.id] = sample
        }
        samplesByHost[outgoingHostID] = outgoingSamplesByID.values.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        samplesByHost[selectedHostID] = []
        return Self(
            hosts: hosts,
            selectedHostID: selectedHostID,
            selectedHealth: nil,
            samplesByHost: samplesByHost
        )
    }
}

public struct PingScopeIOSAllHostsGraphRenderSeries: Equatable, Sendable {
    public let hostID: UUID
    public let startDate: Date
    public let endDate: Date
    public let samples: [PingResult]
    public let resolvedColor: ResolvedHostDisplayColor

    public init(
        hostID: UUID,
        startDate: Date,
        endDate: Date,
        samples: [PingResult],
        resolvedColor: ResolvedHostDisplayColor
    ) {
        self.hostID = hostID
        self.startDate = startDate
        self.endDate = endDate
        self.samples = samples
        self.resolvedColor = resolvedColor
    }
}

public struct PingScopeIOSAllHostsPreparedGraphSeries: Equatable, Sendable, Identifiable {
    public let hostID: UUID
    public let renderData: PingScopeIOSLatencyGraphData
    public let resolvedColor: ResolvedHostDisplayColor

    public var id: UUID { hostID }

    public init(
        hostID: UUID,
        renderData: PingScopeIOSLatencyGraphData,
        resolvedColor: ResolvedHostDisplayColor
    ) {
        self.hostID = hostID
        self.renderData = renderData
        self.resolvedColor = resolvedColor
    }
}

public struct PingScopeIOSAllHostsGraphPresentation: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let series: [PingScopeIOSAllHostsPreparedGraphSeries]
    public let statistics: SampleStats
    public let scale: LatencyGraphScale
    public let chronologicalPoints: [PingScopeIOSLatencyGraphPoint]

    private let graphDataByHostID: [UUID: PingScopeIOSLatencyGraphData]

    public init(
        startDate: Date,
        endDate: Date,
        series: [PingScopeIOSAllHostsPreparedGraphSeries],
        statistics: SampleStats
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.series = series
        self.statistics = statistics
        self.graphDataByHostID = Dictionary(uniqueKeysWithValues: series.map { ($0.hostID, $0.renderData) })
        let indexedPoints = series.flatMap { $0.renderData.points }.enumerated()
        self.chronologicalPoints = indexedPoints.sorted { lhs, rhs in
            if lhs.element.timestamp != rhs.element.timestamp {
                return lhs.element.timestamp < rhs.element.timestamp
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        self.scale = LatencyGraphScale(latencies: series.flatMap { source in
            source.renderData.points.map(\.latencyMilliseconds)
        })
    }

    public func graphData(for hostID: UUID) -> PingScopeIOSLatencyGraphData? {
        graphDataByHostID[hostID]
    }
}

public struct PingScopeIOSAllHostsRowPresentation: Equatable, Sendable {
    public let displayName: String
    public let displayStatus: HealthStatus
    public let latencyText: String
    public let cacheLabel: String?
    public let accessibilityLabel: String
    public let actionAccessibilityHint: String
    public let resolvedColor: ResolvedHostDisplayColor

    public var focusAccessibilityHint: String { actionAccessibilityHint }

    public init(
        displayName: String,
        displayStatus: HealthStatus,
        latencyText: String,
        cacheLabel: String? = nil,
        accessibilityLabel: String,
        actionAccessibilityHint: String,
        resolvedColor: ResolvedHostDisplayColor
    ) {
        self.displayName = displayName
        self.displayStatus = displayStatus
        self.latencyText = latencyText
        self.cacheLabel = cacheLabel
        self.accessibilityLabel = accessibilityLabel
        self.actionAccessibilityHint = actionAccessibilityHint
        self.resolvedColor = resolvedColor
    }
}

public enum PingScopeIOSHostRowAction: Equatable, Sendable {
    case focus
    case edit
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

    var pingScopeIOSConnectivityTipsEnabled: Bool {
        get { bool(forKey: "pingScopeIOSConnectivityTipsEnabled") }
        set { set(newValue, forKey: "pingScopeIOSConnectivityTipsEnabled") }
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
    public static func rows(
        hostScope: PingScopeIOSHostScope,
        allHostRows: [PingScopeIOSHostRowSnapshot]
    ) -> [PingScopeIOSHostRowSnapshot] {
        allHostRows
    }

    public static func graphSeries(
        hostScope: PingScopeIOSHostScope,
        allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    ) -> [PingScopeIOSHostGraphSeries] {
        allHostGraphSeries
    }

    public static func graphSamples(
        for row: PingScopeIOSHostRowSnapshot,
        allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    ) -> [PingResult] {
        allHostGraphSeries.first { $0.hostID == row.hostID }?.samples ?? row.samples
    }

    public static func graphIdentityColor(
        for host: HostConfig
    ) -> ResolvedHostDisplayColor {
        ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
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
                samples: samples(in: range, endingAt: endDate, from: source.samples),
                resolvedColor: source.resolvedColor
            )
        }
    }

    public static func graphPresentation(
        from series: [PingScopeIOSHostGraphSeries],
        range: TimeRange,
        endDate: Date
    ) -> PingScopeIOSAllHostsGraphPresentation {
        let renderSeries = graphRenderSeries(from: series, range: range, endDate: endDate)
        var statisticsSamples: [PingResult] = []
        statisticsSamples.reserveCapacity(renderSeries.reduce(0) { $0 + $1.samples.count })
        let preparedSeries = renderSeries.map { source in
            statisticsSamples.append(contentsOf: source.samples)
            return PingScopeIOSAllHostsPreparedGraphSeries(
                hostID: source.hostID,
                renderData: PingScopeIOSLatencyGraphData(
                    samples: source.samples,
                    startDate: source.startDate,
                    endDate: source.endDate
                ),
                resolvedColor: source.resolvedColor
            )
        }
        return PingScopeIOSAllHostsGraphPresentation(
            startDate: endDate.addingTimeInterval(-range.duration),
            endDate: endDate,
            series: preparedSeries,
            statistics: SampleStats(samples: statisticsSamples)
        )
    }

    public static func statistics(
        for series: [PingScopeIOSHostGraphSeries],
        range: TimeRange,
        endDate: Date
    ) -> SampleStats {
        graphPresentation(from: series, range: range, endDate: endDate).statistics
    }

    public static func combinedLatencyMilliseconds(
        from rows: [PingScopeIOSHostRowSnapshot]
    ) -> Double? {
        let latencies = rows.compactMap { row in
            row.isStale || row.isCached ? nil : row.latestLatencyMilliseconds
        }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    public static func rowPresentation(
        for row: PingScopeIOSHostRowSnapshot,
        action: PingScopeIOSHostRowAction = .focus
    ) -> PingScopeIOSAllHostsRowPresentation {
        let displayName = row.displayName.isEmpty ? "Unnamed Host" : row.displayName
        let latencyText = row.isStale ? "--ms" : row.latencyText
        let isUnavailable = latencyText == "--ms"
        let displayStatus: HealthStatus = row.isStale || row.isCached ? .noData : row.status
        let statusText: String
        if row.isStale {
            statusText = "Stale"
        } else if row.isCached {
            statusText = "Cached data"
        } else {
            statusText = accessibilityStatusText(for: row.status)
        }
        let latencyDescription = isUnavailable
            ? "unavailable"
            : "\(Int((row.latestLatencyMilliseconds ?? 0).rounded())) milliseconds"
        let actionAccessibilityHint = switch action {
        case .focus: "Double-tap to focus \(displayName)."
        case .edit: "Double-tap to edit \(displayName)."
        }
        return PingScopeIOSAllHostsRowPresentation(
            displayName: displayName,
            displayStatus: displayStatus,
            latencyText: latencyText,
            cacheLabel: row.isCached ? "Cached" : nil,
            accessibilityLabel: "\(displayName), \(row.endpointCaption), \(statusText), \(latencyDescription)",
            actionAccessibilityHint: actionAccessibilityHint,
            resolvedColor: row.resolvedColor
        )
    }

    public static func stableColorIndex(for hostID: UUID, paletteCount: Int) -> Int {
        HostDisplayColorAutomaticPalette.stableIndex(for: hostID, paletteCount: paletteCount)
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

public struct PingScopeIOSSwitchHostConcreteItem: Identifiable, Equatable, Sendable {
    public let hostID: UUID
    public let row: PingScopeIOSHostRowSnapshot
    public let rowPresentation: PingScopeIOSAllHostsRowPresentation
    public let resolvedColor: ResolvedHostDisplayColor
    public let action: PingScopeIOSHostRowAction
    public let isSelected: Bool

    public var id: UUID { hostID }
}

public enum PingScopeIOSSwitchHostItem: Identifiable, Equatable, Sendable {
    case allHosts(isSelected: Bool)
    case host(PingScopeIOSSwitchHostConcreteItem)

    public var id: String {
        switch self {
        case .allHosts:
            "all-hosts"
        case .host(let item):
            item.hostID.uuidString
        }
    }
}

public struct PingScopeIOSSwitchHostPresentation: Equatable, Sendable {
    public let items: [PingScopeIOSSwitchHostItem]
    public let allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation

    public init(
        hosts: [HostConfig],
        hostScope: PingScopeIOSHostScope,
        selectedHostID: UUID,
        selectedHealth: HostHealth?,
        selectedSamples: [PingResult],
        allHostRows: [PingScopeIOSHostRowSnapshot],
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) {
        self.allHostsGraphPresentation = allHostsGraphPresentation
        let rowsByHostID = allHostRows.reduce(into: [UUID: PingScopeIOSHostRowSnapshot]()) {
            $0[$1.hostID] = $1
        }
        let concreteItems = hosts.map { host in
            let isSelected = hostScope == .focused && host.id == selectedHostID
            let row = rowsByHostID[host.id] ?? PingScopeIOSHostRowSnapshot(
                host: host,
                health: isSelected ? selectedHealth : nil,
                samples: isSelected ? selectedSamples : []
            )
            let rowPresentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(
                for: row,
                action: .focus
            )
            return PingScopeIOSSwitchHostConcreteItem(
                hostID: host.id,
                row: row,
                rowPresentation: rowPresentation,
                resolvedColor: rowPresentation.resolvedColor,
                action: .focus,
                isSelected: isSelected
            )
        }
        items = [.allHosts(isSelected: hostScope == .allHosts)] + concreteItems.map(PingScopeIOSSwitchHostItem.host)
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

@MainActor
final class PingScopeIOSAllHostsGraphPresentationMemo: ObservableObject {
    private struct CacheKey: Hashable {
        let rangeDuration: TimeInterval
        let endDate: Date
        let series: [SeriesKey]
    }

    private struct SeriesKey: Hashable {
        let hostID: UUID
        let samples: AppendOnlySequenceFingerprint<UUID>
        let resolvedColor: ResolvedHostDisplayColor
    }

    private var cache = BoundedMemo<CacheKey, PingScopeIOSAllHostsGraphPresentation>(capacity: 1)

    func resolve(
        series: [PingScopeIOSHostGraphSeries],
        range: TimeRange,
        endDate: Date
    ) -> PingScopeIOSAllHostsGraphPresentation {
        let key = CacheKey(
            rangeDuration: range.duration,
            endDate: endDate,
            series: series.map {
                SeriesKey(
                    hostID: $0.hostID,
                    samples: AppendOnlySequenceFingerprint(samples: $0.samples),
                    resolvedColor: $0.resolvedColor
                )
            }
        )
        return cache.resolve(key) {
            PingScopeIOSAllHostsMonitorPresentation.graphPresentation(
                from: series,
                range: range,
                endDate: endDate
            )
        }
    }
}

#if os(iOS)
private struct PingScopeIOSGraphReadingGroup<Reading: View, Graph: View>: View {
    @State private var scrubbedLatencyMilliseconds: Double?

    let reading: (Double?) -> Reading
    let graph: (Binding<Double?>) -> Graph

    init(
        @ViewBuilder reading: @escaping (Double?) -> Reading,
        @ViewBuilder graph: @escaping (Binding<Double?>) -> Graph
    ) {
        self.reading = reading
        self.graph = graph
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            reading(scrubbedLatencyMilliseconds)
            graph($scrubbedLatencyMilliseconds)
        }
    }
}

public struct PingScopeIOSRootView: View {
    @State private var selectedTab: PingScopeIOSRootTab = .monitor
    @State private var editingHost: HostConfig?
    @State private var isHostSwitcherPresented = false
    @State private var isMonitorSettingsPresented = false
    @State private var isOnboardingPresented = false
    @State private var includesSensitiveDiagnostics = false
    @State private var showsWidgetInstructions = false
    @StateObject private var allHostsGraphPresentationMemo = PingScopeIOSAllHostsGraphPresentationMemo()

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
    public var historyMapContent: (PingScopeIOSHistorySelection, PingScopeIOSResolvedHistoryPresentation, HistoryMapLens, Bool) -> AnyView
    public var selectedGraphRange: TimeRange
    public var gatewayDetectionText: String?
    public var backgroundKeepAliveEnabled: Bool
    public var backgroundKeepAliveStatus: String
    public var displayMode: PingScopeIOSDisplayMode
    public var hostScope: PingScopeIOSHostScope
    public var allHostRows: [PingScopeIOSHostRowSnapshot]
    public var allHostGraphSeries: [PingScopeIOSHostGraphSeries]
    public var monitorInsights: PingScopeIOSMonitorInsightsPresentation
    public var connectivityTipsEnabled: Bool
    public var lockScreenLiveActivityEnabled: Bool
    public var dynamicIslandDetailsEnabled: Bool
    public var allHostsPresentationEndDate: Date
    public var selectedHostID: UUID
    public var onboardingPresentation: PingScopeIOSOnboardingPresentation
    public var diagnosticsMetadata: PingScopeIOSDiagnosticsMetadata
    public var diagnosticsLogText: String
    public var cloudSyncEnabled: Bool
    public var cloudSyncStatusText: String
    public var onSelectDisplayMode: (PingScopeIOSDisplayMode) -> Void
    public var onSetConnectivityTipsEnabled: (Bool) -> Void
    public var onSetLockScreenLiveActivityEnabled: (Bool) -> Void
    public var onSetDynamicIslandDetailsEnabled: (Bool) -> Void
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
    public var onRefreshDiagnostics: () async -> Void
    public var onShareDiagnostics: (Bool) -> Void
    public var onDismissOnboarding: () -> Void
    public var onOpenAppSettings: () -> Void
    public var onSetCloudSyncEnabled: (Bool) -> Void

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
        historyMapContent: @escaping (PingScopeIOSHistorySelection, PingScopeIOSResolvedHistoryPresentation, HistoryMapLens, Bool) -> AnyView = { _, _, _, _ in AnyView(EmptyView()) },
        selectedGraphRange: TimeRange = .fiveMinutes,
        gatewayDetectionText: String? = nil,
        backgroundKeepAliveEnabled: Bool = false,
        backgroundKeepAliveStatus: String = "Disabled",
        displayMode: PingScopeIOSDisplayMode = .signal,
        hostScope: PingScopeIOSHostScope = .focused,
        allHostRows: [PingScopeIOSHostRowSnapshot] = [],
        allHostGraphSeries: [PingScopeIOSHostGraphSeries] = [],
        monitorInsights: PingScopeIOSMonitorInsightsPresentation = .init(snapshots: []),
        connectivityTipsEnabled: Bool = false,
        lockScreenLiveActivityEnabled: Bool = true,
        dynamicIslandDetailsEnabled: Bool = true,
        allHostsPresentationEndDate: Date? = nil,
        selectedHostID: UUID? = nil,
        onboardingPresentation: PingScopeIOSOnboardingPresentation = .init(
            inputs: .init(
                notificationAuthorization: .unknown,
                localNetworkCapability: .notRequired,
                locationAuthorization: .undetermined,
                isLocationTaggingEnabled: false,
                hasConfiguredWidget: false
            ),
            hasBeenSeen: true
        ),
        diagnosticsMetadata: PingScopeIOSDiagnosticsMetadata = .init(appName: "PingScope", version: "--", build: "--", buildFlavor: "--"),
        diagnosticsLogText: String = "",
        cloudSyncEnabled: Bool = false,
        cloudSyncStatusText: String = "Off",
        onSelectDisplayMode: @escaping (PingScopeIOSDisplayMode) -> Void = { _ in },
        onSetConnectivityTipsEnabled: @escaping (Bool) -> Void = { _ in },
        onSetLockScreenLiveActivityEnabled: @escaping (Bool) -> Void = { _ in },
        onSetDynamicIslandDetailsEnabled: @escaping (Bool) -> Void = { _ in },
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
        onStop: @escaping () -> Void = {},
        onRefreshDiagnostics: @escaping () async -> Void = {},
        onShareDiagnostics: @escaping (Bool) -> Void = { _ in },
        onDismissOnboarding: @escaping () -> Void = {},
        onOpenAppSettings: @escaping () -> Void = {},
        onSetCloudSyncEnabled: @escaping (Bool) -> Void = { _ in }
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
        self.monitorInsights = monitorInsights
        self.connectivityTipsEnabled = connectivityTipsEnabled
        self.lockScreenLiveActivityEnabled = lockScreenLiveActivityEnabled
        self.dynamicIslandDetailsEnabled = dynamicIslandDetailsEnabled
        self.allHostsPresentationEndDate = allHostsPresentationEndDate ?? resolvedGraphPresentation.renderData.endDate
        self.selectedHostID = resolvedSelectedHostID
        self.onboardingPresentation = onboardingPresentation
        self.diagnosticsMetadata = diagnosticsMetadata
        self.diagnosticsLogText = diagnosticsLogText
        self.cloudSyncEnabled = cloudSyncEnabled
        self.cloudSyncStatusText = cloudSyncStatusText
        self.onSelectDisplayMode = onSelectDisplayMode
        self.onSetConnectivityTipsEnabled = onSetConnectivityTipsEnabled
        self.onSetLockScreenLiveActivityEnabled = onSetLockScreenLiveActivityEnabled
        self.onSetDynamicIslandDetailsEnabled = onSetDynamicIslandDetailsEnabled
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
        self.onRefreshDiagnostics = onRefreshDiagnostics
        self.onShareDiagnostics = onShareDiagnostics
        self.onDismissOnboarding = onDismissOnboarding
        self.onOpenAppSettings = onOpenAppSettings
        self.onSetCloudSyncEnabled = onSetCloudSyncEnabled
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
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                PingScopeIOSOnboardingView(
                    presentation: onboardingPresentation,
                    onSelectDestination: { destination in
                        switch destination {
                        case .appSettings: onOpenAppSettings()
                        case .widgetInstructions: showsWidgetInstructions = true
                        }
                    },
                    onDismiss: {
                        onDismissOnboarding()
                        isOnboardingPresented = false
                    }
                )
            }
            .alert("Add a Widget", isPresented: $showsWidgetInstructions) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Touch and hold the Home Screen, tap Edit, then Add Widget and choose PingScope.")
            }
            .task {
                if onboardingPresentation.shouldPresentOnLaunch {
                    isOnboardingPresented = true
                }
            }
        }
    }

    private var monitorTab: some View {
        let allHostsGraphPresentation = allHostsGraphPresentationMemo.resolve(
            series: allHostsMonitorGraphSeries,
            range: selectedGraphRange,
            endDate: allHostsPresentationEndDate
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monitorHeader
                PingScopeIOSGraphReadingGroup { scrubbedLatencyMilliseconds in
                    readingRow(scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds)
                } graph: { scrubbedLatencyMilliseconds in
                    heroDisplay(
                        scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds,
                        allHostsGraphPresentation: allHostsGraphPresentation
                    )
                    .frame(height: 206)
                }
                rangePicker
                statsStrip(allHostsGraphPresentation: allHostsGraphPresentation)
                monitorInsightsSection
                runControl
                monitorHostRows(allHostsGraphPresentation: allHostsGraphPresentation)
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
    private func readingRow(scrubbedLatencyMilliseconds: Double?) -> some View {
        if hostScope == .allHosts {
            allHostsReadingRow(scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds)
        } else {
            focusedHostReadingRow(scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds)
        }
    }

    private func focusedHostReadingRow(scrubbedLatencyMilliseconds: Double?) -> some View {
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
                latencyReading(
                    milliseconds: scrubbedLatencyMilliseconds ?? health.latestResult?.latency?.milliseconds,
                    size: 34
                )
                PingScopeIOSStatusPill(status: health.status)
            }
        }
    }

    private func allHostsReadingRow(scrubbedLatencyMilliseconds: Double?) -> some View {
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
    private func heroDisplay(
        scrubbedLatencyMilliseconds: Binding<Double?>,
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) -> some View {
        switch displayMode {
        case .signal:
            if hostScope == .allHosts {
                PingScopeIOSAllHostsSignalHeroGraphCard(
                    presentation: allHostsGraphPresentation,
                    range: selectedGraphRange,
                    scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds,
                    onStepRange: stepRange
                )
            } else {
                SignalHeroGraphCard(
                    renderData: graphPresentation.renderData,
                    range: selectedGraphRange,
                    color: PingScopeIOSAllHostsMonitorPresentation
                        .graphIdentityColor(for: host)
                        .swiftUIColor,
                    scrubbedLatencyMilliseconds: scrubbedLatencyMilliseconds,
                    onStepRange: stepRange,
                    onSwipeHost: swipeHost
                )
            }
        case .ring:
            if hostScope == .allHosts {
                PingScopeIOSAllHostsConcentricRingHero(rows: allHostsMonitorRows, onSelectHost: onSelectHost)
            } else {
                PingScopeIOSRingHero(
                    latencyMilliseconds: scrubbedLatencyMilliseconds.wrappedValue ?? health.latestResult?.latency?.milliseconds,
                    status: health.status,
                    statusLabel: health.status.displayName,
                    progress: ringProgress(
                        for: scrubbedLatencyMilliseconds.wrappedValue ?? health.latestResult?.latency?.milliseconds
                    ),
                    onHostSwitch: {
                        isHostSwitcherPresented = true
                    }
                )
            }
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

    private func statsStrip(
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) -> some View {
        let stats = hostScope == .allHosts ? allHostsGraphPresentation.statistics : graphPresentation.stats
        return HStack(spacing: 0) {
            iosStat("Min", latencyValue(stats.minimumMilliseconds))
            iosStat("Avg", latencyValue(stats.averageMilliseconds))
            iosStat("Max", latencyValue(stats.maximumMilliseconds))
            iosStat("Loss", "\(Int(stats.lossPercent.rounded()))%")
        }
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var monitorInsightsSection: some View {
        let visibility = PingScopeIOSMonitorInsightsVisibility(
            presentation: monitorInsights,
            connectivityTipsEnabled: connectivityTipsEnabled
        )
        if visibility.hasContent {
            VStack(alignment: .leading, spacing: 10) {
                if let diagnosis = visibility.diagnosis {
                    PingScopeIOSDiagnosisCard(presentation: diagnosis)
                }
                ForEach(visibility.starlink) { presentation in
                    PingScopeIOSStarlinkCard(presentation: presentation)
                }
            }
        }
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

    private func otherHostsCard(
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) -> some View {
        let others = hosts.filter { $0.id != host.id }.prefix(3)
        let cachedRows = allHostsMonitorRows.reduce(into: [UUID: PingScopeIOSHostRowSnapshot]()) {
            $0[$1.hostID] = $1
        }
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
                        if let row = cachedRows[host.id] {
                            allHostsRow(
                                row,
                                presentation: PingScopeIOSAllHostsMonitorPresentation.rowPresentation(
                                    for: row,
                                    action: .focus
                                ),
                                allHostsGraphPresentation: allHostsGraphPresentation
                            )
                        } else {
                            hostRow(host, isActive: false, showsSparkline: true)
                        }
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
    private func monitorHostRows(
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) -> some View {
        if hostScope == .allHosts {
            allHostsCard(allHostsGraphPresentation: allHostsGraphPresentation)
        } else {
            otherHostsCard(allHostsGraphPresentation: allHostsGraphPresentation)
        }
    }

    private func allHostsCard(
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation
    ) -> some View {
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
                    let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(
                        for: row,
                        action: .focus
                    )
                    Button {
                        onSelectHost(row.hostID)
                    } label: {
                        allHostsRow(
                            row,
                            presentation: presentation,
                            allHostsGraphPresentation: allHostsGraphPresentation
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(presentation.accessibilityLabel)
                    .accessibilityHint(presentation.actionAccessibilityHint)
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
        let cachedRows = allHostsMonitorRows.reduce(into: [UUID: PingScopeIOSHostRowSnapshot]()) {
            $0[$1.hostID] = $1
        }
        let allHostsGraphPresentation = allHostsGraphPresentationMemo.resolve(
            series: allHostsMonitorGraphSeries,
            range: selectedGraphRange,
            endDate: allHostsPresentationEndDate
        )
        return List {
            Section {
                ForEach(hosts) { listedHost in
                    Button {
                        editingHost = listedHost
                    } label: {
                        if listedHost.id != host.id, let row = cachedRows[listedHost.id] {
                            allHostsRow(
                                row,
                                presentation: PingScopeIOSAllHostsMonitorPresentation.rowPresentation(
                                    for: row,
                                    action: .edit
                                ),
                                allHostsGraphPresentation: allHostsGraphPresentation
                            )
                        } else {
                            hostRow(listedHost, isActive: listedHost.id == host.id, showsSparkline: true)
                        }
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
            mapContent: historyMapContent(
                selection,
                decision.resolvedPresentation,
                historyMapLens,
                PingScopeIOSHistoryRenderingState(decision: decision).mapNoteShown
            ),
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
        let allHostsGraphPresentation = allHostsGraphPresentationMemo.resolve(
            series: allHostsMonitorGraphSeries,
            range: selectedGraphRange,
            endDate: allHostsPresentationEndDate
        )
        let switcherPresentation = PingScopeIOSSwitchHostPresentation(
            hosts: hosts,
            hostScope: hostScope,
            selectedHostID: selectedHostID,
            selectedHealth: health,
            selectedSamples: samples,
            allHostRows: allHostsMonitorRows,
            allHostsGraphPresentation: allHostsGraphPresentation
        )
        return NavigationStack {
            List {
                ForEach(switcherPresentation.items) { item in
                    switch item {
                    case .allHosts(let isSelected):
                        Button {
                            onSelectAllHosts()
                            isHostSwitcherPresented = false
                        } label: {
                            allHostsSwitcherRow(isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                    case .host(let concreteItem):
                        Button {
                            onSelectHost(concreteItem.hostID)
                            isHostSwitcherPresented = false
                        } label: {
                            allHostsRow(
                                concreteItem.row,
                                presentation: concreteItem.rowPresentation,
                                allHostsGraphPresentation: switcherPresentation.allHostsGraphPresentation,
                                isSelected: concreteItem.isSelected
                            )
                        }
                        .accessibilityLabel(concreteItem.rowPresentation.accessibilityLabel)
                        .accessibilityHint(concreteItem.rowPresentation.actionAccessibilityHint)
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

    private func allHostsSwitcherRow(isSelected: Bool) -> some View {
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
            if isSelected {
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
                    Toggle("Connectivity Tips", isOn: Binding(
                        get: { connectivityTipsEnabled },
                        set: { onSetConnectivityTipsEnabled($0) }
                    ))
                }
                Section("Gateway") {
                    Button("Use Default Gateway", action: onUseDefaultGateway)
                    if let gatewayDetectionText {
                        Text(gatewayDetectionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Live Activity") {
                    Toggle("Lock Screen Live Activity", isOn: Binding(
                        get: { lockScreenLiveActivityEnabled },
                        set: { onSetLockScreenLiveActivityEnabled($0) }
                    ))
                    Toggle("Dynamic Island Details", isOn: Binding(
                        get: { dynamicIslandDetailsEnabled },
                        set: { onSetDynamicIslandDetailsEnabled($0) }
                    ))
                    .disabled(!lockScreenLiveActivityEnabled)
                    Text("Lock Screen Live Activity controls the Live Activity on both the Lock Screen and Dynamic Island. Dynamic Island Details only reduces the information shown on Dynamic Island; it cannot remove the system surface independently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Section("Setup") {
                    Button {
                        isOnboardingPresented = true
                    } label: {
                        Label(
                            onboardingPresentation.overallStatus == .allSet ? "Setup Complete" : "Finish Setup",
                            systemImage: onboardingPresentation.overallStatus == .allSet ? "checkmark.circle.fill" : "checklist"
                        )
                    }
                }
                Section("iCloud Sync") {
                    Toggle("Sync History & Hosts", isOn: Binding(
                        get: { cloudSyncEnabled },
                        set: { onSetCloudSyncEnabled($0) }
                    ))
                    Text(cloudSyncStatusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Off by default. History and host settings leave this iPhone only after you enable sync, and are stored in your private iCloud database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    LabeledContent("Version", value: "\(diagnosticsMetadata.version) (\(diagnosticsMetadata.build))")
                    Text(diagnosticsLogText.isEmpty ? "No recent log entries." : diagnosticsLogText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                    Toggle("Include location and network names", isOn: $includesSensitiveDiagnostics)
                    Button("Refresh Log") {
                        Task { await onRefreshDiagnostics() }
                    }
                    Button("Share Diagnostics") {
                        onShareDiagnostics(includesSensitiveDiagnostics)
                    }
                    Menu("Export History") {
                        Button("CSV") { onShareHistory(.csv) }
                        Button("JSON") { onShareHistory(.json) }
                    }
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
        let color = PingScopeIOSAllHostsMonitorPresentation
            .graphIdentityColor(for: listedHost)
            .swiftUIColor
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
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
                PingScopeIOSSparkline(
                    renderData: isActive
                        ? graphPresentation.renderData
                        : PingScopeIOSLatencyGraphData(samples: [], range: selectedGraphRange),
                    color: color
                )
                    .frame(width: 58, height: 28)
            }
            Text(isActive ? latencyValue(health.latestResult?.latency?.milliseconds) : "--")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func allHostsRow(
        _ row: PingScopeIOSHostRowSnapshot,
        presentation: PingScopeIOSAllHostsRowPresentation,
        allHostsGraphPresentation: PingScopeIOSAllHostsGraphPresentation,
        isSelected: Bool = false
    ) -> some View {
        let color = presentation.resolvedColor.swiftUIColor
        let graphData: PingScopeIOSLatencyGraphData
        if hostScope == .focused, let firstSample = row.samples.first, let lastSample = row.samples.last {
            graphData = PingScopeIOSLatencyGraphData(
                samples: row.samples,
                startDate: min(firstSample.timestamp, lastSample.timestamp.addingTimeInterval(-1)),
                endDate: lastSample.timestamp
            )
        } else {
            graphData = allHostsGraphPresentation.graphData(for: row.hostID) ?? PingScopeIOSLatencyGraphData(
                samples: row.samples,
                range: selectedGraphRange,
                endDate: allHostsPresentationEndDate
            )
        }
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.displayName)
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
            VStack(alignment: .trailing, spacing: 2) {
                if let cacheLabel = presentation.cacheLabel {
                    Text(cacheLabel)
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Text(presentation.latencyText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 56, alignment: .trailing)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.actionAccessibilityHint)
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

    private func ringProgress(for latency: Double?) -> Double {
        guard let latency else { return 0 }
        let threshold = max(host.thresholds.degradedMilliseconds, 1)
        return min(max(latency / threshold, 0), 1)
    }
}

extension HealthStatus {
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

private struct PingScopeIOSDiagnosisCard: View {
    let presentation: PingScopeIOSDiagnosisPresentation

    var body: some View {
        let tint = Color(iosDiagnosisTone: presentation.tone)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct PingScopeIOSStarlinkCard: View {
    let presentation: PingScopeIOSStarlinkPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(starlinkTitle)
                .font(.subheadline.weight(.semibold))
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                alignment: .leading,
                spacing: 10
            ) {
                item("State", presentation.state)
                item("Drop", presentation.dropRate)
                item("Obstructed", presentation.obstruction)
                item("Down", presentation.downlinkThroughput)
                item("Up", presentation.uplinkThroughput)
                item("Uptime", presentation.uptime)
            }
            if let alerts = presentation.alerts {
                Text(alerts)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var starlinkTitle: String {
        presentation.hostName.localizedCaseInsensitiveCompare("Starlink") == .orderedSame
            ? "Starlink"
            : "Starlink · \(presentation.hostName)"
    }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
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

    init(iosDiagnosisTone: PingScopeIOSDiagnosisTone) {
        switch iosDiagnosisTone {
        case .gray: self = .gray
        case .green: self = .green
        case .yellow: self = .yellow
        case .orange: self = .orange
        case .red: self = .red
        }
    }
}
#endif

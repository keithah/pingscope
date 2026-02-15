import Combine
import Foundation

@MainActor
final class DisplayViewModel: ObservableObject {
    struct HostSample: Equatable {
        let timestamp: Date
        let latencyMS: Double?
    }

    struct GraphPoint: Equatable {
        let timestamp: Date
        let latencyMS: Double
    }

    struct RecentResultRow: Equatable {
        let timestamp: Date
        let latencyMS: Double?
        let hostName: String?

        var isSuccess: Bool {
            latencyMS != nil
        }
    }

    @Published private(set) var hosts: [Host] = []
    @Published private(set) var displayMode: DisplayMode
    @Published private(set) var selectedHostID: UUID?
    @Published private(set) var selectedTimeRange: DisplayTimeRange
    @Published private(set) var showsMonitoredHosts: Bool
    @Published private(set) var showsHistorySummary: Bool

    private let preferencesStore: DisplayPreferencesStore
    private let sampleBufferLimit: Int
    private var modeStateByMode: [DisplayMode: DisplayModeState]
    private var samplesByHostID: [UUID: [HostSample]] = [:]

    init(
        preferencesStore: DisplayPreferencesStore = DisplayPreferencesStore(),
        initialMode: DisplayMode = .full,
        sampleBufferLimit: Int = 3_600
    ) {
        self.preferencesStore = preferencesStore
        displayMode = initialMode
        self.sampleBufferLimit = max(1, sampleBufferLimit)

        let shared = preferencesStore.sharedState
        selectedHostID = shared.selectedHostID
        selectedTimeRange = shared.selectedTimeRange
        showsMonitoredHosts = shared.showsMonitoredHosts
        showsHistorySummary = shared.showsHistorySummary

        modeStateByMode = [
            .full: preferencesStore.modeState(for: .full),
            .compact: preferencesStore.modeState(for: .compact)
        ]
    }

    var graphVisible: Bool {
        modeState(for: displayMode).graphVisible
    }

    var historyVisible: Bool {
        modeState(for: displayMode).historyVisible
    }

    var selectedHostGraphPoints: [GraphPoint] {
        graphPoints(for: selectedHostID)
    }

    var selectedHostRecentResults: [RecentResultRow] {
        recentResults(for: selectedHostID)
    }

    func setHosts(_ hosts: [Host]) {
        self.hosts = hosts

        guard !hosts.isEmpty else {
            selectedHostID = nil
            persistSharedState()
            return
        }

        if let selectedHostID,
           hosts.contains(where: { $0.id == selectedHostID }) {
            return
        }

        self.selectedHostID = hosts[0].id
        persistSharedState()
    }

    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
    }

    func selectHost(id: UUID?) {
        guard selectedHostID != id else {
            return
        }

        selectedHostID = id
        persistSharedState()
    }

    func setTimeRange(_ range: DisplayTimeRange) {
        guard selectedTimeRange != range else {
            return
        }

        selectedTimeRange = range
        persistSharedState()
    }

    func setShowsMonitoredHosts(_ isVisible: Bool) {
        guard showsMonitoredHosts != isVisible else {
            return
        }

        showsMonitoredHosts = isVisible
        persistSharedState()
    }

    func setShowsHistorySummary(_ isVisible: Bool) {
        guard showsHistorySummary != isVisible else {
            return
        }

        showsHistorySummary = isVisible
        persistSharedState()
    }

    func setGraphVisible(_ isVisible: Bool, for mode: DisplayMode? = nil) {
        updateModeState(for: mode ?? displayMode) {
            $0.graphVisible = isVisible
        }
    }

    func setHistoryVisible(_ isVisible: Bool, for mode: DisplayMode? = nil) {
        updateModeState(for: mode ?? displayMode) {
            $0.historyVisible = isVisible
        }
    }

    func toggleGraphVisible(for mode: DisplayMode? = nil) {
        let targetMode = mode ?? displayMode
        setGraphVisible(!modeState(for: targetMode).graphVisible, for: targetMode)
    }

    func toggleHistoryVisible(for mode: DisplayMode? = nil) {
        let targetMode = mode ?? displayMode
        setHistoryVisible(!modeState(for: targetMode).historyVisible, for: targetMode)
    }

    func modeState(for mode: DisplayMode) -> DisplayModeState {
        modeStateByMode[mode] ?? .default(for: mode)
    }

    func ingest(_ result: PingResult, for hostID: UUID) {
        ingestSample(
            hostID: hostID,
            timestamp: result.timestamp,
            latencyMS: result.latency.map(Self.durationToMilliseconds)
        )
    }

    func ingestSample(hostID: UUID, timestamp: Date, latencyMS: Double?) {
        var samples = samplesByHostID[hostID] ?? []
        samples.append(HostSample(timestamp: timestamp, latencyMS: latencyMS))

        if samples.count > sampleBufferLimit {
            samples.removeFirst(samples.count - sampleBufferLimit)
        }

        samplesByHostID[hostID] = samples

        // Notify observers so graph and results views update with new data.
        objectWillChange.send()
    }

    func graphPoints(for hostID: UUID?) -> [GraphPoint] {
        filteredSamples(for: hostID)
            .compactMap { sample in
                guard let latencyMS = sample.latencyMS else {
                    return nil
                }

                return GraphPoint(timestamp: sample.timestamp, latencyMS: latencyMS)
            }
    }

    func recentResults(for hostID: UUID?, limit: Int? = nil) -> [RecentResultRow] {
        let hostName = hostID.flatMap { id in hosts.first { $0.id == id }?.name }

        let rows = filteredSamples(for: hostID)
            .reversed()
            .map {
                RecentResultRow(timestamp: $0.timestamp, latencyMS: $0.latencyMS, hostName: hostName)
            }

        guard let limit else {
            return Array(rows)
        }

        return Array(rows.prefix(max(0, limit)))
    }

    /// Returns a status indicator for the host based on most recent ping result.
    /// - Green: <= 80ms latency
    /// - Yellow: <= 150ms latency
    /// - Red: > 150ms or failure (nil latency)
    /// - Gray: No samples yet
    func hostStatus(for hostID: UUID) -> HostStatus {
        guard let samples = samplesByHostID[hostID], !samples.isEmpty else {
            return .unknown
        }

        // Use the most recent sample to determine status
        guard let latestLatency = samples.last?.latencyMS else {
            return .failure
        }

        if latestLatency <= 80 {
            return .good
        } else if latestLatency <= 150 {
            return .warning
        } else {
            return .poor
        }
    }

    enum HostStatus {
        case good      // green: <= 80ms
        case warning   // yellow: <= 150ms
        case poor      // red: > 150ms
        case failure   // red: nil latency (failed)
        case unknown   // gray: no samples
    }

    private func filteredSamples(for hostID: UUID?) -> [HostSample] {
        guard let hostID,
              let hostSamples = samplesByHostID[hostID]
        else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-selectedTimeRange.windowDuration)
        return hostSamples.filter { $0.timestamp >= cutoff }
    }

    private func updateModeState(for mode: DisplayMode, _ update: (inout DisplayModeState) -> Void) {
        var state = modeState(for: mode)
        update(&state)

        // `DisplayModeCoordinator` persists frame changes (move/resize) directly to the
        // preferences store. Preserve the latest persisted frame data here so UI-only
        // toggles (graph/history collapse) don't accidentally overwrite window geometry.
        state.frameData = preferencesStore.modeState(for: mode).frameData

        modeStateByMode[mode] = state
        preferencesStore.setModeState(state, for: mode)

        // Notify observers so SwiftUI re-renders collapsed/expanded sections.
        objectWillChange.send()
    }

    private func persistSharedState() {
        preferencesStore.sharedState = DisplaySharedState(
            selectedHostID: selectedHostID,
            selectedTimeRange: selectedTimeRange,
            showsMonitoredHosts: showsMonitoredHosts,
            showsHistorySummary: showsHistorySummary
        )
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let secondsMS = Double(components.seconds) * 1_000
        let attosecondsMS = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMS + attosecondsMS
    }
}

private extension DisplayTimeRange {
    var windowDuration: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 300
        case .tenMinutes:
            return 600
        case .oneHour:
            return 3_600
        }
    }
}

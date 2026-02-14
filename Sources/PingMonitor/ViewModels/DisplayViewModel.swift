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

        var isSuccess: Bool {
            latencyMS != nil
        }
    }

    @Published private(set) var hosts: [Host] = []
    @Published private(set) var displayMode: DisplayMode
    @Published private(set) var selectedHostID: UUID?
    @Published private(set) var selectedTimeRange: DisplayTimeRange

    private let preferencesStore: DisplayPreferencesStore
    private let sampleBufferLimit: Int
    private var modeStateByMode: [DisplayMode: DisplayModeState]
    private var samplesByHostID: [UUID: [HostSample]] = [:]

    init(
        preferencesStore: DisplayPreferencesStore = DisplayPreferencesStore(),
        initialMode: DisplayMode = .full,
        sampleBufferLimit: Int = 360
    ) {
        self.preferencesStore = preferencesStore
        displayMode = initialMode
        self.sampleBufferLimit = max(1, sampleBufferLimit)

        let shared = preferencesStore.sharedState
        selectedHostID = shared.selectedHostID
        selectedTimeRange = shared.selectedTimeRange

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
        let rows = filteredSamples(for: hostID)
            .reversed()
            .map {
                RecentResultRow(timestamp: $0.timestamp, latencyMS: $0.latencyMS)
            }

        guard let limit else {
            return Array(rows)
        }

        return Array(rows.prefix(max(0, limit)))
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
        modeStateByMode[mode] = state
        preferencesStore.setModeState(state, for: mode)
    }

    private func persistSharedState() {
        preferencesStore.sharedState = DisplaySharedState(
            selectedHostID: selectedHostID,
            selectedTimeRange: selectedTimeRange
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

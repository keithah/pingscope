import Foundation
import PingScopeCore

public enum HistoryRange: String, CaseIterable, Codable, Hashable, Sendable {
    case h1 = "1H"
    case h4 = "4H"
    case h12 = "12H"
    case h24 = "24H"
    case d7 = "7D"
    case d14 = "14D"
    case d30 = "30D"

    public static let defaultValue: HistoryRange = .h24

    public var duration: TimeInterval {
        switch self {
        case .h1: 60 * 60
        case .h4: 4 * 60 * 60
        case .h12: 12 * 60 * 60
        case .h24: 24 * 60 * 60
        case .d7: 7 * 24 * 60 * 60
        case .d14: 14 * 24 * 60 * 60
        case .d30: 30 * 24 * 60 * 60
        }
    }

    public var queryLimit: Int {
        switch self {
        case .h1: 2_500
        case .h4: 8_000
        case .h12: 25_000
        case .h24, .d7, .d14, .d30: 50_000
        }
    }

    public var usesLongRangeReduction: Bool {
        switch self {
        case .d7, .d14, .d30: true
        case .h1, .h4, .h12, .h24: false
        }
    }

    public func cutoff(endingAt endDate: Date) -> Date {
        endDate.addingTimeInterval(-duration)
    }

    public var endpointLabelStyle: PingScopeIOSHistoryEndpointLabelStyle {
        switch self {
        case .h1, .h4, .h12: .time
        case .h24, .d7: .compactDateTime
        case .d14, .d30: .compactDate
        }
    }
}

public enum PingScopeIOSHistoryEndpointLabelStyle: Equatable, Sendable {
    case time
    case compactDateTime
    case compactDate
}

public struct PingScopeIOSHistorySelection: Equatable, Hashable, Sendable {
    public let hostID: UUID
    public let range: HistoryRange

    public init(hostID: UUID, range: HistoryRange) {
        self.hostID = hostID
        self.range = range
    }
}

public enum PingScopeIOSHistoryRefreshTrigger: Equatable, Sendable {
    case operational
    case historyVisible(PingScopeIOSHistorySelection)
}

public enum PingScopeIOSHistoryRangedRefreshPolicy {
    public static func selection(
        for trigger: PingScopeIOSHistoryRefreshTrigger
    ) -> PingScopeIOSHistorySelection? {
        switch trigger {
        case .operational: nil
        case let .historyVisible(selection): selection
        }
    }
}

public struct PingScopeIOSHistoryLoadResult: Equatable, Sendable {
    public let hostID: UUID
    public let range: HistoryRange
    public let cutoff: Date
    public let endingAt: Date
    public let samples: [PingResult]
    public let chartReduction: HistoryChartReduction
    public let isCollecting: Bool

    public init(
        hostID: UUID,
        range: HistoryRange,
        cutoff: Date,
        endingAt: Date,
        samples: [PingResult],
        chartReduction: HistoryChartReduction,
        isCollecting: Bool
    ) {
        self.hostID = hostID
        self.range = range
        self.cutoff = cutoff
        self.endingAt = endingAt
        self.samples = samples
        self.chartReduction = chartReduction
        self.isCollecting = isCollecting
    }
}

public actor PingScopeIOSHistoryLoader {
    private var generation: UInt64 = 0
    private var requestedHostID: UUID?
    private var requestedRange: HistoryRange?

    public init() {}

    public func load(
        store: any PingHistoryStore,
        hostID: UUID,
        range: HistoryRange,
        now: Date
    ) async -> PingScopeIOSHistoryLoadResult? {
        generation &+= 1
        let requestGeneration = generation
        requestedHostID = hostID
        requestedRange = range
        let cutoff = range.cutoff(endingAt: now)

        let loadedSamples = await store.latestSamples(
            hostID: hostID,
            since: cutoff,
            limit: range.queryLimit
        )

        guard requestGeneration == generation,
              requestedHostID == hostID,
              requestedRange == range else {
            return nil
        }

        let samples = stableChronologicalSamples(loadedSamples)
        let isCollecting: Bool
        if samples.isEmpty {
            isCollecting = false
        } else if loadedSamples.count >= range.queryLimit {
            isCollecting = true
        } else {
            let nominalInterval = HistorySession.nominalInterval(samples: samples)
            let leadingGapTolerance = max(60, 3 * nominalInterval)
            isCollecting = samples[0].timestamp.timeIntervalSince(cutoff) > leadingGapTolerance
        }
        return PingScopeIOSHistoryLoadResult(
            hostID: hostID,
            range: range,
            cutoff: cutoff,
            endingAt: now,
            samples: samples,
            chartReduction: HistoryChartReduction(samples: samples),
            isCollecting: isCollecting
        )
    }
}

public struct HistoryMetrics: Equatable, Sendable {
    public let averageMilliseconds: Double?
    public let p95Milliseconds: Double?
    public let lossPercent: Double
    public let minimumMilliseconds: Double?
    public let maximumMilliseconds: Double?
    public let outageCount: Int
    public let uptimePercent: Double

    public init(samples: [PingResult]) {
        let stats = SampleStats(samples: samples)
        averageMilliseconds = stats.averageMilliseconds
        lossPercent = stats.lossPercent
        minimumMilliseconds = stats.minimumMilliseconds
        maximumMilliseconds = stats.maximumMilliseconds
        uptimePercent = max(0, 100 - stats.lossPercent)

        let successfulLatencies = samples.compactMap { sample -> Double? in
            guard sample.isSuccess, let latency = sample.latency?.milliseconds, latency.isFinite else {
                return nil
            }
            return latency
        }.sorted()
        if successfulLatencies.isEmpty {
            p95Milliseconds = nil
        } else {
            let nearestRank = Int(ceil(0.95 * Double(successfulLatencies.count)))
            p95Milliseconds = successfulLatencies[nearestRank - 1]
        }

        var inOutage = false
        var outages = 0
        for sample in stableChronologicalSamples(samples) {
            if sample.isSuccess {
                inOutage = false
            } else if !inOutage {
                outages += 1
                inOutage = true
            }
        }
        outageCount = outages
    }
}

public struct HistorySession: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let samples: [PingResult]
    public let sparklineSamples: [PingResult]
    public let metrics: HistoryMetrics
    public let status: HealthStatus

    public var hasOutage: Bool { metrics.outageCount > 0 }

    public static func nominalInterval(samples: [PingResult], fallback: TimeInterval = 60) -> TimeInterval {
        let chronological = stableChronologicalSamples(samples)
        let deltas = zip(chronological, chronological.dropFirst())
            .map { $1.timestamp.timeIntervalSince($0.timestamp) }
            .filter { $0 > 0 }
            .sorted()
        guard deltas.count >= 2 else { return fallback }
        return deltas[(deltas.count - 1) / 2]
    }

    public static func sessionize(
        _ samples: [PingResult],
        thresholds: LatencyThresholds = .defaults,
        nominalIntervalFallback: TimeInterval = 60,
        sparklineLimit: Int = 60
    ) -> [HistorySession] {
        let chronological = stableChronologicalSamples(samples)
        guard !chronological.isEmpty else { return [] }
        let interval = nominalInterval(samples: chronological, fallback: nominalIntervalFallback)
        let boundary = max(3 * interval, 120)
        var groups: [[PingResult]] = [[chronological[0]]]
        for sample in chronological.dropFirst() {
            let gap = sample.timestamp.timeIntervalSince(groups[groups.count - 1].last!.timestamp)
            if gap > boundary {
                groups.append([sample])
            } else {
                groups[groups.count - 1].append(sample)
            }
        }
        return groups.map { group in
            let metrics = HistoryMetrics(samples: group)
            let status: HealthStatus
            if metrics.outageCount > 0 {
                status = .down
            } else if (metrics.maximumMilliseconds ?? 0) >= thresholds.degradedMilliseconds {
                status = .degraded
            } else {
                status = .healthy
            }
            return HistorySession(
                startDate: group[0].timestamp,
                endDate: group[group.count - 1].timestamp,
                samples: group,
                sparklineSamples: boundedSamples(group, limit: sparklineLimit),
                metrics: metrics,
                status: status
            )
        }
    }
}

public struct HistoryChartPoint: Equatable, Sendable {
    public let timestamp: Date
    public let latencyMilliseconds: Double

    public init(timestamp: Date, latencyMilliseconds: Double) {
        self.timestamp = timestamp
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct HistoryChartBucket: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let timestamp: Date
    public let minimum: HistoryChartPoint?
    public let average: HistoryChartPoint?
    public let maximum: HistoryChartPoint?
    public let failureRepresentative: PingResult?
    public let failureCount: Int
    public let sampleCount: Int
    public let sourceRepresentativeID: UUID?
}

public struct HistoryChartReduction: Equatable, Sendable {
    public static let defaultMaximumBucketCount = 500

    public let buckets: [HistoryChartBucket]

    public var averageLinePoints: [HistoryChartPoint] {
        buckets.compactMap(\.average)
    }

    /// At most `maximumBucketCount` chronological buckets are emitted. Every raw
    /// failure contributes to its bucket's `failureCount`, and every failure-bearing
    /// bucket retains one concrete representative, so loss is bounded without being
    /// silently erased from the rendered timeline.
    public init(samples: [PingResult], maximumBucketCount: Int = defaultMaximumBucketCount) {
        let chronological = stableChronologicalSamples(samples)
        guard !chronological.isEmpty else {
            buckets = []
            return
        }
        let bucketCount = min(chronological.count, max(1, maximumBucketCount))
        buckets = (0..<bucketCount).map { bucketIndex in
            let lower = bucketIndex * chronological.count / bucketCount
            let upper = (bucketIndex + 1) * chronological.count / bucketCount
            let members = Array(chronological[lower..<upper])
            let validSuccesses: [(sample: PingResult, latency: Double)] = members.compactMap { sample in
                guard sample.isSuccess, let latency = sample.latency?.milliseconds, latency.isFinite else {
                    return nil
                }
                return (sample, latency)
            }
            let timestamp = Date(
                timeIntervalSince1970: members.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(members.count)
            )
            let minimum = validSuccesses.min { $0.latency < $1.latency }.map {
                HistoryChartPoint(timestamp: $0.sample.timestamp, latencyMilliseconds: $0.latency)
            }
            let maximum = validSuccesses.max { $0.latency < $1.latency }.map {
                HistoryChartPoint(timestamp: $0.sample.timestamp, latencyMilliseconds: $0.latency)
            }
            let average = validSuccesses.isEmpty ? nil : HistoryChartPoint(
                timestamp: timestamp,
                latencyMilliseconds: validSuccesses.reduce(0) { $0 + $1.latency } / Double(validSuccesses.count)
            )
            let failures = members.filter { !$0.isSuccess }
            return HistoryChartBucket(
                startDate: members[0].timestamp,
                endDate: members[members.count - 1].timestamp,
                timestamp: timestamp,
                minimum: minimum,
                average: average,
                maximum: maximum,
                failureRepresentative: failures.first,
                failureCount: failures.count,
                sampleCount: members.count,
                sourceRepresentativeID: members.first?.id
            )
        }
    }
}

public struct PingScopeIOSHistoryGraphBucket: Equatable, Sendable {
    public let timestamp: Date
    public let minimumMilliseconds: Double?
    public let averageMilliseconds: Double?
    public let maximumMilliseconds: Double?
    public let failureCount: Int

    public init(bucket: HistoryChartBucket) {
        timestamp = bucket.timestamp
        minimumMilliseconds = bucket.minimum?.latencyMilliseconds
        averageMilliseconds = bucket.average?.latencyMilliseconds
        maximumMilliseconds = bucket.maximum?.latencyMilliseconds
        failureCount = bucket.failureCount
    }
}

public struct PingScopeIOSHistoryExtremaPoint: Equatable, Sendable {
    public let timestamp: Date
    public let minimumMilliseconds: Double
    public let maximumMilliseconds: Double
}

public struct PingScopeIOSHistoryFailureMarker: Equatable, Sendable {
    public let timestamp: Date
    public let failureCount: Int
}

public struct PingScopeIOSHistoryGraphPresentation: Equatable, Sendable {
    public let buckets: [PingScopeIOSHistoryGraphBucket]
    public let averageLineSegments: [[HistoryChartPoint]]
    public let extremaBand: [PingScopeIOSHistoryExtremaPoint]
    public let extremaBandSegments: [[PingScopeIOSHistoryExtremaPoint]]
    public let failureMarkers: [PingScopeIOSHistoryFailureMarker]
    public let scale: LatencyGraphScale

    public init(reduction: HistoryChartReduction) {
        buckets = reduction.buckets.map(PingScopeIOSHistoryGraphBucket.init)
        averageLineSegments = Self.segments(
            reduction.buckets.map { bucket in
                bucket.average.map {
                    HistoryChartPoint(timestamp: bucket.timestamp, latencyMilliseconds: $0.latencyMilliseconds)
                }
            }
        )
        extremaBand = reduction.buckets.compactMap { bucket in
            guard let minimum = bucket.minimum?.latencyMilliseconds,
                  let maximum = bucket.maximum?.latencyMilliseconds else { return nil }
            return PingScopeIOSHistoryExtremaPoint(
                timestamp: bucket.timestamp,
                minimumMilliseconds: minimum,
                maximumMilliseconds: maximum
            )
        }
        extremaBandSegments = Self.segments(
            reduction.buckets.map { bucket in
                guard let minimum = bucket.minimum?.latencyMilliseconds,
                      let maximum = bucket.maximum?.latencyMilliseconds else { return nil }
                return PingScopeIOSHistoryExtremaPoint(
                    timestamp: bucket.timestamp,
                    minimumMilliseconds: minimum,
                    maximumMilliseconds: maximum
                )
            }
        )
        failureMarkers = reduction.buckets.compactMap { bucket in
            guard bucket.failureCount > 0, let failure = bucket.failureRepresentative else { return nil }
            return PingScopeIOSHistoryFailureMarker(timestamp: failure.timestamp, failureCount: bucket.failureCount)
        }
        let maximum = buckets.compactMap(\.maximumMilliseconds).max()
        scale = LatencyGraphScale(maximumMilliseconds: maximum)
    }

    private static func segments<Value>(_ values: [Value?]) -> [[Value]] {
        var result: [[Value]] = []
        var current: [Value] = []
        for value in values {
            if let value {
                current.append(value)
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

public struct PingScopeIOSHistoryStatistic: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PingScopeIOSHistoryEmptyState: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct PingScopeIOSHistorySessionPresentation: Equatable, Sendable, Identifiable {
    public let session: HistorySession
    public let averageText: String
    public let graphData: PingScopeIOSLatencyGraphData

    public var id: Date { session.startDate }
    public var status: HealthStatus { session.status }

    public init(session: HistorySession) {
        self.session = session
        self.averageText = Self.latencyText(session.metrics.averageMilliseconds)
        self.graphData = PingScopeIOSLatencyGraphData(
            samples: session.sparklineSamples,
            startDate: session.startDate,
            endDate: session.endDate
        )
    }

    private static func latencyText(_ milliseconds: Double?) -> String {
        milliseconds.map { "\(Int($0.rounded())) ms" } ?? "--"
    }
}

public struct PingScopeIOSHistoryPresentation: Equatable, Sendable {
    public let range: HistoryRange
    public let sourceSamples: [PingResult]
    public let graphData: PingScopeIOSLatencyGraphData
    public let graphPresentation: PingScopeIOSHistoryGraphPresentation
    public let mapPresentation: HistoryMapPresentation
    public let statistics: [PingScopeIOSHistoryStatistic]
    public let sessions: [PingScopeIOSHistorySessionPresentation]
    public let collectingText: String?
    public let emptyState: PingScopeIOSHistoryEmptyState?

    public init(
        loadResult: PingScopeIOSHistoryLoadResult?,
        thresholds: LatencyThresholds = .defaults
    ) {
        guard let loadResult else {
            let epoch = Date(timeIntervalSince1970: 0)
            self.range = .defaultValue
            self.sourceSamples = []
            self.graphData = PingScopeIOSLatencyGraphData(historyPoints: [], startDate: epoch, endDate: epoch)
            self.graphPresentation = PingScopeIOSHistoryGraphPresentation(reduction: HistoryChartReduction(samples: []))
            self.mapPresentation = HistoryMapPresentation(samples: [])
            self.statistics = Self.statistics(for: HistoryMetrics(samples: []))
            self.sessions = []
            self.collectingText = nil
            self.emptyState = Self.monitoringFirstEmptyState
            return
        }

        let metrics = HistoryMetrics(samples: loadResult.samples)
        self.range = loadResult.range
        self.sourceSamples = loadResult.samples
        self.graphData = PingScopeIOSLatencyGraphData(
            historyPoints: loadResult.chartReduction.averageLinePoints,
            startDate: loadResult.cutoff,
            endDate: loadResult.endingAt
        )
        self.graphPresentation = PingScopeIOSHistoryGraphPresentation(reduction: loadResult.chartReduction)
        self.mapPresentation = HistoryMapPresentation(samples: loadResult.samples)
        self.statistics = Self.statistics(for: metrics)
        self.sessions = HistorySession.sessionize(
            loadResult.samples,
            thresholds: thresholds
        ).map(PingScopeIOSHistorySessionPresentation.init)
        self.collectingText = loadResult.isCollecting
            ? "Collecting data for the full \(loadResult.range.rawValue) window"
            : nil
        self.emptyState = loadResult.samples.isEmpty ? Self.monitoringFirstEmptyState : nil
    }

    private static let monitoringFirstEmptyState = PingScopeIOSHistoryEmptyState(
        title: "Start monitoring to build history",
        message: "Latency trends and sessions will appear here as samples are collected."
    )

    private static func statistics(for metrics: HistoryMetrics) -> [PingScopeIOSHistoryStatistic] {
        [
            PingScopeIOSHistoryStatistic(label: "Avg", value: latencyText(metrics.averageMilliseconds)),
            PingScopeIOSHistoryStatistic(label: "p95", value: latencyText(metrics.p95Milliseconds)),
            PingScopeIOSHistoryStatistic(label: "Loss", value: percentageText(metrics.lossPercent)),
            PingScopeIOSHistoryStatistic(label: "Outages", value: "\(metrics.outageCount)"),
        ]
    }

    private static func latencyText(_ milliseconds: Double?) -> String {
        milliseconds.map { "\(Int($0.rounded())) ms" } ?? "--"
    }

    private static func percentageText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded))%"
        }
        return String(format: "%.1f%%", value)
    }
}

public enum PingScopeIOSHistoryPresentationState: Equatable, Sendable {
    case loading(selection: PingScopeIOSHistorySelection)
    case loaded(selection: PingScopeIOSHistorySelection, presentation: PingScopeIOSHistoryPresentation)

    public var selection: PingScopeIOSHistorySelection {
        switch self {
        case let .loading(selection), let .loaded(selection, _): selection
        }
    }
}

public enum PingScopeIOSResolvedHistoryPresentation: Equatable, Sendable {
    case loading
    case content(PingScopeIOSHistoryPresentation)
}

public enum PingScopeIOSHistoryPresentationResolver {
    public static func resolve(
        _ state: PingScopeIOSHistoryPresentationState,
        for selection: PingScopeIOSHistorySelection
    ) -> PingScopeIOSResolvedHistoryPresentation {
        guard state.selection == selection else { return .loading }
        switch state {
        case .loading: return .loading
        case let .loaded(_, presentation): return .content(presentation)
        }
    }
}

private func stableChronologicalSamples(_ samples: [PingResult]) -> [PingResult] {
    samples.enumerated().sorted { lhs, rhs in
        if lhs.element.timestamp == rhs.element.timestamp {
            return lhs.offset < rhs.offset
        }
        return lhs.element.timestamp < rhs.element.timestamp
    }.map(\.element)
}

private func boundedSamples(_ samples: [PingResult], limit: Int) -> [PingResult] {
    guard limit > 0, samples.count > limit else { return limit > 0 ? samples : [] }
    guard limit > 1 else { return [samples[0]] }
    return (0..<limit).map { index in
        samples[index * (samples.count - 1) / (limit - 1)]
    }
}

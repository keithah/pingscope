import Foundation
import PingScopeCore

public struct HistoryNetworkKey: Hashable, Sendable {
    public static let unknown = HistoryNetworkKey(interface: nil, name: nil)

    public let interface: String?
    public let name: String?

    public init(interface: String?, name: String?) {
        self.interface = NetworkInterfaceNormalizer.normalize(interface)
        self.name = Self.nonempty(name)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct HistoryNetworkGroup: Equatable, Sendable, Identifiable {
    public let key: HistoryNetworkKey
    public let displayLabel: String
    public let interface: String?
    public let sampleCount: Int
    public let firstSeen: Date
    public let lastSeen: Date
    public let metrics: HistoryMetrics
    public let samples: [PingResult]
    public let hasVPN: Bool

    public var id: HistoryNetworkKey { key }
}

public struct HistoryNetworkBreakdown: Equatable, Sendable {
    public let groups: [HistoryNetworkGroup]

    public init(samples: [PingResult]) {
        self.init(accumulating: samples)
    }

    public init<S: Sequence>(accumulating samples: S) where S.Element == PingResult {
        var accumulator = HistoryNetworkBreakdownAccumulator()
        for sample in samples {
            accumulator.append(sample)
        }
        groups = accumulator.groups.map { key, accumulated in
            HistoryNetworkGroup(
                key: key,
                displayLabel: key.name
                    ?? key.interface.map(NetworkInterfaceNormalizer.displayName(for:))
                    ?? "Unknown",
                interface: key.interface,
                sampleCount: accumulated.samples.count,
                firstSeen: accumulated.firstSeen,
                lastSeen: accumulated.lastSeen,
                metrics: HistoryMetrics(samples: accumulated.samples),
                samples: accumulated.samples,
                hasVPN: accumulated.hasVPN
            )
        }.sorted(by: Self.isOrderedBefore)
    }

    private static func isOrderedBefore(_ lhs: HistoryNetworkGroup, _ rhs: HistoryNetworkGroup) -> Bool {
        if lhs.metrics.uptimePercent != rhs.metrics.uptimePercent {
            return lhs.metrics.uptimePercent < rhs.metrics.uptimePercent
        }
        if lhs.sampleCount != rhs.sampleCount {
            return lhs.sampleCount > rhs.sampleCount
        }
        let lhsLabel = lhs.displayLabel.lowercased()
        let rhsLabel = rhs.displayLabel.lowercased()
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }
        if lhs.displayLabel != rhs.displayLabel {
            return lhs.displayLabel < rhs.displayLabel
        }
        return (lhs.interface ?? "") < (rhs.interface ?? "")
    }
}

private struct HistoryNetworkBreakdownAccumulator {
    struct Group {
        var samples: [PingResult]
        var firstSeen: Date
        var lastSeen: Date
        var hasVPN: Bool

        mutating func append(_ sample: PingResult) {
            samples.append(sample)
            firstSeen = min(firstSeen, sample.timestamp)
            lastSeen = max(lastSeen, sample.timestamp)
            hasVPN = hasVPN || sample.isVPN
        }
    }

    var groups: [HistoryNetworkKey: Group] = [:]

    mutating func append(_ sample: PingResult) {
        let key = HistoryNetworkKey(interface: sample.networkInterface, name: sample.networkName)
        groups[key, default: Group(
            samples: [],
            firstSeen: sample.timestamp,
            lastSeen: sample.timestamp,
            hasVPN: false
        )].append(sample)
    }
}

public enum HistoryNetworkSelection: Equatable, Hashable, Sendable {
    case all
    case network(HistoryNetworkKey)
}

public struct HistoryNetworkCardPresentation: Equatable, Sendable, Identifiable {
    public let key: HistoryNetworkKey
    public let label: String
    public let interface: String?
    public let interfaceLabel: String
    public let systemImage: String
    public let sampleCount: Int
    public let sampleCountText: String
    public let averageText: String
    public let p95Text: String
    public let lossText: String
    public let uptimeText: String
    public let status: HealthStatus
    public let hasVPN: Bool
    public let sparklineSamples: [PingResult]

    public var id: HistoryNetworkKey { key }

    init(group: HistoryNetworkGroup, thresholds: LatencyThresholds) {
        key = group.key
        label = group.displayLabel
        interface = group.interface
        interfaceLabel = group.interface.map(NetworkInterfaceNormalizer.displayName(for:)) ?? "Unknown"
        systemImage = switch group.interface {
        case "wifi": "wifi"
        case "cellular": "antenna.radiowaves.left.and.right"
        case "wired": "cable.connector"
        case "other": "network"
        default: "questionmark.circle"
        }
        sampleCount = group.sampleCount
        sampleCountText = "\(group.sampleCount) \(group.sampleCount == 1 ? "sample" : "samples")"
        averageText = Self.latencyText(group.metrics.averageMilliseconds)
        p95Text = Self.latencyText(group.metrics.p95Milliseconds)
        lossText = Self.percentageText(group.metrics.lossPercent)
        uptimeText = Self.percentageText(group.metrics.uptimePercent)
        status = if group.metrics.outageCount > 0 {
            .down
        } else if (group.metrics.maximumMilliseconds ?? 0) >= thresholds.degradedMilliseconds {
            .degraded
        } else {
            .healthy
        }
        hasVPN = group.hasVPN
        sparklineSamples = Self.boundedSamples(group.samples, limit: 60)
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

    private static func boundedSamples(_ samples: [PingResult], limit: Int) -> [PingResult] {
        guard samples.count > limit, limit > 1 else { return samples }
        return (0..<limit).map { index in
            samples[index * (samples.count - 1) / (limit - 1)]
        }
    }
}

public struct HistoryNetworkPresentation: Equatable, Sendable {
    public let cards: [HistoryNetworkCardPresentation]
    public let selection: HistoryNetworkSelection
    public let selectedSamples: [PingResult]
    public let selectedLabel: String?

    public init(
        samples: [PingResult],
        selection: HistoryNetworkSelection = .all,
        thresholds: LatencyThresholds = .defaults
    ) {
        let breakdown = HistoryNetworkBreakdown(samples: samples)
        cards = breakdown.groups.map { HistoryNetworkCardPresentation(group: $0, thresholds: thresholds) }
        self.selection = selection
        switch selection {
        case .all:
            selectedSamples = samples
            selectedLabel = nil
        case let .network(key):
            let group = breakdown.groups.first { $0.key == key }
            selectedSamples = group?.samples ?? []
            selectedLabel = group?.displayLabel
        }
    }
}

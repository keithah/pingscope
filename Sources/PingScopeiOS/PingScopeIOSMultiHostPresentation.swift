import Foundation
import PingScopeCore

public enum PingScopeIOSLatencySampleReducer {
    public static let defaultLimit = 12

    public static func reduce(_ results: [PingResult], limit: Int) -> [PingResult] {
        let usableResults = results.filter(\.isSuccess)
        guard limit > 0, !usableResults.isEmpty else { return [] }
        guard usableResults.count > limit else { return usableResults }
        guard limit > 1 else { return [usableResults[0]] }

        var reduced: [PingResult] = []
        reduced.reserveCapacity(limit)
        var lastIndex: Int?
        for slot in 0..<limit {
            let position = Double(slot) * Double(usableResults.count - 1) / Double(limit - 1)
            let index = Int(position.rounded())
            if lastIndex != index {
                reduced.append(usableResults[index])
                lastIndex = index
            }
        }
        return reduced
    }
}

public struct PingScopeIOSHostRowSnapshot: Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public let status: HealthStatus
    public let latestLatencyMilliseconds: Double?
    public let samples: [PingResult]
    public let isStale: Bool
    public let isDefaultGateway: Bool
    public let degradedThresholdMilliseconds: Double

    public var reducedSamples: [PingResult] { samples }

    public var latencyText: String {
        Self.latencyText(for: latestLatencyMilliseconds)
    }

    fileprivate static func latencyText(for latency: Double?) -> String {
        guard let latency, latency.isFinite else { return "--ms" }
        let rounded = max(latency, 0).rounded()
        guard rounded < Double(Int.max) else { return "--ms" }
        return "\(Int(rounded))ms"
    }

    public var formattedLatency: String { latencyText }

    fileprivate init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: HealthStatus,
        latestLatencyMilliseconds: Double?,
        samples: [PingResult],
        isStale: Bool,
        isDefaultGateway: Bool = false,
        degradedThresholdMilliseconds: Double = LatencyThresholds.defaults.degradedMilliseconds
    ) {
        self.hostID = hostID
        self.displayName = displayName
        self.endpointCaption = endpointCaption
        self.status = status
        self.latestLatencyMilliseconds = latestLatencyMilliseconds
        self.samples = samples
        self.isStale = isStale
        self.isDefaultGateway = isDefaultGateway
        self.degradedThresholdMilliseconds = degradedThresholdMilliseconds
    }

    public init(
        host: HostConfig,
        health: HostHealth?,
        samples: [PingResult] = [],
        isStale: Bool = false,
        sampleLimit: Int = PingScopeIOSLatencySampleReducer.defaultLimit
    ) {
        self.hostID = host.id
        self.displayName = host.displayName
        self.endpointCaption = "\(host.method.displayName) \(host.address)"
        self.status = health?.status ?? .noData
        self.latestLatencyMilliseconds = health?.latestResult?.latency?.milliseconds
        self.samples = PingScopeIOSLatencySampleReducer.reduce(samples, limit: sampleLimit)
        self.isStale = isStale
        self.isDefaultGateway = host.isDefaultGateway
        self.degradedThresholdMilliseconds = host.thresholds.degradedMilliseconds
    }

    fileprivate func cappedForActivity() -> Self {
        Self(
            hostID: hostID,
            displayName: displayName,
            endpointCaption: endpointCaption,
            status: status,
            latestLatencyMilliseconds: latestLatencyMilliseconds,
            samples: PingScopeIOSLatencySampleReducer.reduce(samples, limit: PingScopeIOSLatencySampleReducer.defaultLimit),
            isStale: isStale,
            isDefaultGateway: isDefaultGateway,
            degradedThresholdMilliseconds: degradedThresholdMilliseconds
        )
    }
}

public struct PingScopeIOSAllHostsRingCell: Identifiable, Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let latencyText: String
    public let ringProgress: Double
    public let status: HealthStatus

    public var id: UUID { hostID }
}

public enum PingScopeIOSAllHostsRingGridPresentation {
    public static func cells(from rows: [PingScopeIOSHostRowSnapshot]) -> [PingScopeIOSAllHostsRingCell] {
        rows.map { row in
            let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row)
            let latency = row.isStale ? nil : row.latestLatencyMilliseconds
            let threshold = max(row.degradedThresholdMilliseconds, 1)
            return PingScopeIOSAllHostsRingCell(
                hostID: row.hostID,
                displayName: presentation.displayName,
                latencyText: presentation.latencyText,
                ringProgress: latency.map { min(max($0 / threshold, 0), 1) } ?? 0,
                status: presentation.displayStatus
            )
        }
    }

    static func latencyText(for latency: Double?) -> String {
        PingScopeIOSHostRowSnapshot.latencyText(for: latency)
    }
}

struct PingScopeIOSAllHostsRingRowsFingerprint: Hashable {
    struct Row: Hashable {
        let hostID: UUID
        let displayName: String
        let status: String
        let latencyBitPattern: UInt64?
        let isStale: Bool
        let degradedThresholdBitPattern: UInt64
    }

    let rows: [Row]

    init(_ rows: [PingScopeIOSHostRowSnapshot]) {
        self.rows = rows.map { row in
            Row(
                hostID: row.hostID,
                displayName: row.displayName,
                status: row.status.rawValue,
                latencyBitPattern: row.latestLatencyMilliseconds?.bitPattern,
                isStale: row.isStale,
                degradedThresholdBitPattern: row.degradedThresholdMilliseconds.bitPattern
            )
        }
    }
}

@MainActor
final class PingScopeIOSAllHostsRingGridContentMemo {
    private var cache = BoundedMemo<
        PingScopeIOSAllHostsRingRowsFingerprint,
        [PingScopeIOSAllHostsRingCell]
    >(capacity: 1)

    func resolve(
        _ rows: [PingScopeIOSHostRowSnapshot],
        build: ([PingScopeIOSHostRowSnapshot]) -> [PingScopeIOSAllHostsRingCell]
    ) -> [PingScopeIOSAllHostsRingCell] {
        cache.resolve(PingScopeIOSAllHostsRingRowsFingerprint(rows)) {
            build(rows)
        }
    }
}

public enum PingScopeIOSHostScopePresentation {
    public static let activityHostLimit = 3

    public static func aggregateStatus(from rows: [PingScopeIOSHostRowSnapshot]) -> HealthStatus {
        let statuses = rows.map { $0.isStale ? HealthStatus.noData : $0.status }
        if statuses.contains(.down) { return .down }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.healthy) { return .healthy }
        return .noData
    }

    public static func enabledHosts(from hosts: [HostConfig]) -> [HostConfig] {
        hosts.filter(\.isEnabled)
    }

    public static func enabledHosts(from state: PingScopeIOSHostState) -> [HostConfig] {
        enabledHosts(from: state.hosts)
    }

    public static func rows(
        from hosts: [HostConfig],
        healthByHost: [UUID: HostHealth] = [:],
        samplesByHost: [UUID: [PingResult]] = [:],
        staleHostIDs: Set<UUID> = []
    ) -> [PingScopeIOSHostRowSnapshot] {
        enabledHosts(from: hosts).map { host in
            PingScopeIOSHostRowSnapshot(
                host: host,
                health: healthByHost[host.id],
                samples: samplesByHost[host.id] ?? [],
                isStale: staleHostIDs.contains(host.id)
            )
        }
    }

    public static func activityRows(from rows: [PingScopeIOSHostRowSnapshot]) -> [PingScopeIOSHostRowSnapshot] {
        rows.prefix(activityHostLimit).map { $0.cappedForActivity() }
    }

    public static func activityRows(
        from hosts: [HostConfig],
        healthByHost: [UUID: HostHealth] = [:],
        samplesByHost: [UUID: [PingResult]] = [:],
        staleHostIDs: Set<UUID> = []
    ) -> [PingScopeIOSHostRowSnapshot] {
        activityRows(from: rows(
            from: hosts,
            healthByHost: healthByHost,
            samplesByHost: samplesByHost,
            staleHostIDs: staleHostIDs
        ))
    }
}

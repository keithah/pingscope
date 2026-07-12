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

    public var reducedSamples: [PingResult] { samples }

    public var latencyText: String {
        guard let latestLatencyMilliseconds else { return "--ms" }
        return "\(Int(latestLatencyMilliseconds.rounded()))ms"
    }

    public var formattedLatency: String { latencyText }

    fileprivate init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: HealthStatus,
        latestLatencyMilliseconds: Double?,
        samples: [PingResult],
        isStale: Bool
    ) {
        self.hostID = hostID
        self.displayName = displayName
        self.endpointCaption = endpointCaption
        self.status = status
        self.latestLatencyMilliseconds = latestLatencyMilliseconds
        self.samples = samples
        self.isStale = isStale
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
    }

    fileprivate func cappedForActivity() -> Self {
        Self(
            hostID: hostID,
            displayName: displayName,
            endpointCaption: endpointCaption,
            status: status,
            latestLatencyMilliseconds: latestLatencyMilliseconds,
            samples: PingScopeIOSLatencySampleReducer.reduce(samples, limit: PingScopeIOSLatencySampleReducer.defaultLimit),
            isStale: isStale
        )
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

public extension PingScopeIOSDisplayMode {
    func resolvedForHostScope(showsAllHosts: Bool) -> PingScopeIOSDisplayMode {
        showsAllHosts ? .signal : self
    }
}

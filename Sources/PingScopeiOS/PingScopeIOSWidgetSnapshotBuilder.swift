import Foundation
import PingScopeCore

public enum PingScopeIOSWidgetSnapshotBuilder {
    public static let transportSampleLimit = 60

    public static func make(
        savedHosts: [HostConfig],
        liveSnapshots: [LiveMonitorSessionSnapshot],
        cachedRows: [PingScopeIOSHostRowSnapshot] = [],
        cachedSeries: [PingScopeIOSHostGraphSeries] = [],
        rememberedPrimaryHostID: UUID?,
        scope: WidgetMonitoringScope,
        generatedAt: Date,
        isMonitoringActive: Bool,
        includeRecentSamples: Bool = true
    ) -> WidgetSnapshot {
        let hosts = HostConfig.sanitizedHosts(savedHosts).filter(\.isEnabled)
        let liveByHostID = liveSnapshots.reduce(into: [UUID: LiveMonitorSessionSnapshot]()) {
            if $0[$1.host.id] == nil { $0[$1.host.id] = $1 }
        }
        let cachedRowsByHostID = cachedRows.reduce(into: [UUID: PingScopeIOSHostRowSnapshot]()) {
            if $0[$1.hostID] == nil { $0[$1.hostID] = $1 }
        }
        let cachedSeriesByHostID = cachedSeries.reduce(into: [UUID: [PingResult]]()) {
            if $0[$1.hostID] == nil { $0[$1.hostID] = $1.samples }
        }
        let primaryHostID = rememberedPrimaryHostID.flatMap { candidate in
            hosts.contains { $0.id == candidate } ? candidate : nil
        } ?? hosts.first?.id
        let widgetHosts = hosts.map { host in
            WidgetHost(
                id: host.id,
                displayName: host.displayName,
                address: host.address,
                method: host.method,
                port: host.port,
                isPrimary: host.id == primaryHostID,
                displayColor: WidgetHostDisplayColor(
                    resolvedColor: ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
                )
            )
        }
        let health = hosts.map { host in
            if let live = liveByHostID[host.id] {
                return WidgetHostHealth(
                    hostID: host.id,
                    status: live.health.status,
                    latencyMilliseconds: live.health.latestResult?.latency?.milliseconds,
                    consecutiveFailureCount: live.health.consecutiveFailureCount,
                    failureReason: live.health.latestResult?.failureReason,
                    latestResultAt: live.health.latestResult?.timestamp
                )
            }
            if let row = cachedRowsByHostID[host.id] {
                let latestResultAt = (cachedSeriesByHostID[host.id] ?? row.samples)
                    .max { lhs, rhs in lhs.timestamp < rhs.timestamp }?
                    .timestamp
                return WidgetHostHealth(
                    hostID: host.id,
                    status: row.status,
                    latencyMilliseconds: row.latestLatencyMilliseconds,
                    consecutiveFailureCount: 0,
                    failureReason: nil,
                    latestResultAt: latestResultAt
                )
            }
            return WidgetHostHealth(
                hostID: host.id,
                status: .noData,
                latencyMilliseconds: nil,
                consecutiveFailureCount: 0,
                failureReason: nil,
                latestResultAt: nil
            )
        }
        let samplesByHostID = hosts.reduce(into: [UUID: [PingResult]]()) { result, host in
            var samplesByID: [UUID: PingResult] = [:]
            let cachedSamples = cachedSeriesByHostID[host.id] ?? cachedRowsByHostID[host.id]?.samples ?? []
            for sample in cachedSamples where sample.hostID == host.id {
                samplesByID[sample.id] = sample
            }
            for sample in liveByHostID[host.id]?.series.samples ?? [] where sample.hostID == host.id {
                samplesByID[sample.id] = sample
            }
            result[host.id] = samplesByID.values.sorted(by: Self.sampleOrdering)
        }
        let recentSamples = includeRecentSamples
            ? fairSamples(hosts: hosts, samplesByHostID: samplesByHostID).map(WidgetSample.init(result:))
            : []
        return WidgetSnapshot(
            primaryHostID: primaryHostID,
            hosts: widgetHosts,
            health: health,
            recentSamples: recentSamples,
            networkStatus: .connected,
            generatedAt: generatedAt,
            monitoring: WidgetMonitoringContext(isActive: isMonitoringActive, scope: scope)
        )
    }

    private static func fairSamples(
        hosts: [HostConfig],
        samplesByHostID: [UUID: [PingResult]]
    ) -> [PingResult] {
        var positions = hosts.map { (samplesByHostID[$0.id]?.count ?? 0) - 1 }
        var selected: [PingResult] = []
        selected.reserveCapacity(transportSampleLimit)
        while selected.count < transportSampleLimit {
            var appendedInRound = false
            for index in hosts.indices where selected.count < transportSampleLimit {
                guard positions[index] >= 0,
                      let samples = samplesByHostID[hosts[index].id] else { continue }
                selected.append(samples[positions[index]])
                positions[index] -= 1
                appendedInRound = true
            }
            if !appendedInRound { break }
        }
        let hostOrder = Dictionary(uniqueKeysWithValues: hosts.enumerated().map { ($1.id, $0) })
        return selected.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            let lhsOrder = hostOrder[lhs.hostID] ?? .max
            let rhsOrder = hostOrder[rhs.hostID] ?? .max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func sampleOrdering(_ lhs: PingResult, _ rhs: PingResult) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

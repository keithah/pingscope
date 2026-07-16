import Foundation
import PingScopeCore

public struct HistoryIncident: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date?
    public let duration: TimeInterval
    public let sampleCount: Int
    public let worstLatencyMilliseconds: Double?
    public let onsetDiagnosisScope: NetworkPerspectiveDiagnosis.Scope?
    public let onsetFaultTier: NetworkTier?

    public var isOngoing: Bool { endDate == nil }

    public init(
        id: UUID,
        startDate: Date,
        endDate: Date?,
        duration: TimeInterval,
        sampleCount: Int,
        worstLatencyMilliseconds: Double?,
        onsetDiagnosisScope: NetworkPerspectiveDiagnosis.Scope?,
        onsetFaultTier: NetworkTier?
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.sampleCount = sampleCount
        self.worstLatencyMilliseconds = worstLatencyMilliseconds
        self.onsetDiagnosisScope = onsetDiagnosisScope
        self.onsetFaultTier = onsetFaultTier
    }
}

public struct HistoryIncidentLog: Equatable, Sendable {
    public let incidents: [HistoryIncident]

    public init(
        samples: [PingResult],
        endingAt: Date,
        diagnosesBySampleID: [UUID: NetworkPerspectiveDiagnosis] = [:]
    ) {
        let chronological = samples.sorted(by: Self.isChronologicallyOrdered)
        var derived: [HistoryIncident] = []
        var downSamples: [PingResult] = []

        func appendIncident(endingAt endDate: Date?) {
            guard let onset = downSamples.first else { return }
            let diagnosis = diagnosesBySampleID[onset.id]
            let effectiveEnd = endDate ?? endingAt
            derived.append(HistoryIncident(
                id: onset.id,
                startDate: onset.timestamp,
                endDate: endDate,
                duration: max(0, effectiveEnd.timeIntervalSince(onset.timestamp)),
                sampleCount: downSamples.count,
                worstLatencyMilliseconds: downSamples.compactMap { sample in
                    guard let value = sample.latency?.milliseconds, value.isFinite else { return nil }
                    return value
                }.max(),
                onsetDiagnosisScope: diagnosis?.scope,
                onsetFaultTier: diagnosis?.faultTier
            ))
            downSamples.removeAll(keepingCapacity: true)
        }

        for sample in chronological {
            if sample.isSuccess {
                appendIncident(endingAt: sample.timestamp)
            } else {
                downSamples.append(sample)
            }
        }
        appendIncident(endingAt: nil)
        incidents = derived
    }

    /// Derives onset context from the most recent sample for every monitored
    /// host at each failure onset, using Core's shared perspective diagnoser.
    public init(
        samples: [PingResult],
        host: HostConfig,
        allHosts: [HostConfig],
        samplesByHost: [UUID: [PingResult]],
        endingAt: Date
    ) {
        let chronological = samples.sorted(by: Self.isChronologicallyOrdered)
        var previousWasDown = false
        var diagnoses: [UUID: NetworkPerspectiveDiagnosis] = [:]
        let diagnoser = NetworkPerspectiveDiagnoser()
        for sample in chronological {
            let isDown = !sample.isSuccess
            if isDown, !previousWasDown {
                var healthByHost: [UUID: HostHealth] = [:]
                for monitoredHost in allHosts {
                    guard let latest = samplesByHost[monitoredHost.id]?
                        .filter({ $0.timestamp <= sample.timestamp })
                        .max(by: Self.isChronologicallyOrdered) else { continue }
                    var health = HostHealth(hostID: monitoredHost.id, thresholds: monitoredHost.thresholds)
                    health.ingest(latest)
                    healthByHost[monitoredHost.id] = health
                }
                if healthByHost[host.id] != nil {
                    diagnoses[sample.id] = diagnoser.diagnose(hosts: allHosts, healthByHost: healthByHost)
                }
            }
            previousWasDown = isDown
        }
        self.init(samples: samples, endingAt: endingAt, diagnosesBySampleID: diagnoses)
    }

    private static func isChronologicallyOrdered(_ lhs: PingResult, _ rhs: PingResult) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct HistoryWeeklyDigest: Equatable, Sendable {
    public static let windowDuration: TimeInterval = 7 * 24 * 60 * 60

    public let startDate: Date
    public let endDate: Date
    public let monitoredHostCount: Int
    public let hostsWithDataCount: Int
    public let sampleCount: Int
    public let uptimePercent: Double
    public let incidentCount: Int
    public let totalDowntime: TimeInterval
    public let worstHostID: UUID?
    public let worstHostName: String?
    public let averageMilliseconds: Double?
    public let p95Milliseconds: Double?
    public let busiestInterface: String?
    public let busiestInterfaceLabel: String?

    public static func make(
        hosts: [HostConfig],
        samplesByHost: [UUID: [PingResult]],
        endingAt: Date
    ) -> HistoryWeeklyDigest? {
        let startDate = endingAt.addingTimeInterval(-windowDuration)
        let rangedByHost = Dictionary(uniqueKeysWithValues: hosts.map { host in
            let samples = (samplesByHost[host.id] ?? []).filter {
                $0.timestamp >= startDate && $0.timestamp <= endingAt
            }
            return (host.id, samples)
        })
        let allSamples = hosts.flatMap { rangedByHost[$0.id] ?? [] }
        guard !allSamples.isEmpty else { return nil }

        let metrics = HistoryMetrics(samples: allSamples)
        let hostSummaries = hosts.compactMap { host -> (HostConfig, [PingResult], HistoryMetrics)? in
            guard let samples = rangedByHost[host.id], !samples.isEmpty else { return nil }
            return (host, samples, HistoryMetrics(samples: samples))
        }
        let worstHost = hostSummaries.sorted { lhs, rhs in
            if lhs.2.uptimePercent != rhs.2.uptimePercent {
                return lhs.2.uptimePercent < rhs.2.uptimePercent
            }
            if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
            let comparison = lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }.first

        let incidentLogs = hostSummaries.map {
            HistoryIncidentLog(samples: $0.1, endingAt: endingAt)
        }
        let incidents = incidentLogs.flatMap(\.incidents)
        let busiestNetwork = HistoryNetworkBreakdown(samples: allSamples).groups.sorted { lhs, rhs in
            if lhs.sampleCount != rhs.sampleCount { return lhs.sampleCount > rhs.sampleCount }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }.first

        return HistoryWeeklyDigest(
            startDate: startDate,
            endDate: endingAt,
            monitoredHostCount: hosts.count,
            hostsWithDataCount: hostSummaries.count,
            sampleCount: allSamples.count,
            uptimePercent: metrics.uptimePercent,
            incidentCount: incidents.count,
            totalDowntime: incidents.reduce(0) { $0 + $1.duration },
            worstHostID: worstHost?.0.id,
            worstHostName: worstHost?.0.displayName,
            averageMilliseconds: metrics.averageMilliseconds,
            p95Milliseconds: metrics.p95Milliseconds,
            busiestInterface: busiestNetwork?.interface,
            busiestInterfaceLabel: busiestNetwork?.interface.map(NetworkInterfaceNormalizer.displayName(for:))
        )
    }

    public init(
        startDate: Date,
        endDate: Date,
        monitoredHostCount: Int,
        hostsWithDataCount: Int,
        sampleCount: Int,
        uptimePercent: Double,
        incidentCount: Int,
        totalDowntime: TimeInterval,
        worstHostID: UUID?,
        worstHostName: String?,
        averageMilliseconds: Double?,
        p95Milliseconds: Double?,
        busiestInterface: String?,
        busiestInterfaceLabel: String?
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.monitoredHostCount = monitoredHostCount
        self.hostsWithDataCount = hostsWithDataCount
        self.sampleCount = sampleCount
        self.uptimePercent = uptimePercent
        self.incidentCount = incidentCount
        self.totalDowntime = totalDowntime
        self.worstHostID = worstHostID
        self.worstHostName = worstHostName
        self.averageMilliseconds = averageMilliseconds
        self.p95Milliseconds = p95Milliseconds
        self.busiestInterface = busiestInterface
        self.busiestInterfaceLabel = busiestInterfaceLabel
    }
}

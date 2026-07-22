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
        let chronologicalByHost = samplesByHost.mapValues {
            $0.sorted(by: Self.isChronologicallyOrdered)
        }
        var previousWasDown = false
        var diagnoses: [UUID: NetworkPerspectiveDiagnosis] = [:]
        let diagnoser = NetworkPerspectiveDiagnoser()
        for sample in chronological {
            let isDown = !sample.isSuccess
            if isDown, !previousWasDown {
                var healthByHost: [UUID: HostHealth] = [:]
                for monitoredHost in allHosts {
                    guard let hostSamples = chronologicalByHost[monitoredHost.id],
                          let latest = Self.latestSample(in: hostSamples, through: sample.timestamp) else { continue }
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

    private static func latestSample(in samples: [PingResult], through timestamp: Date) -> PingResult? {
        var lowerBound = 0
        var upperBound = samples.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if samples[middle].timestamp <= timestamp {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound > 0 else { return nil }
        return samples[lowerBound - 1]
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
        let worstHost = hostSummaries.min { lhs, rhs in
            if lhs.2.uptimePercent != rhs.2.uptimePercent {
                return lhs.2.uptimePercent < rhs.2.uptimePercent
            }
            if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
            let comparison = lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }

        let incidentLogs = hostSummaries.map {
            HistoryIncidentLog(samples: $0.1, endingAt: endingAt)
        }
        let incidents = incidentLogs.flatMap(\.incidents)
        let busiestNetwork = HistoryNetworkBreakdown(samples: allSamples).groups.min { lhs, rhs in
            if lhs.sampleCount != rhs.sampleCount { return lhs.sampleCount > rhs.sampleCount }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }

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

    public static func make(
        hosts: [HostConfig],
        samples: [HistoryWeeklyDigestSample],
        endingAt: Date
    ) -> HistoryWeeklyDigest? {
        let startDate = endingAt.addingTimeInterval(-windowDuration)
        let includedHostIDs = Set(hosts.map(\.id))
        var samplesByHost: [UUID: [HistoryWeeklyDigestSample]] = [:]
        for sample in samples where includedHostIDs.contains(sample.hostID)
            && sample.timestamp >= startDate && sample.timestamp <= endingAt {
            samplesByHost[sample.hostID, default: []].append(sample)
        }

        var metrics = WeeklyDigestMetricAccumulator()
        var hostSummaries: [WeeklyDigestHostSummary] = []
        var incidentCount = 0
        var totalDowntime: TimeInterval = 0
        var networkCounts: [HistoryNetworkKey: Int] = [:]

        for host in hosts {
            guard let hostSamples = samplesByHost[host.id], !hostSamples.isEmpty else { continue }
            var hostMetrics = WeeklyDigestMetricAccumulator()
            for sample in hostSamples {
                metrics.append(sample)
                hostMetrics.append(sample)
                let networkKey = HistoryNetworkKey(
                    interface: sample.networkInterface,
                    name: sample.networkName
                )
                networkCounts[networkKey, default: 0] += 1
            }
            let incidentSummary = WeeklyDigestIncidentSummary(
                samples: hostSamples,
                endingAt: endingAt
            )
            incidentCount += incidentSummary.count
            totalDowntime += incidentSummary.totalDowntime
            hostSummaries.append(WeeklyDigestHostSummary(
                host: host,
                sampleCount: hostSamples.count,
                uptimePercent: hostMetrics.uptimePercent
            ))
        }
        guard metrics.sampleCount > 0 else { return nil }

        let worstHost = hostSummaries.min(by: WeeklyDigestHostSummary.isOrderedBefore)
        let busiestNetwork = networkCounts.map { key, count in
            WeeklyDigestNetworkSummary(key: key, sampleCount: count)
        }.min(by: WeeklyDigestNetworkSummary.isOrderedBefore)

        return HistoryWeeklyDigest(
            startDate: startDate,
            endDate: endingAt,
            monitoredHostCount: hosts.count,
            hostsWithDataCount: hostSummaries.count,
            sampleCount: metrics.sampleCount,
            uptimePercent: metrics.uptimePercent,
            incidentCount: incidentCount,
            totalDowntime: totalDowntime,
            worstHostID: worstHost?.host.id,
            worstHostName: worstHost?.host.displayName,
            averageMilliseconds: metrics.averageMilliseconds,
            p95Milliseconds: metrics.p95Milliseconds,
            busiestInterface: busiestNetwork?.key.interface,
            busiestInterfaceLabel: busiestNetwork?.key.interface.map(NetworkInterfaceNormalizer.displayName(for:))
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

private struct WeeklyDigestMetricAccumulator {
    private(set) var sampleCount = 0
    private var receivedCount = 0
    private var latencyTotal = 0.0
    private var lossTotal = 0.0
    private var successfulLatencies: [Double] = []

    mutating func append(_ sample: HistoryWeeklyDigestSample) {
        sampleCount += 1
        if let latency = sample.latencyMilliseconds {
            receivedCount += 1
            latencyTotal += latency
        }
        if let override = sample.lossFractionOverride {
            lossTotal += min(1, max(0, override))
        } else {
            lossTotal += sample.isSuccess ? 0 : 1
        }
        if sample.isSuccess, let latency = sample.latencyMilliseconds, latency.isFinite {
            successfulLatencies.append(latency)
        }
    }

    var uptimePercent: Double {
        max(0, 100 - (sampleCount == 0 ? 0 : lossTotal / Double(sampleCount) * 100))
    }

    var averageMilliseconds: Double? {
        receivedCount == 0 ? nil : latencyTotal / Double(receivedCount)
    }

    var p95Milliseconds: Double? {
        guard !successfulLatencies.isEmpty else { return nil }
        let sorted = successfulLatencies.sorted()
        let nearestRank = Int(ceil(0.95 * Double(sorted.count)))
        return sorted[nearestRank - 1]
    }
}

private struct WeeklyDigestIncidentSummary {
    let count: Int
    let totalDowntime: TimeInterval

    init(samples: [HistoryWeeklyDigestSample], endingAt: Date) {
        let chronological = samples.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var onset: Date?
        var derivedCount = 0
        var downtime: TimeInterval = 0
        for sample in chronological {
            if sample.isSuccess {
                if let onset {
                    derivedCount += 1
                    downtime += max(0, sample.timestamp.timeIntervalSince(onset))
                }
                onset = nil
            } else if onset == nil {
                onset = sample.timestamp
            }
        }
        if let onset {
            derivedCount += 1
            downtime += max(0, endingAt.timeIntervalSince(onset))
        }
        count = derivedCount
        totalDowntime = downtime
    }
}

private struct WeeklyDigestHostSummary {
    let host: HostConfig
    let sampleCount: Int
    let uptimePercent: Double

    static func isOrderedBefore(_ lhs: WeeklyDigestHostSummary, _ rhs: WeeklyDigestHostSummary) -> Bool {
        if lhs.uptimePercent != rhs.uptimePercent { return lhs.uptimePercent < rhs.uptimePercent }
        if lhs.sampleCount != rhs.sampleCount { return lhs.sampleCount > rhs.sampleCount }
        let comparison = lhs.host.displayName.localizedCaseInsensitiveCompare(rhs.host.displayName)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.host.id.uuidString < rhs.host.id.uuidString
    }
}

private struct WeeklyDigestNetworkSummary {
    let key: HistoryNetworkKey
    let sampleCount: Int

    var displayLabel: String {
        key.name ?? key.interface.map(NetworkInterfaceNormalizer.displayName(for:)) ?? "Unknown"
    }

    static func isOrderedBefore(_ lhs: WeeklyDigestNetworkSummary, _ rhs: WeeklyDigestNetworkSummary) -> Bool {
        if lhs.sampleCount != rhs.sampleCount { return lhs.sampleCount > rhs.sampleCount }
        return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
    }
}

public actor HistoryWeeklyDigestLoader {
    private struct HostIdentity: Hashable, Sendable {
        let id: UUID
        let displayName: String
    }

    private struct CacheKey: Hashable, Sendable {
        let hosts: [HostIdentity]
        let revision: UInt64
        let mutationRevision: UInt64
        let endingAt: Date
    }

    private struct RequestIdentity: Hashable, Sendable {
        let hosts: [HostIdentity]
        let endingAt: Date
    }

    private struct CacheEntry: Sendable {
        let digest: HistoryWeeklyDigest?
        let samples: [HistoryWeeklyDigestSample]
        let coveredSince: Date
        let coveredThrough: Date
    }

    private struct LoadResult: Sendable {
        let digest: HistoryWeeklyDigest?
        let samples: [HistoryWeeklyDigestSample]
        let since: Date
        let through: Date
    }

    private struct QueryPlan: Sendable {
        let store: any PingHistoryStore
        let hosts: [HostConfig]
        let hostIDs: [UUID]
        let querySince: Date
        let queryThrough: Date
        let baseSamples: [HistoryWeeklyDigestSample]
        let coveredSince: Date
    }

    private struct InFlight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<HistoryWeeklyDigest?, Never>]
    }

    private struct Pending {
        let plan: QueryPlan
        var waiters: [UUID: CheckedContinuation<HistoryWeeklyDigest?, Never>]
    }

    private let capacity: Int
    private var cache: [CacheKey: CacheEntry] = [:]
    private var recency: [CacheKey] = []
    private var inFlight: [CacheKey: InFlight] = [:]
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var pending: [CacheKey: Pending] = [:]
    private var pendingOrder: [CacheKey] = []
    private var preparingRequests: [RequestIdentity: Int] = [:]
    private var reservations: [UUID: RequestIdentity] = [:]

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    func activeWaiterCount() -> Int {
        inFlight.values.reduce(0) { $0 + $1.waiters.count }
            + pending.values.reduce(0) { $0 + $1.waiters.count }
    }

    public func load(
        store: any PingHistoryStore,
        hosts: [HostConfig],
        endingAt: Date
    ) async -> HistoryWeeklyDigest? {
        let enabledHosts = hosts.filter(\.isEnabled)
        guard !enabledHosts.isEmpty else { return nil }
        let identities = enabledHosts.map {
            HostIdentity(id: $0.id, displayName: $0.displayName)
        }.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.displayName < rhs.displayName
        }
        let requestIdentity = RequestIdentity(hosts: identities, endingAt: endingAt)
        let reservationID = UUID()
        reservations[reservationID] = requestIdentity
        preparingRequests[requestIdentity, default: 0] += 1
        return await withTaskCancellationHandler {
            await loadReserved(
                reservationID: reservationID,
                store: store,
                enabledHosts: enabledHosts,
                identities: identities,
                endingAt: endingAt
            )
        } onCancel: {
            Task { await self.releaseReservation(reservationID) }
        }
    }

    private func loadReserved(
        reservationID: UUID,
        store: any PingHistoryStore,
        enabledHosts: [HostConfig],
        identities: [HostIdentity],
        endingAt: Date
    ) async -> HistoryWeeklyDigest? {
        let revision = await store.historyRevision()
        let mutationRevision = await store.historyMutationRevision()
        guard !Task.isCancelled else {
            releaseReservation(reservationID)
            return nil
        }
        let key = CacheKey(
            hosts: identities,
            revision: revision,
            mutationRevision: mutationRevision,
            endingAt: endingAt
        )
        if let cached = cache[key] {
            touch(key)
            releaseReservation(reservationID)
            return cached.digest
        }

        let cutoff = endingAt.addingTimeInterval(-HistoryWeeklyDigest.windowDuration)
        let compatibleEntries = cache.filter { cachedKey, entry in
            cachedKey.hosts == identities
                && cachedKey.mutationRevision == mutationRevision
                && entry.coveredSince <= cutoff
        }
        if let covering = compatibleEntries.first(where: { _, entry in
            entry.coveredThrough >= endingAt
        }) {
            touch(covering.key)
            let digest = HistoryWeeklyDigest.make(
                hosts: enabledHosts,
                samples: covering.value.samples,
                endingAt: endingAt
            )
            insert(CacheEntry(
                digest: digest,
                samples: covering.value.samples,
                coveredSince: covering.value.coveredSince,
                coveredThrough: covering.value.coveredThrough
            ), for: key)
            releaseReservation(reservationID)
            return digest
        }

        let tailEntry = compatibleEntries
            .filter { $0.value.coveredThrough < endingAt }
            .max { $0.value.coveredThrough < $1.value.coveredThrough }
        if let tailEntry {
            touch(tailEntry.key)
        }
        let plan = QueryPlan(
            store: store,
            hosts: enabledHosts,
            hostIDs: enabledHosts.map(\.id),
            querySince: tailEntry?.value.coveredThrough ?? cutoff,
            queryThrough: endingAt,
            baseSamples: tailEntry?.value.samples ?? [],
            coveredSince: tailEntry?.value.coveredSince ?? cutoff
        )
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueue(
                    continuation,
                    waiterID: waiterID,
                    key: key,
                    plan: plan
                )
                releaseReservation(reservationID)
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, for: key) }
        }
    }

    private func enqueue(
        _ continuation: CheckedContinuation<HistoryWeeklyDigest?, Never>,
        waiterID: UUID,
        key: CacheKey,
        plan: QueryPlan
    ) {
        if let cached = cache[key] {
            touch(key)
            continuation.resume(returning: cached.digest)
        } else if var flight = inFlight[key] {
            flight.waiters[waiterID] = continuation
            inFlight[key] = flight
        } else if var queued = pending[key] {
            queued.waiters[waiterID] = continuation
            pending[key] = queued
        } else if activeTasks.count < capacity {
            startFlight(
                key: key,
                plan: plan,
                waiters: [waiterID: continuation]
            )
        } else {
            pending[key] = Pending(plan: plan, waiters: [waiterID: continuation])
            pendingOrder.append(key)
        }
    }

    private func startFlight(
        key: CacheKey,
        plan: QueryPlan,
        waiters: [UUID: CheckedContinuation<HistoryWeeklyDigest?, Never>]
    ) {
        let flightID = UUID()
        let task = Task.detached(priority: .userInitiated) {
            let queried = plan.store.weeklyDigestSampleStream(
                hostIDs: plan.hostIDs,
                since: plan.querySince,
                through: plan.queryThrough
            )
            var samplesByID = Dictionary(uniqueKeysWithValues: plan.baseSamples.map { ($0.id, $0) })
            for await sample in queried {
                samplesByID[sample.id] = sample
            }
            let samples = samplesByID.values.sorted(by: Self.isSampleOrderedBefore)
            let result = LoadResult(
                digest: HistoryWeeklyDigest.make(
                    hosts: plan.hosts,
                    samples: samples,
                    endingAt: plan.queryThrough
                ),
                samples: samples,
                since: plan.coveredSince,
                through: plan.queryThrough
            )
            await self.finishFlight(result, for: key, flightID: flightID)
        }
        inFlight[key] = InFlight(id: flightID, task: task, waiters: waiters)
        activeTasks[flightID] = task
    }

    private func finishFlight(_ result: LoadResult, for key: CacheKey, flightID: UUID) {
        guard activeTasks.removeValue(forKey: flightID) != nil else { return }
        if let flight = inFlight[key], flight.id == flightID {
            inFlight[key] = nil
            insert(CacheEntry(
                digest: result.digest,
                samples: result.samples,
                coveredSince: result.since,
                coveredThrough: result.through
            ), for: key)
            flight.waiters.values.forEach { $0.resume(returning: result.digest) }
        }
        startPendingFlights()
    }

    private func cancelWaiter(_ waiterID: UUID, for key: CacheKey) {
        if var flight = inFlight[key], let continuation = flight.waiters.removeValue(forKey: waiterID) {
            let requestIdentity = RequestIdentity(hosts: key.hosts, endingAt: key.endingAt)
            if flight.waiters.isEmpty, preparingRequests[requestIdentity] == nil {
                inFlight[key] = nil
                flight.task.cancel()
            } else {
                inFlight[key] = flight
            }
            continuation.resume(returning: nil)
            return
        }
        if var queued = pending[key], let continuation = queued.waiters.removeValue(forKey: waiterID) {
            if queued.waiters.isEmpty {
                pending[key] = nil
                pendingOrder.removeAll { $0 == key }
            } else {
                pending[key] = queued
            }
            continuation.resume(returning: nil)
        }
    }

    private func releaseReservation(_ reservationID: UUID) {
        guard let requestIdentity = reservations.removeValue(forKey: reservationID),
              let count = preparingRequests[requestIdentity] else { return }
        if count > 1 {
            preparingRequests[requestIdentity] = count - 1
            return
        }
        preparingRequests[requestIdentity] = nil
        let unownedKeys = inFlight.compactMap { key, flight in
            flight.waiters.isEmpty
                && key.hosts == requestIdentity.hosts
                && key.endingAt == requestIdentity.endingAt
                ? key
                : nil
        }
        for key in unownedKeys {
            guard let flight = inFlight.removeValue(forKey: key) else { continue }
            flight.task.cancel()
        }
    }

    private func startPendingFlights() {
        while activeTasks.count < capacity, !pendingOrder.isEmpty {
            let key = pendingOrder.removeFirst()
            guard let queued = pending.removeValue(forKey: key), !queued.waiters.isEmpty else {
                continue
            }
            if let cached = cache[key] {
                queued.waiters.values.forEach { $0.resume(returning: cached.digest) }
            } else {
                startFlight(key: key, plan: queued.plan, waiters: queued.waiters)
            }
        }
    }

    private static func isSampleOrderedBefore(
        _ lhs: HistoryWeeklyDigestSample,
        _ rhs: HistoryWeeklyDigestSample
    ) -> Bool {
        if lhs.hostID != rhs.hostID { return lhs.hostID.uuidString < rhs.hostID.uuidString }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func touch(_ key: CacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func insert(_ entry: CacheEntry, for key: CacheKey) {
        // A newer window supersedes the nearly-identical raw sample array for the
        // same host set. Keeping every revision would retain multiple full weeks.
        let superseded = cache.keys.filter { $0.hosts == key.hosts && $0 != key }
        for oldKey in superseded {
            cache[oldKey] = nil
            recency.removeAll { $0 == oldKey }
        }
        cache[key] = entry
        touch(key)
        while recency.count > capacity {
            cache[recency.removeFirst()] = nil
        }
    }
}

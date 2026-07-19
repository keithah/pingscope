import Foundation
import PingScopeCore
import PingScopeHistoryKit

public protocol PingScopeIOSMultiHostSessionControlling: Sendable {
    func start(duration: MonitorSessionDuration, at date: Date) async
    func stop(reason: MonitorSessionEndReason, at date: Date) async
    func snapshot() async -> LiveMonitorSessionSnapshot
    func nextProbeInterval() async -> Duration
    func nextProbeDeadline() async -> Date
}

public extension PingScopeIOSMultiHostSessionControlling {
    func nextProbeInterval() async -> Duration {
        MonitorSessionPolicy().probeInterval
    }

    func nextProbeDeadline() async -> Date {
        Date().addingTimeInterval((await nextProbeInterval()).seconds)
    }
}

extension LiveMonitorSessionController: PingScopeIOSMultiHostSessionControlling {}

public struct PingScopeIOSAllHostPresentationCache {
    public struct Resolution: Sendable {
        public let rows: [PingScopeIOSHostRowSnapshot]
        public let series: [PingScopeIOSHostGraphSeries]
        public let recomputedHostIDs: [UUID]
        public let reusedHostIDs: [UUID]
        public let hasPresentationChanges: Bool
        public let latestResult: PingResult?

        public func valueIfPresentationChanged<Value>(
            _ build: () -> Value
        ) -> Value? {
            guard hasPresentationChanges else { return nil }
            return build()
        }
    }

    private struct InputKey: Equatable {
        let host: HostConfig
        let health: HostHealth
        let samples: AppendOnlySequenceFingerprint<UUID>
        let isStale: Bool
    }

    private struct Entry {
        let key: InputKey
        let row: PingScopeIOSHostRowSnapshot
        let series: PingScopeIOSHostGraphSeries
        let latestResult: PingResult?
    }

    private var entriesByHostID: [UUID: Entry] = [:]
    private var orderedHostIDs: [UUID] = []

    public init() {}

    public mutating func resolve(_ snapshots: [LiveMonitorSessionSnapshot]) -> Resolution {
        var nextEntries: [UUID: Entry] = [:]
        nextEntries.reserveCapacity(snapshots.count)
        var rows: [PingScopeIOSHostRowSnapshot] = []
        var series: [PingScopeIOSHostGraphSeries] = []
        var recomputedHostIDs: [UUID] = []
        var reusedHostIDs: [UUID] = []
        rows.reserveCapacity(snapshots.count)
        series.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            let isStale = snapshot.session.map { $0.phase() != .live } ?? false
            let key = InputKey(
                host: snapshot.host,
                health: snapshot.health,
                samples: AppendOnlySequenceFingerprint(samples: snapshot.series.samples),
                isStale: isStale
            )
            let entry: Entry
            if let cached = entriesByHostID[snapshot.host.id], cached.key == key {
                entry = cached
                reusedHostIDs.append(snapshot.host.id)
            } else {
                entry = Entry(
                    key: key,
                    row: PingScopeIOSHostRowSnapshot(
                        host: snapshot.host,
                        health: snapshot.health,
                        samples: snapshot.series.samples,
                        isStale: isStale
                    ),
                    series: PingScopeIOSHostGraphSeries(
                        hostID: snapshot.host.id,
                        samples: snapshot.series.samples
                    ),
                    latestResult: snapshot.series.samples.max { $0.timestamp < $1.timestamp }
                )
                recomputedHostIDs.append(snapshot.host.id)
            }
            nextEntries[snapshot.host.id] = entry
            rows.append(entry.row)
            series.append(entry.series)
        }

        let nextOrder = snapshots.map(\.host.id)
        let hasPresentationChanges = nextOrder != orderedHostIDs
            || !recomputedHostIDs.isEmpty
            || nextEntries.count != entriesByHostID.count
        entriesByHostID = nextEntries
        orderedHostIDs = nextOrder
        return Resolution(
            rows: rows,
            series: series,
            recomputedHostIDs: recomputedHostIDs,
            reusedHostIDs: reusedHostIDs,
            hasPresentationChanges: hasPresentationChanges,
            latestResult: PingScopeIOSResourceEfficiency.latestResult(in: series)
        )
    }
}

public protocol PingScopeIOSMultiHostSessionControllerFactory: Sendable {
    func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher,
        measurementObserver: @escaping PingScopeIOSMeasurementObserver
    ) async -> any PingScopeIOSMultiHostSessionControlling
}

public struct DefaultPingScopeIOSMultiHostSessionControllerFactory: PingScopeIOSMultiHostSessionControllerFactory {
    public init() {}

    public func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher,
        measurementObserver: @escaping PingScopeIOSMeasurementObserver
    ) async -> any PingScopeIOSMultiHostSessionControlling {
        LiveMonitorSessionController(
            host: host,
            historyStore: historyStore,
            historySampleEnricher: historySampleEnricher,
            measurementObserver: measurementObserver
        )
    }
}

public struct PingScopeIOSMultiHostSessionState: Equatable, Sendable {
    public var duration: MonitorSessionDuration
    public var startedAt: Date
    public var endedAt: Date?
    public var endReason: MonitorSessionEndReason?

    public init(
        duration: MonitorSessionDuration,
        startedAt: Date,
        endedAt: Date? = nil,
        endReason: MonitorSessionEndReason? = nil
    ) {
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    public var scheduledEndAt: Date? {
        guard let duration = duration.duration else { return nil }
        return startedAt.addingTimeInterval(duration.seconds)
    }

    public func remainingDuration(at date: Date = Date()) -> Duration {
        guard endedAt == nil, let scheduledEndAt else { return .zero }
        return .milliseconds(max(0, scheduledEndAt.timeIntervalSince(date)) * 1_000)
    }

    public func isActive(at date: Date = Date()) -> Bool {
        guard endedAt == nil else { return false }
        guard let scheduledEndAt else { return true }
        return date < scheduledEndAt
    }

    func ending(at date: Date, reason: MonitorSessionEndReason) -> Self {
        var copy = self
        copy.endedAt = date
        copy.endReason = reason
        return copy
    }
}

private actor PingScopeIOSMultiHostLifecycleTransactions {
    private var tail: Task<Void, Never>?

    func perform(_ transaction: @escaping @Sendable () async -> Void) async {
        let previous = tail
        // The detached transaction is intentionally independent of the caller:
        // cancelling one lifecycle caller must not abandon the shared queue.
        let next = Task.detached { [previous, transaction] in
            await previous?.value
            await transaction()
        }
        tail = next
        await next.value
    }
}

public actor PingScopeIOSMultiHostSessionCoordinator {
    private struct ControllerEntry: Sendable {
        let host: HostConfig
        let controller: any PingScopeIOSMultiHostSessionControlling
    }

    private let historyStore: (any PingHistoryStore)?
    private let controllerFactory: any PingScopeIOSMultiHostSessionControllerFactory
    private let now: @Sendable () -> Date
    private let historySampleEnricher: PingScopeIOSHistorySampleEnricher
    private let measurementObserver: PingScopeIOSMeasurementObserver
    private let lifecycleTransactions = PingScopeIOSMultiHostLifecycleTransactions()
    private var controllers: [UUID: ControllerEntry] = [:]
    private var orderedHostIDs: [UUID] = []
    private var aggregateSession: PingScopeIOSMultiHostSessionState?
    private var seriesPreservedForScopeRoundTrip: [UUID: SampleSeries] = [:]
    private var isSuspendedForScopeChange = false

    public init(
        historyStore: (any PingHistoryStore)? = nil,
        controllerFactory: any PingScopeIOSMultiHostSessionControllerFactory = DefaultPingScopeIOSMultiHostSessionControllerFactory(),
        now: @escaping @Sendable () -> Date = { Date() },
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher = { $0 },
        measurementObserver: @escaping PingScopeIOSMeasurementObserver = { _, _, _ in }
    ) {
        self.historyStore = historyStore
        self.controllerFactory = controllerFactory
        self.now = now
        self.historySampleEnricher = historySampleEnricher
        self.measurementObserver = measurementObserver
    }

    public func start(duration: MonitorSessionDuration) async {
        await lifecycleTransactions.perform { [weak self] in
            await self?.startTransaction(duration: duration)
        }
    }

    public func stop(reason: MonitorSessionEndReason = .userStopped) async {
        await lifecycleTransactions.perform { [weak self] in
            await self?.stopTransaction(reason: reason)
        }
    }

    public func suspendForScopeChange() async {
        await lifecycleTransactions.perform { [weak self] in
            await self?.suspendForScopeChangeTransaction()
        }
    }

    public func reconcile(hosts: [HostConfig]) async {
        await lifecycleTransactions.perform { [weak self] in
            await self?.reconcileTransaction(hosts: hosts)
        }
    }

    private func startTransaction(duration: MonitorSessionDuration) async {
        if !isSuspendedForScopeChange {
            seriesPreservedForScopeRoundTrip.removeAll(keepingCapacity: true)
        }
        isSuspendedForScopeChange = false
        let startedAt = now()
        aggregateSession = PingScopeIOSMultiHostSessionState(duration: duration, startedAt: startedAt)
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        await withTaskGroup(of: Void.self) { group in
            for entry in orderedEntries {
                group.addTask {
                    await entry.controller.start(duration: duration, at: startedAt)
                }
            }
        }
    }

    private func stopTransaction(reason: MonitorSessionEndReason) async {
        isSuspendedForScopeChange = false
        seriesPreservedForScopeRoundTrip.removeAll(keepingCapacity: true)
        await stopControllers(reason: reason)
    }

    private func suspendForScopeChangeTransaction() async {
        let snapshots = await orderedSnapshots()
        seriesPreservedForScopeRoundTrip = Dictionary(
            snapshots.map { ($0.host.id, $0.series) },
            uniquingKeysWith: { first, _ in first }
        )
        isSuspendedForScopeChange = true
        await stopControllers(reason: .userStopped)
    }

    private func stopControllers(reason: MonitorSessionEndReason) async {
        let stoppedAt = now()
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        await withTaskGroup(of: Void.self) { group in
            for entry in orderedEntries {
                group.addTask {
                    await entry.controller.stop(reason: reason, at: stoppedAt)
                }
            }
        }
        aggregateSession = aggregateSession?.ending(at: stoppedAt, reason: reason)
    }

    public func session() -> PingScopeIOSMultiHostSessionState? {
        aggregateSession
    }

    /// Returns snapshots in the saved enabled-host order used for lifecycle fan-out.
    public func orderedSnapshots() async -> [LiveMonitorSessionSnapshot] {
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        return await withTaskGroup(of: (Int, LiveMonitorSessionSnapshot).self, returning: [LiveMonitorSessionSnapshot].self) { group in
            for (index, entry) in orderedEntries.enumerated() {
                group.addTask {
                    var snapshot = await entry.controller.snapshot()
                    snapshot.host = snapshot.host.applyingPresentationMetadata(from: entry.host)
                    return (index, snapshot)
                }
            }
            var snapshots = Array<LiveMonitorSessionSnapshot?>(repeating: nil, count: orderedEntries.count)
            for await (index, snapshot) in group {
                snapshots[index] = snapshot
            }
            var resolved = snapshots.compactMap { $0 }
            for index in resolved.indices {
                let hostID = resolved[index].host.id
                guard let preserved = seriesPreservedForScopeRoundTrip[hostID] else { continue }
                let merged = mergePreservedSeries(preserved, with: resolved[index].series)
                resolved[index].series = merged
                seriesPreservedForScopeRoundTrip[hostID] = merged
            }
            return resolved
        }
    }

    /// Returns a keyed lookup for a host ID. Dictionary iteration order is unspecified.
    public func snapshotsByHostID() async -> [UUID: LiveMonitorSessionSnapshot] {
        // Never trap on duplicate IDs, even if an unsanitized host list reaches
        // reconcile; keep the first (saved-order) snapshot for a duplicated ID.
        Dictionary(
            await orderedSnapshots().map { ($0.host.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Returns a keyed host lookup. Dictionary iteration order is unspecified.
    public func snapshots() async -> [UUID: LiveMonitorSessionSnapshot] {
        await snapshotsByHostID()
    }

    public func nextProbeInterval() async -> Duration {
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        guard !orderedEntries.isEmpty else { return MonitorSessionPolicy().probeInterval }
        return await withTaskGroup(of: Duration.self, returning: Duration.self) { group in
            for entry in orderedEntries {
                group.addTask { await entry.controller.nextProbeInterval() }
            }
            var shortest = ProbeIdleBackoffPolicy.maximumInterval
            for await interval in group {
                shortest = min(shortest, interval)
            }
            return shortest
        }
    }

    public func nextProbeDeadline() async -> Date {
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        guard !orderedEntries.isEmpty else {
            return Date().addingTimeInterval(MonitorSessionPolicy().probeInterval.seconds)
        }
        return await withTaskGroup(of: Date.self, returning: Date.self) { group in
            for entry in orderedEntries {
                group.addTask { await entry.controller.nextProbeDeadline() }
            }
            var earliest = Date.distantFuture
            for await deadline in group {
                earliest = min(earliest, deadline)
            }
            return earliest
        }
    }

    private func reconcileTransaction(hosts: [HostConfig]) async {
        var desiredHostIDs = Set<UUID>()
        let enabledHosts = PingScopeIOSHostScopePresentation.enabledHosts(from: hosts).filter {
            desiredHostIDs.insert($0.id).inserted
        }
        let reconciledAt = now()

        for hostID in orderedHostIDs where !desiredHostIDs.contains(hostID) {
            await stopAndRemoveController(hostID: hostID, at: reconciledAt)
        }

        for host in enabledHosts {
            if let entry = controllers[host.id] {
                if entry.host.hasSameProbeConfiguration(as: host) {
                    controllers[host.id] = ControllerEntry(host: host, controller: entry.controller)
                } else {
                    await stopAndRemoveController(hostID: host.id, at: reconciledAt)
                }
            }
            guard controllers[host.id] == nil else { continue }

            let controller = await controllerFactory.makeController(
                for: host,
                historyStore: historyStore,
                historySampleEnricher: historySampleEnricher,
                measurementObserver: measurementObserver
            )
            controllers[host.id] = ControllerEntry(host: host, controller: controller)
            if let aggregateSession, aggregateSession.isActive(at: reconciledAt) {
                await controller.start(duration: aggregateSession.duration, at: aggregateSession.startedAt)
            }
        }

        orderedHostIDs = enabledHosts.map(\.id)
    }

    private func stopAndRemoveController(hostID: UUID, at date: Date) async {
        guard let entry = controllers[hostID] else { return }
        await entry.controller.stop(reason: .userStopped, at: date)
        controllers.removeValue(forKey: hostID)
        seriesPreservedForScopeRoundTrip.removeValue(forKey: hostID)
    }

    private func mergePreservedSeries(_ preserved: SampleSeries, with current: SampleSeries) -> SampleSeries {
        var seenIDs = Set<UUID>()
        let samples = (preserved.samples + current.samples)
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seenIDs.insert($0.id).inserted }
        var merged = SampleSeries(hostID: current.hostID, capacity: current.capacity)
        for sample in samples {
            merged.append(sample)
        }
        return merged
    }
}

private extension HostConfig {
    func applyingPresentationMetadata(from other: HostConfig) -> HostConfig {
        var copy = self
        copy.displayName = other.displayName
        copy.tier = other.tier
        copy.notifications = other.notifications
        return copy
    }

    func hasSameProbeConfiguration(as other: HostConfig) -> Bool {
        address == other.address
            && method == other.method
            && port == other.port
            && interval == other.interval
            && timeout == other.timeout
            && thresholds == other.thresholds
    }
}

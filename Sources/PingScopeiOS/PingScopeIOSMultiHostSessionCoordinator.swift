import Foundation
import PingScopeCore

public protocol PingScopeIOSMultiHostSessionControlling: Sendable {
    func start(duration: MonitorSessionDuration, at date: Date) async
    func stop(reason: MonitorSessionEndReason, at date: Date) async
    func snapshot() async -> LiveMonitorSessionSnapshot
}

extension LiveMonitorSessionController: PingScopeIOSMultiHostSessionControlling {}

public protocol PingScopeIOSMultiHostSessionControllerFactory: Sendable {
    func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher
    ) async -> any PingScopeIOSMultiHostSessionControlling
}

public struct DefaultPingScopeIOSMultiHostSessionControllerFactory: PingScopeIOSMultiHostSessionControllerFactory {
    public init() {}

    public func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher
    ) async -> any PingScopeIOSMultiHostSessionControlling {
        LiveMonitorSessionController(
            host: host,
            historyStore: historyStore,
            historySampleEnricher: historySampleEnricher
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
    private let lifecycleTransactions = PingScopeIOSMultiHostLifecycleTransactions()
    private var controllers: [UUID: ControllerEntry] = [:]
    private var orderedHostIDs: [UUID] = []
    private var aggregateSession: PingScopeIOSMultiHostSessionState?

    public init(
        historyStore: (any PingHistoryStore)? = nil,
        controllerFactory: any PingScopeIOSMultiHostSessionControllerFactory = DefaultPingScopeIOSMultiHostSessionControllerFactory(),
        now: @escaping @Sendable () -> Date = { Date() },
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher = { $0 }
    ) {
        self.historyStore = historyStore
        self.controllerFactory = controllerFactory
        self.now = now
        self.historySampleEnricher = historySampleEnricher
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

    public func reconcile(hosts: [HostConfig]) async {
        await lifecycleTransactions.perform { [weak self] in
            await self?.reconcileTransaction(hosts: hosts)
        }
    }

    private func startTransaction(duration: MonitorSessionDuration) async {
        let startedAt = now()
        aggregateSession = PingScopeIOSMultiHostSessionState(duration: duration, startedAt: startedAt)
        for hostID in orderedHostIDs {
            guard let entry = controllers[hostID] else { continue }
            await entry.controller.start(duration: duration, at: startedAt)
        }
    }

    private func stopTransaction(reason: MonitorSessionEndReason) async {
        let stoppedAt = now()
        for hostID in orderedHostIDs {
            guard let entry = controllers[hostID] else { continue }
            await entry.controller.stop(reason: reason, at: stoppedAt)
        }
        aggregateSession = aggregateSession?.ending(at: stoppedAt, reason: reason)
    }

    public func session() -> PingScopeIOSMultiHostSessionState? {
        aggregateSession
    }

    /// Returns snapshots in the saved enabled-host order used for lifecycle fan-out.
    public func orderedSnapshots() async -> [LiveMonitorSessionSnapshot] {
        let orderedEntries = orderedHostIDs.compactMap { controllers[$0] }
        var snapshots: [LiveMonitorSessionSnapshot] = []
        snapshots.reserveCapacity(orderedEntries.count)
        for entry in orderedEntries {
            var snapshot = await entry.controller.snapshot()
            snapshot.host = snapshot.host.applyingPresentationMetadata(from: entry.host)
            snapshots.append(snapshot)
        }
        return snapshots
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

    private func reconcileTransaction(hosts: [HostConfig]) async {
        let enabledHosts = PingScopeIOSHostScopePresentation.enabledHosts(from: hosts)
        let desiredHostIDs = Set(enabledHosts.map(\.id))
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
                historySampleEnricher: historySampleEnricher
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

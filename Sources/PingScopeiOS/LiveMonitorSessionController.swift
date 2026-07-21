import Foundation
import PingScopeCore
import PingScopeHistoryKit

public typealias PingScopeIOSHistorySampleEnricher = @Sendable (PingResult) -> PingResult
public typealias PingScopeIOSMeasurementObserver = @Sendable (
    _ result: PingResult,
    _ previousStatus: HealthStatus,
    _ currentStatus: HealthStatus
) async -> Void

public enum PingScopeIOSResourceEfficiency {
    /// Preserves the former flattened `max` semantics without allocating a
    /// combined sample array. Individual series are not assumed chronological.
    public static func latestResult(in series: [PingScopeIOSHostGraphSeries]) -> PingResult? {
        series.compactMap { $0.samples.max { $0.timestamp < $1.timestamp } }
            .max { $0.timestamp < $1.timestamp }
    }
}

public enum PingScopeIOSWidgetCheapPublishGate {
    /// Conservatively skips sample construction only when no possible sample
    /// change could make the existing publish policy save this snapshot.
    public static func canSkipSampleConstruction(
        candidateWithoutSamples: WidgetSnapshot,
        previousSnapshot: WidgetSnapshot?,
        lastTimelineReloadAt: Date?,
        policy: WidgetSnapshotPublishPolicy
    ) -> Bool {
        guard let previousSnapshot,
              candidateWithoutSamples.hasSameWidgetState(as: previousSnapshot) else { return false }
        let heartbeatDue = candidateWithoutSamples.generatedAt.timeIntervalSince(previousSnapshot.generatedAt)
            >= policy.heartbeatInterval
        let sampleSaveCouldBeDue = candidateWithoutSamples.generatedAt.timeIntervalSince(
            lastTimelineReloadAt ?? .distantPast
        ) >= policy.timelineReloadInterval
        return !heartbeatDue && !sampleSaveCouldBeDue
    }
}

public enum PingScopeIOSRefreshCadence {
    public static let maximumCountdownRefreshInterval: Duration = .seconds(2)
    public static let inFlightProbePollInterval: Duration = .milliseconds(250)

    public static func interval(
        nextProbeDeadline: Date,
        duration: MonitorSessionDuration,
        now: Date
    ) -> Duration {
        let remainingSeconds = nextProbeDeadline.timeIntervalSince(now)
        let probeAlignedInterval = remainingSeconds > 0
            ? Duration.seconds(remainingSeconds)
            : inFlightProbePollInterval
        guard duration != .continuous else { return probeAlignedInterval }
        return min(probeAlignedInterval, maximumCountdownRefreshInterval)
    }
}

/// Owns the refresh task without allowing the suspended task to retain its
/// owner. The iteration closure returns the absolute-deadline-derived sleep.
@MainActor
public final class PingScopeIOSRefreshLoopDriver {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let sleeper: Sleeper
    private var task: Task<Void, Never>?
    private var generation = 0
    public private(set) var isRunning = false

    public init(sleeper: @escaping Sleeper = { duration in
        try await Task.sleep(for: duration)
    }) {
        self.sleeper = sleeper
    }

    public func start(
        iteration: @escaping @MainActor @Sendable () async -> Duration?
    ) {
        cancel()
        generation += 1
        let taskGeneration = generation
        let sleeper = sleeper
        isRunning = true
        task = Task { @MainActor [weak self] in
            defer { self?.finish(generation: taskGeneration) }
            while !Task.isCancelled {
                guard self != nil else { return }
                guard let interval = await iteration() else { return }
                do {
                    try await sleeper(interval)
                } catch {
                    return
                }
            }
        }
    }

    public func cancel() {
        generation += 1
        isRunning = false
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }

    private func finish(generation taskGeneration: Int) {
        guard generation == taskGeneration else { return }
        isRunning = false
        task = nil
    }
}

public struct LiveMonitorSessionSnapshot: Equatable, Sendable {
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth
    public var series: SampleSeries

    public init(host: HostConfig, session: MonitorSessionState?, health: HostHealth, series: SampleSeries? = nil) {
        self.host = host
        self.session = session
        self.health = health
        self.series = series ?? SampleSeries(hostID: host.id)
    }
}

public actor LiveMonitorSessionController {
    private var host: HostConfig
    private let probeFactory: any ProbeFactory
    private let policy: MonitorSessionPolicy
    private let backgroundRuntimeLimit: Duration?
    private let historyStore: (any PingHistoryStore)?
    private let historyWriter: LiveHistoryWriteBuffer?
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private let historySampleEnricher: PingScopeIOSHistorySampleEnricher
    private let measurementObserver: PingScopeIOSMeasurementObserver
    private var session: MonitorSessionState?
    private var health: HostHealth
    private var series: SampleSeries
    private var loopTask: Task<Void, Never>?
    private var loopGeneration = 0
    private var currentNextProbeInterval: Duration
    private var currentNextProbeDeadline: Date

    /// `clock` paces the probe loop and `now` supplies its wall-clock reads, so
    /// tests can drive the loop deterministically instead of racing real sleeps.
    public init(
        host: HostConfig,
        probeFactory: any ProbeFactory = DefaultProbeFactory(flavor: .appStore),
        policy: MonitorSessionPolicy = MonitorSessionPolicy(),
        backgroundRuntimeLimit: Duration? = nil,
        historyStore: (any PingHistoryStore)? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher = { $0 },
        measurementObserver: @escaping PingScopeIOSMeasurementObserver = { _, _, _ in }
    ) {
        self.host = BuildFlavor.appStore.normalizedHost(host)
        self.probeFactory = probeFactory
        self.policy = policy
        self.backgroundRuntimeLimit = backgroundRuntimeLimit
        self.historyStore = historyStore
        self.historyWriter = historyStore.map { LiveHistoryWriteBuffer(store: $0) }
        self.clock = clock
        self.now = now
        self.historySampleEnricher = historySampleEnricher
        self.measurementObserver = measurementObserver
        self.health = HostHealth(hostID: self.host.id, thresholds: self.host.thresholds)
        self.series = SampleSeries(hostID: self.host.id)
        self.currentNextProbeInterval = policy.probeInterval
        self.currentNextProbeDeadline = now().addingTimeInterval(policy.probeInterval.seconds)
    }

    public func start(duration: MonitorSessionDuration) async {
        await start(duration: duration, at: now())
    }

    public func start(duration: MonitorSessionDuration, at date: Date) async {
        cancelLoop()
        await historyWriter?.flushNow()
        let newSession = MonitorSessionState(
            hostID: host.id,
            duration: duration,
            startedAt: date,
            policy: policy
        )
        session = newSession
        health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        series = SampleSeries(hostID: host.id)
        currentNextProbeInterval = policy.probeInterval
        currentNextProbeDeadline = date
        let generation = loopGeneration
        loopTask = Task {
            await runLoop(startedAt: date, generation: generation)
        }
    }

    public func stop(reason: MonitorSessionEndReason = .userStopped) async {
        await stop(reason: reason, at: now())
    }

    public func stop(reason: MonitorSessionEndReason, at date: Date) async {
        cancelLoop()
        finish(reason: reason, at: date)
        await historyWriter?.flushNow()
    }

    public func snapshot() -> LiveMonitorSessionSnapshot {
        LiveMonitorSessionSnapshot(host: host, session: session, health: health, series: series)
    }

    /// Restores the exact observable controller state captured before a
    /// reconciliation that was superseded while `stop()` was awaiting its
    /// history flush. Monitoring resumes on the preserved session without an
    /// immediate extra probe or resetting accumulated health and samples.
    public func restoreAfterSupersededReconciliation(
        from snapshot: LiveMonitorSessionSnapshot
    ) async {
        cancelLoop()
        host = BuildFlavor.appStore.normalizedHost(snapshot.host)
        session = snapshot.session
        health = snapshot.health
        series = snapshot.series
        let resumeInterval = snapshot.session?.policy.probeInterval ?? policy.probeInterval
        currentNextProbeInterval = resumeInterval
        currentNextProbeDeadline = now().addingTimeInterval(resumeInterval.seconds)
        guard let restoredSession = snapshot.session,
              restoredSession.phase(at: now()) != .ended else {
            return
        }
        let generation = loopGeneration
        loopTask = Task {
            do {
                try await clock.sleep(for: resumeInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await runLoop(startedAt: restoredSession.startedAt, generation: generation)
        }
    }

    /// Applies presentation-only metadata without disturbing the active probe
    /// loop, session accounting, health, or accumulated samples.
    @discardableResult
    public func updatePresentationHost(_ updatedHost: HostConfig) -> Bool {
        guard host.id == updatedHost.id,
              host.isEnabled == updatedHost.isEnabled,
              host.hasSameProbeConfiguration(as: updatedHost) else {
            return false
        }
        host = host.applyingPresentationMetadata(from: updatedHost)
        return true
    }

    public func nextProbeInterval() async -> Duration {
        currentNextProbeInterval
    }

    public func nextProbeDeadline() async -> Date {
        currentNextProbeDeadline
    }

    func historyWriterDiagnosticsForTesting() async -> (
        pendingCount: Int,
        consecutiveFailureCount: Int
    )? {
        await historyWriter?.diagnosticsForTesting()
    }

    private func cancelLoop() {
        loopGeneration += 1
        guard let task = loopTask else { return }
        loopTask = nil
        task.cancel()
    }

    private func runLoop(startedAt: Date, generation: Int) async {
        var idleBackoff = ProbeIdleBackoffTracker()
        while !Task.isCancelled {
            guard generation == loopGeneration else { break }
            let now = now()
            if shouldEndForSelectedDuration(at: now) {
                finish(reason: .completed, at: now)
                break
            }
            if shouldEndForBackgroundRuntime(startedAt: startedAt, at: now) {
                finish(reason: .backgroundRuntimeExpired, at: now)
                break
            }

            let probe = await probeFactory.makeProbe(for: host.method)
            let result = await probe.measure(host)
            guard !Task.isCancelled, generation == loopGeneration else { break }
            let statusTransition = await ingest(result)
            let nextInterval = idleBackoff.interval(
                after: result,
                previousStatus: statusTransition.previous,
                currentStatus: statusTransition.current,
                baseInterval: policy.probeInterval
            )
            currentNextProbeInterval = nextInterval
            currentNextProbeDeadline = self.now().addingTimeInterval(nextInterval.seconds)

            do {
                try await clock.sleep(for: nextInterval)
            } catch {
                break
            }
        }
    }

    private func shouldEndForSelectedDuration(at date: Date) -> Bool {
        guard let session else { return true }
        guard let scheduledEndAt = session.scheduledEndAt else { return false }
        return date >= scheduledEndAt
    }

    private func shouldEndForBackgroundRuntime(startedAt: Date, at date: Date) -> Bool {
        guard let backgroundRuntimeLimit else { return false }
        return date.timeIntervalSince(startedAt) >= backgroundRuntimeLimit.seconds
    }

    private func ingest(_ result: PingResult) async -> (previous: HealthStatus, current: HealthStatus) {
        let previousStatus = health.status
        health.ingest(result)
        let currentStatus = health.status
        series.append(result)
        session = session?.updating(with: result)
        await measurementObserver(result, previousStatus, currentStatus)
        await historyWriter?.append(historySampleEnricher(result))
        return (previousStatus, currentStatus)
    }

    private func finish(reason: MonitorSessionEndReason, at date: Date) {
        session = session?.ending(at: date, reason: reason)
    }
}

private actor LiveHistoryWriteBuffer {
    private let store: any PingHistoryStore
    private let maxBatchSize: Int
    private let flushDelay: Duration
    private var pending: BoundedBuffer<PingResult>
    private var flushTask: Task<Void, Never>?
    private var consecutiveFailureCount = 0
    private var lastFailureLogAt: Date?

    init(
        store: any PingHistoryStore,
        maxBatchSize: Int = 16,
        maxPendingResults: Int = 512,
        flushDelay: Duration = .seconds(2)
    ) {
        self.store = store
        self.maxBatchSize = max(1, maxBatchSize)
        self.pending = BoundedBuffer(capacity: max(self.maxBatchSize, maxPendingResults))
        self.flushDelay = flushDelay
    }

    func append(_ result: PingResult) {
        pending.append(result)
        if pending.count >= maxBatchSize {
            scheduleImmediateFlush()
        } else {
            scheduleDelayedFlush()
        }
    }

    func flushNow() async {
        await cancelFlushTask()
        let pendingBeforeFlush = pending.count
        let completed = await drainAll()
        if !completed, pendingBeforeFlush > 0 {
            NSLog("PingScope iOS history forced flush incomplete pending=\(pending.count)")
        }
    }

    func diagnosticsForTesting() -> (pendingCount: Int, consecutiveFailureCount: Int) {
        (pending.count, consecutiveFailureCount)
    }

    private func scheduleDelayedFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [flushDelay] in
            do {
                try await Task.sleep(for: flushDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await flushScheduled()
        }
    }

    private func scheduleImmediateFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            guard !Task.isCancelled else { return }
            await flushScheduled()
        }
    }

    private func flushScheduled() async {
        await drainOneBatch()
        flushTask = nil
        if pending.count >= maxBatchSize {
            scheduleImmediateFlush()
        } else if !pending.isEmpty {
            scheduleDelayedFlush()
        }
    }

    @discardableResult
    private func drainAll() async -> Bool {
        while !pending.isEmpty {
            guard await drainOneBatch() else { return false }
        }
        return true
    }

    @discardableResult
    private func drainOneBatch() async -> Bool {
        guard !pending.isEmpty else { return true }
        let batch = pending.popPrefix(maxBatchSize)
        do {
            try await store.appendAndWait(batch)
            if consecutiveFailureCount > 0 {
                NSLog("PingScope iOS history writes recovered pending=\(pending.count)")
            }
            consecutiveFailureCount = 0
            lastFailureLogAt = nil
            return true
        } catch {
            pending.prepend(contentsOf: batch)
            consecutiveFailureCount += 1
            logFailureIfNeeded(error)
            await retryBackoff()
            return false
        }
    }

    private func logFailureIfNeeded(_ error: Error) {
        let now = Date()
        if let lastFailureLogAt, now.timeIntervalSince(lastFailureLogAt) < 60 {
            return
        }
        lastFailureLogAt = now
        NSLog("PingScope iOS history write failed failures=\(consecutiveFailureCount) pending=\(pending.count) dropped=\(pending.droppedCount) error=\(String(describing: error))")
    }

    private func retryBackoff() async {
        let exponent = min(consecutiveFailureCount - 1, 5)
        let milliseconds = 250 * (1 << exponent)
        try? await Task.sleep(for: .milliseconds(Double(milliseconds)))
    }

    private func cancelFlushTask() async {
        while let task = flushTask {
            flushTask = nil
            task.cancel()
            await task.value
        }
    }
}

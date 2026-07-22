import Foundation
import PingScopeCore

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
    private let host: HostConfig
    private let probeFactory: any ProbeFactory
    private let policy: MonitorSessionPolicy
    private let backgroundRuntimeLimit: Duration?
    private let historyStore: (any PingHistoryStore)?
    private let historyWriter: LiveHistoryWriteBuffer?
    private let clock: any Clock<Duration>
    private let now: @Sendable () -> Date
    private var session: MonitorSessionState?
    private var health: HostHealth
    private var series: SampleSeries
    private var loopTask: Task<Void, Never>?
    private var loopGeneration = 0
    private var cadenceInputs: CadenceInputs = .default

    /// `clock` paces the probe loop and `now` supplies its wall-clock reads, so
    /// tests can drive the loop deterministically instead of racing real sleeps.
    public init(
        host: HostConfig,
        probeFactory: any ProbeFactory = DefaultProbeFactory(flavor: .appStore),
        policy: MonitorSessionPolicy = MonitorSessionPolicy(),
        backgroundRuntimeLimit: Duration? = nil,
        historyStore: (any PingHistoryStore)? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.host = BuildFlavor.appStore.normalizedHost(host)
        self.probeFactory = probeFactory
        self.policy = policy
        self.backgroundRuntimeLimit = backgroundRuntimeLimit
        self.historyStore = historyStore
        self.historyWriter = historyStore.map { LiveHistoryWriteBuffer(store: $0) }
        self.clock = clock
        self.now = now
        self.health = HostHealth(hostID: self.host.id, thresholds: self.host.thresholds)
        self.series = SampleSeries(hostID: self.host.id)
    }

    public func start(duration: MonitorSessionDuration) async {
        await start(duration: duration, at: now())
    }

    public func setCadenceInputs(_ inputs: CadenceInputs) {
        cadenceInputs = inputs
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

    private func cancelLoop() {
        loopGeneration += 1
        guard let task = loopTask else { return }
        loopTask = nil
        task.cancel()
    }

    private func runLoop(startedAt: Date, generation: Int) async {
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
            await ingest(result)

            do {
                try await clock.sleep(for: cadenceInputs.effectiveInterval(base: policy.probeInterval))
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

    private func ingest(_ result: PingResult) async {
        health.ingest(result)
        series.append(result)
        session = session?.updating(with: result)
        await historyWriter?.append(result)
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

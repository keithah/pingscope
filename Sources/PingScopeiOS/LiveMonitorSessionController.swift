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
    private var session: MonitorSessionState?
    private var health: HostHealth
    private var series: SampleSeries
    private var loopTask: Task<Void, Never>?

    public init(
        host: HostConfig,
        probeFactory: any ProbeFactory = DefaultProbeFactory(flavor: .appStore),
        policy: MonitorSessionPolicy = MonitorSessionPolicy(),
        backgroundRuntimeLimit: Duration? = nil,
        historyStore: (any PingHistoryStore)? = nil
    ) {
        self.host = BuildFlavor.appStore.normalizedHost(host)
        self.probeFactory = probeFactory
        self.policy = policy
        self.backgroundRuntimeLimit = backgroundRuntimeLimit
        self.historyStore = historyStore
        self.historyWriter = historyStore.map { LiveHistoryWriteBuffer(store: $0) }
        self.health = HostHealth(hostID: self.host.id, thresholds: self.host.thresholds)
        self.series = SampleSeries(hostID: self.host.id)
    }

    public func start(duration: MonitorSessionDuration, at date: Date = Date()) async {
        loopTask?.cancel()
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
        loopTask = Task {
            await runLoop(startedAt: date)
        }
    }

    public func stop(reason: MonitorSessionEndReason = .userStopped, at date: Date = Date()) {
        loopTask?.cancel()
        loopTask = nil
        finish(reason: reason, at: date)
        Task {
            await historyWriter?.flushNow()
        }
    }

    public func stop(reason: MonitorSessionEndReason = .userStopped, at date: Date = Date()) async {
        loopTask?.cancel()
        loopTask = nil
        finish(reason: reason, at: date)
        await historyWriter?.flushNow()
    }

    public func snapshot() -> LiveMonitorSessionSnapshot {
        LiveMonitorSessionSnapshot(host: host, session: session, health: health, series: series)
    }

    private func runLoop(startedAt: Date) async {
        while !Task.isCancelled {
            let now = Date()
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
            await ingest(result)

            do {
                try await Task.sleep(for: policy.probeInterval)
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
    private var pending: [PingResult] = []
    private var flushTask: Task<Void, Never>?

    init(store: any PingHistoryStore, maxBatchSize: Int = 16, flushDelay: Duration = .seconds(2)) {
        self.store = store
        self.maxBatchSize = max(1, maxBatchSize)
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
        await drainAll()
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

    private func drainAll() async {
        while !pending.isEmpty {
            await drainOneBatch()
        }
    }

    private func drainOneBatch() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        await store.append(batch)
    }

    private func cancelFlushTask() async {
        while let task = flushTask {
            flushTask = nil
            task.cancel()
            await task.value
        }
    }
}

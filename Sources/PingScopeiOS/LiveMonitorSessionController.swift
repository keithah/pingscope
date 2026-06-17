import Foundation
import PingScopeCore

public struct LiveMonitorSessionSnapshot: Equatable, Sendable {
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth

    public init(host: HostConfig, session: MonitorSessionState?, health: HostHealth) {
        self.host = host
        self.session = session
        self.health = health
    }
}

public actor LiveMonitorSessionController {
    private let host: HostConfig
    private let probeFactory: any ProbeFactory
    private let policy: MonitorSessionPolicy
    private let backgroundRuntimeLimit: Duration?
    private var session: MonitorSessionState?
    private var health: HostHealth
    private var loopTask: Task<Void, Never>?

    public init(
        host: HostConfig,
        probeFactory: any ProbeFactory = DefaultProbeFactory(flavor: .appStore),
        policy: MonitorSessionPolicy = MonitorSessionPolicy(),
        backgroundRuntimeLimit: Duration? = nil
    ) {
        self.host = BuildFlavor.appStore.normalizedHost(host)
        self.probeFactory = probeFactory
        self.policy = policy
        self.backgroundRuntimeLimit = backgroundRuntimeLimit
        self.health = HostHealth(hostID: self.host.id, thresholds: self.host.thresholds)
    }

    public func start(duration: MonitorSessionDuration, at date: Date = Date()) {
        loopTask?.cancel()
        let newSession = MonitorSessionState(
            hostID: host.id,
            duration: duration,
            startedAt: date,
            policy: policy
        )
        session = newSession
        loopTask = Task {
            await runLoop(startedAt: date)
        }
    }

    public func stop(reason: MonitorSessionEndReason = .userStopped, at date: Date = Date()) {
        loopTask?.cancel()
        loopTask = nil
        finish(reason: reason, at: date)
    }

    public func snapshot() -> LiveMonitorSessionSnapshot {
        LiveMonitorSessionSnapshot(host: host, session: session, health: health)
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
            ingest(result)

            do {
                try await Task.sleep(for: policy.probeInterval)
            } catch {
                break
            }
        }
    }

    private func shouldEndForSelectedDuration(at date: Date) -> Bool {
        guard let session else { return true }
        return date >= session.scheduledEndAt
    }

    private func shouldEndForBackgroundRuntime(startedAt: Date, at date: Date) -> Bool {
        guard let backgroundRuntimeLimit else { return false }
        return date.timeIntervalSince(startedAt) >= backgroundRuntimeLimit.seconds
    }

    private func ingest(_ result: PingResult) {
        health.ingest(result)
        session = session?.updating(with: result)
    }

    private func finish(reason: MonitorSessionEndReason, at date: Date) {
        session = session?.ending(at: date, reason: reason)
    }
}

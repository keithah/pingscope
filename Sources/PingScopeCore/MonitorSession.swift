import Foundation

public enum MonitorSessionDuration: String, CaseIterable, Codable, Equatable, Sendable {
    case thirtySeconds
    case oneMinute

    public var duration: Duration {
        switch self {
        case .thirtySeconds: .seconds(30)
        case .oneMinute: .seconds(60)
        }
    }

    public var displayName: String {
        switch self {
        case .thirtySeconds: "30s"
        case .oneMinute: "1m"
        }
    }
}

public enum MonitorSessionPhase: String, Codable, Equatable, Sendable {
    case live
    case stale
    case ended
}

public enum MonitorSessionEndReason: String, Codable, Equatable, Sendable {
    case completed
    case userStopped
    case backgroundRuntimeExpired
}

public struct MonitorSessionPolicy: Codable, Equatable, Sendable {
    public var liveFreshness: Duration
    public var staleAfter: Duration
    public var probeInterval: Duration

    public init(
        liveFreshness: Duration = .seconds(10),
        staleAfter: Duration = .seconds(15),
        probeInterval: Duration = .seconds(2)
    ) {
        self.liveFreshness = liveFreshness
        self.staleAfter = staleAfter
        self.probeInterval = probeInterval
    }
}

public struct MonitorSessionState: Codable, Equatable, Sendable {
    public var hostID: UUID
    public var duration: MonitorSessionDuration
    public var startedAt: Date
    public var endedAt: Date?
    public var endReason: MonitorSessionEndReason?
    public var latestResult: PingResult?
    public var policy: MonitorSessionPolicy

    public init(
        hostID: UUID,
        duration: MonitorSessionDuration,
        startedAt: Date,
        endedAt: Date? = nil,
        endReason: MonitorSessionEndReason? = nil,
        latestResult: PingResult? = nil,
        policy: MonitorSessionPolicy = MonitorSessionPolicy()
    ) {
        self.hostID = hostID
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.latestResult = latestResult
        self.policy = policy
    }

    public var scheduledEndAt: Date {
        startedAt.addingTimeInterval(duration.duration.seconds)
    }

    public func phase(at date: Date = Date()) -> MonitorSessionPhase {
        if let endedAt, date >= endedAt {
            return .ended
        }
        if date >= scheduledEndAt {
            return .ended
        }

        let freshnessAnchor = latestResult?.timestamp ?? startedAt
        if date.timeIntervalSince(freshnessAnchor) > policy.staleAfter.seconds {
            return .stale
        }
        return .live
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        phase(at: date) == .ended
    }

    public func remainingDuration(at date: Date = Date()) -> Duration {
        guard phase(at: date) != .ended else { return .zero }
        let deadline = min(scheduledEndAt, endedAt ?? scheduledEndAt)
        return .milliseconds(max(0, deadline.timeIntervalSince(date)) * 1_000)
    }

    public func updating(with result: PingResult) -> MonitorSessionState {
        var copy = self
        copy.latestResult = result
        return copy
    }

    public func ending(at date: Date = Date(), reason: MonitorSessionEndReason) -> MonitorSessionState {
        var copy = self
        copy.endedAt = date
        copy.endReason = reason
        return copy
    }
}

import Foundation
import PingScopeCore

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

@available(iOS 16.2, *)
public struct PingScopeLiveActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var latencyMilliseconds: Int?
        public var status: HealthStatus
        public var lastUpdatedAt: Date?
        public var remainingSeconds: Int
        public var isStale: Bool
        public var failureMessage: String?

        public init(
            latencyMilliseconds: Int?,
            status: HealthStatus,
            lastUpdatedAt: Date?,
            remainingSeconds: Int,
            isStale: Bool,
            failureMessage: String? = nil
        ) {
            self.latencyMilliseconds = latencyMilliseconds
            self.status = status
            self.lastUpdatedAt = lastUpdatedAt
            self.remainingSeconds = max(0, remainingSeconds)
            self.isStale = isStale
            self.failureMessage = failureMessage
        }

        public init(session: MonitorSessionState, health: HostHealth?, at date: Date = Date()) {
            let latestResult = session.latestResult ?? health?.latestResult
            self.init(
                latencyMilliseconds: latestResult?.latency.map { Int($0.milliseconds.rounded()) },
                status: health?.status ?? .noData,
                lastUpdatedAt: latestResult?.timestamp,
                remainingSeconds: session.duration == .continuous ? 0 : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
                isStale: session.phase(at: date) != .live,
                failureMessage: latestResult?.failureReason?.userMessage
            )
        }
    }

    public var hostID: UUID
    public var hostName: String
    public var address: String
    public var method: PingMethod
    public var duration: MonitorSessionDuration

    public init(host: HostConfig, duration: MonitorSessionDuration) {
        self.hostID = host.id
        self.hostName = host.displayName
        self.address = host.address
        self.method = host.method
        self.duration = duration
    }
}
#endif

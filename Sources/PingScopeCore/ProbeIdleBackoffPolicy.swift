import Foundation

public enum ProbeIdleBackoffPolicy {
    public static let maximumInterval: Duration = .seconds(30)

    public static func interval(
        confirmedDownFailureCount: Int,
        baseInterval: Duration
    ) -> Duration {
        guard confirmedDownFailureCount > 1 else { return baseInterval }
        let exponent = confirmedDownFailureCount - 1
        let capSeconds = max(baseInterval.seconds, maximumInterval.seconds)
        let intervalSeconds = min(baseInterval.seconds * pow(2, Double(exponent)), capSeconds)
        return .seconds(intervalSeconds)
    }
}

public struct ProbeIdleBackoffTracker: Sendable {
    private var confirmedDownFailureCount = 0

    public init() {}

    public mutating func interval(
        after result: PingResult,
        previousStatus: HealthStatus,
        currentStatus: HealthStatus,
        baseInterval: Duration
    ) -> Duration {
        if result.isSuccess {
            confirmedDownFailureCount = 0
        } else if currentStatus == .down {
            confirmedDownFailureCount = previousStatus == .down ? confirmedDownFailureCount + 1 : 1
        } else {
            confirmedDownFailureCount = 0
        }
        return ProbeIdleBackoffPolicy.interval(
            confirmedDownFailureCount: confirmedDownFailureCount,
            baseInterval: baseInterval
        )
    }
}

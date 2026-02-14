import Foundation

enum MenuBarStatus: String, Sendable, Equatable {
    case green
    case yellow
    case red
    case gray
}

struct MenuBarStatusEvaluator: Sendable {
    let healthyUpperBoundMS: Double
    let sustainedFailureThreshold: Int

    init(healthyUpperBoundMS: Double = 80, sustainedFailureThreshold: Int = 3) {
        self.healthyUpperBoundMS = healthyUpperBoundMS
        self.sustainedFailureThreshold = sustainedFailureThreshold
    }

    func evaluate(
        latencyMS: Double?,
        consecutiveFailures: Int,
        hasReceivedAnyResult: Bool,
        isMonitoringActive: Bool
    ) -> MenuBarStatus {
        guard isMonitoringActive else {
            return .gray
        }

        guard hasReceivedAnyResult else {
            return .gray
        }

        if consecutiveFailures >= sustainedFailureThreshold {
            return .red
        }

        guard let latencyMS else {
            return .gray
        }

        if latencyMS <= healthyUpperBoundMS {
            return .green
        }

        return .yellow
    }
}

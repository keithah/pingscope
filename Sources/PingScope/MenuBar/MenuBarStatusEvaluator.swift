import Foundation

enum MenuBarStatus: String, Sendable, Equatable {
    case green
    case yellow
    case red
    case gray
}

struct MenuBarStatusEvaluator: Sendable {
    let sustainedFailureThreshold: Int

    init(sustainedFailureThreshold: Int = 3) {
        self.sustainedFailureThreshold = sustainedFailureThreshold
    }

    func evaluate(
        latencyMS: Double?,
        greenThresholdMS: Double = 80,
        yellowThresholdMS: Double = 150,
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

        let (normalizedGreenThresholdMS, normalizedYellowThresholdMS) = normalizedThresholds(
            greenThresholdMS: greenThresholdMS,
            yellowThresholdMS: yellowThresholdMS
        )

        if latencyMS <= normalizedGreenThresholdMS {
            return .green
        }

        if latencyMS <= normalizedYellowThresholdMS {
            return .yellow
        }

        return .red
    }

    private func normalizedThresholds(greenThresholdMS: Double, yellowThresholdMS: Double) -> (Double, Double) {
        let sanitizedGreenThresholdMS = max(0, greenThresholdMS.isFinite ? greenThresholdMS : 0)
        let sanitizedYellowThresholdMS = max(0, yellowThresholdMS.isFinite ? yellowThresholdMS : sanitizedGreenThresholdMS)

        return (
            min(sanitizedGreenThresholdMS, sanitizedYellowThresholdMS),
            max(sanitizedGreenThresholdMS, sanitizedYellowThresholdMS)
        )
    }
}

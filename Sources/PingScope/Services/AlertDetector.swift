import Foundation

struct AlertDetector: Sendable {
    static func detectNoResponse(result: PingResult, wasDown: Bool) -> AlertType? {
        guard result.latency == nil, wasDown == false else {
            return nil
        }

        return .noResponse
    }

    static func detectRecovery(result: PingResult, wasDown: Bool) -> AlertType? {
        guard result.latency != nil, wasDown == true else {
            return nil
        }

        return .recovery
    }

    static func detectHighLatency(latencyMS: Double, threshold: Double) -> AlertType? {
        latencyMS > threshold ? .highLatency : nil
    }

    static func detectDegradation(
        currentLatencyMS: Double,
        baselineLatencyMS: Double?,
        degradationPercentage: Double
    ) -> AlertType? {
        guard let baselineLatencyMS else {
            return nil
        }

        let multiplier = 1 + (degradationPercentage / 100)
        return currentLatencyMS > (baselineLatencyMS * multiplier) ? .degradation : nil
    }

    static func detectIntermittent(failureCount: Int, threshold: Int) -> AlertType? {
        failureCount >= threshold ? .intermittent : nil
    }

    static func detectNetworkChange(previousGateway: String?, currentGateway: String?) -> AlertType? {
        guard let previousGateway, let currentGateway else {
            return nil
        }

        return previousGateway != currentGateway ? .networkChange : nil
    }

    static func detectInternetLoss(allHostResults: [(host: Host, isUp: Bool)]) -> AlertType? {
        guard !allHostResults.isEmpty else {
            return nil
        }

        return allHostResults.allSatisfy { !$0.isUp } ? .internetLoss : nil
    }

    static func evaluate(
        result: PingResult,
        host: Host,
        isHostUp: Bool,
        state: inout HostAlertState,
        preferences: NotificationPreferences
    ) -> [AlertType] {
        _ = host

        var detected: [AlertType] = []

        let wasDown = state.wasDown
        let isDownNow = (result.latency == nil) || (isHostUp == false)

        if let noResponse = detectNoResponse(result: result, wasDown: wasDown) {
            detected.append(noResponse)
        }

        if let recovery = detectRecovery(result: result, wasDown: wasDown) {
            detected.append(recovery)
        }

        if let latency = result.latency {
            let currentLatencyMS = durationToMilliseconds(latency)

            if let highLatency = detectHighLatency(
                latencyMS: currentLatencyMS,
                threshold: preferences.highLatencyThresholdMS
            ) {
                detected.append(highLatency)
            }

            if let degradation = detectDegradation(
                currentLatencyMS: currentLatencyMS,
                baselineLatencyMS: state.previousLatencyMS,
                degradationPercentage: preferences.degradationPercentage
            ) {
                detected.append(degradation)
            }

            state.recordLatency(currentLatencyMS)
        }

        if isDownNow {
            state.recordFailure()
        } else {
            state.pruneStaleFailures()
        }

        let failures = state.failuresInWindow(windowSize: preferences.intermittentWindowSize)
        if let intermittent = detectIntermittent(
            failureCount: failures,
            threshold: preferences.intermittentFailureCount
        ) {
            detected.append(intermittent)
        }

        state.wasDown = isDownNow
        return detected
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
        let fractionalSeconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return (seconds + fractionalSeconds) * 1000
    }
}

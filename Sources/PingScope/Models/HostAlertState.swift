import Foundation

struct HostAlertState: Sendable {
    var wasDown: Bool
    var previousLatencyMS: Double?
    var recentLatencies: [Double]
    var recentFailures: [Date]
    var lastAlertTimes: [AlertType: Date]

    init(
        wasDown: Bool = false,
        previousLatencyMS: Double? = nil,
        recentLatencies: [Double] = [],
        recentFailures: [Date] = [],
        lastAlertTimes: [AlertType: Date] = [:]
    ) {
        self.wasDown = wasDown
        self.previousLatencyMS = previousLatencyMS
        self.recentLatencies = recentLatencies
        self.recentFailures = recentFailures
        self.lastAlertTimes = lastAlertTimes
    }

    mutating func recordLatency(_ ms: Double, maxWindowSize: Int = 20) {
        recentLatencies.append(ms)
        if recentLatencies.count > maxWindowSize {
            recentLatencies.removeFirst(recentLatencies.count - maxWindowSize)
        }

        if !recentLatencies.isEmpty {
            let average = recentLatencies.reduce(0, +) / Double(recentLatencies.count)
            previousLatencyMS = average
        }
    }

    mutating func recordFailure() {
        recentFailures.append(Date())
        pruneStaleFailures(maxAge: 60)
    }

    func canSendAlert(_ alertType: AlertType, cooldown: TimeInterval) -> Bool {
        guard let lastSent = lastAlertTimes[alertType] else {
            return true
        }

        return Date().timeIntervalSince(lastSent) >= cooldown
    }

    mutating func recordAlertSent(_ alertType: AlertType) {
        lastAlertTimes[alertType] = Date()
    }

    func failuresInWindow(windowSize: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-TimeInterval(windowSize))
        return recentFailures.filter { $0 >= cutoff }.count
    }

    mutating func pruneStaleFailures(maxAge: TimeInterval = 120) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        recentFailures.removeAll { $0 < cutoff }
    }
}

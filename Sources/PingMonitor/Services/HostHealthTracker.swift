import Foundation

actor HostHealthTracker {
    private var consecutiveFailures: [String: Int] = [:]
    private let failureThreshold: Int

    init(failureThreshold: Int = 3) {
        self.failureThreshold = failureThreshold
    }

    func record(host: String, success: Bool) -> Bool {
        if success {
            consecutiveFailures[host] = 0
            return true
        }

        let failures = (consecutiveFailures[host] ?? 0) + 1
        consecutiveFailures[host] = failures
        return failures < failureThreshold
    }

    func record(_ result: PingResult) -> Bool {
        record(host: result.host, success: result.isSuccess)
    }

    func isHostDown(_ host: String) -> Bool {
        (consecutiveFailures[host] ?? 0) >= failureThreshold
    }

    func failureCount(for host: String) -> Int {
        consecutiveFailures[host] ?? 0
    }

    func reset(host: String) {
        consecutiveFailures[host] = 0
    }

    func resetAll() {
        consecutiveFailures.removeAll()
    }
}

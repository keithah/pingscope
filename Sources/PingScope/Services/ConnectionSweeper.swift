import Foundation
import Network

actor ConnectionSweeper {
    private struct TrackedConnection {
        let connection: NWConnection
        let startTime: ContinuousClock.Instant
    }

    private var activeConnections: [UUID: TrackedConnection] = [:]
    private var sweepTask: Task<Void, Never>?
    private let clock = ContinuousClock()

    private let sweepInterval: Duration
    private let maxAge: Duration

    init(sweepInterval: Duration = .seconds(10), maxAge: Duration = .seconds(30)) {
        self.sweepInterval = sweepInterval
        self.maxAge = maxAge
    }

    func register(_ connection: NWConnection) -> UUID {
        let id = UUID()
        activeConnections[id] = TrackedConnection(
            connection: connection,
            startTime: clock.now
        )
        return id
    }

    func unregister(_ id: UUID) {
        activeConnections.removeValue(forKey: id)
    }

    func startSweeping() {
        guard sweepTask == nil else { return }

        let sweepInterval = self.sweepInterval
        sweepTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: sweepInterval)
                self.sweep()
            }
        }
    }

    func stopSweeping() {
        sweepTask?.cancel()
        sweepTask = nil
    }

    func sweep() {
        let now = clock.now

        for (id, tracked) in activeConnections where now - tracked.startTime > maxAge {
            tracked.connection.cancel()
            activeConnections.removeValue(forKey: id)
        }
    }

    func cancelAll() {
        for tracked in activeConnections.values {
            tracked.connection.cancel()
        }
        activeConnections.removeAll()
    }

    var activeCount: Int {
        activeConnections.count
    }
}

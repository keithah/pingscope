import Foundation

public struct LiveMonitorBackgroundTaskID: Equatable, Hashable, Sendable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public protocol LiveMonitorBackgroundTaskClient: Sendable {
    func beginBackgroundTask(named name: String, expirationHandler: @escaping @Sendable () -> Void) async -> LiveMonitorBackgroundTaskID?
    func endBackgroundTask(_ id: LiveMonitorBackgroundTaskID) async
}

public actor LiveMonitorBackgroundRuntime {
    private let client: any LiveMonitorBackgroundTaskClient
    private var activeTaskID: LiveMonitorBackgroundTaskID?
    private var expiringTaskID: LiveMonitorBackgroundTaskID?
    private var expirationHandler: (@Sendable () async -> Void)?

    /// How long the app-level cleanup may run once the OS expiration handler has
    /// fired, before the background task is ended regardless. The default is
    /// well inside the few-second watchdog grace period.
    private let expirationCleanupDeadline: Duration

    public init(
        client: any LiveMonitorBackgroundTaskClient,
        expirationCleanupDeadline: Duration = .seconds(2)
    ) {
        self.client = client
        self.expirationCleanupDeadline = expirationCleanupDeadline
    }

    public func begin(expirationHandler: @escaping @Sendable () async -> Void) async {
        await end()
        self.expirationHandler = expirationHandler

        activeTaskID = await client.beginBackgroundTask(named: "PingScope Live Monitor") { [weak self] in
            Task {
                await self?.expire()
            }
        }
    }

    public func end() async {
        guard let activeTaskID else {
            expirationHandler = nil
            return
        }

        self.activeTaskID = nil
        expirationHandler = nil
        await client.endBackgroundTask(activeTaskID)
    }

    private func expire() async {
        guard let activeTaskID else { return }

        self.activeTaskID = nil
        let handler = expirationHandler
        expirationHandler = nil

        // UIKit requires the background task to be ended promptly once its
        // expiration handler fires; overrunning the grace period gets the
        // process killed by the watchdog (0x8badf00d). But ending the OS task
        // first frees iOS to suspend the process before any cleanup has run,
        // losing the SQLite flush and leaving a stale Live Activity behind.
        // Give the cleanup a bounded slice of the grace period instead; the
        // deadline task guarantees endBackgroundTask fires even if the cleanup
        // stalls on I/O, and actor isolation makes ending exactly-once.
        expiringTaskID = activeTaskID
        let deadline = Task { [weak self, expirationCleanupDeadline] in
            try? await Task.sleep(for: expirationCleanupDeadline)
            guard !Task.isCancelled else { return }
            await self?.finishExpiration()
        }
        await handler?()
        deadline.cancel()
        await finishExpiration()
    }

    private func finishExpiration() async {
        guard let expiringTaskID else { return }
        self.expiringTaskID = nil
        await client.endBackgroundTask(expiringTaskID)
    }
}

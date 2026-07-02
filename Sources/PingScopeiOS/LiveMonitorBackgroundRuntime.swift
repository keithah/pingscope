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
    private var expirationHandler: (@Sendable () async -> Void)?

    public init(client: any LiveMonitorBackgroundTaskClient) {
        self.client = client
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
        // process killed by the watchdog (0x8badf00d). End the OS task first,
        // then run the app-level cleanup best-effort in whatever time remains
        // -- the reverse order gates endBackgroundTask behind a SQLite flush,
        // a history reload, a widget publish, and a Live Activity end.
        await client.endBackgroundTask(activeTaskID)
        await handler?()
    }
}

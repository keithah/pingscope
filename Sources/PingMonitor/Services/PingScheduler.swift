import Foundation

actor PingScheduler {
    typealias ResultHandler = @Sendable (PingResult, Bool) -> Void

    private let pingService: PingService
    private let healthTracker: HostHealthTracker

    private var pingTask: Task<Void, Never>?
    private var currentHosts: [Host] = []
    private var interval: Duration = .seconds(30)
    private var onResult: ResultHandler?

    init(pingService: PingService, healthTracker: HostHealthTracker) {
        self.pingService = pingService
        self.healthTracker = healthTracker
    }

    func setResultHandler(_ handler: @escaping ResultHandler) {
        onResult = handler
    }

    func start(hosts: [Host], interval: Duration = .seconds(30)) {
        pingTask?.cancel()

        self.currentHosts = hosts
        self.interval = interval

        guard !hosts.isEmpty else {
            pingTask = nil
            return
        }

        pingTask = Task {
            while !Task.isCancelled {
                await self.pingCycleWithStagger()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pingTask?.cancel()
        pingTask = nil
    }

    func updateHosts(_ hosts: [Host]) {
        pingTask?.cancel()
        start(hosts: hosts, interval: interval)
    }

    func refresh() {
        pingTask?.cancel()
        start(hosts: currentHosts, interval: interval)
    }

    var isRunning: Bool {
        pingTask != nil && !(pingTask?.isCancelled ?? true)
    }

    private func pingCycleWithStagger() async {
        let hosts = currentHosts
        let interval = self.interval
        let resultHandler = onResult

        guard !hosts.isEmpty else {
            return
        }

        let effectiveInterval = (interval * 4) / 5
        let staggerDelay = effectiveInterval / hosts.count

        await withTaskGroup(of: Void.self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    if index > 0 {
                        try? await Task.sleep(for: staggerDelay * index)
                    }

                    guard !Task.isCancelled else {
                        return
                    }

                    let result = await self.pingService.ping(host: host)
                    let isHostUp = await self.healthTracker.record(result)

                    guard let resultHandler else {
                        return
                    }

                    await MainActor.run {
                        resultHandler(result, isHostUp)
                    }
                }
            }
        }
    }
}

import Foundation

actor PingScheduler {
    typealias ResultHandler = @Sendable (PingResult, Bool) -> Void
    typealias PingOperation = @Sendable (Host) async -> PingResult
    typealias HealthRecorder = @Sendable (PingResult) async -> Bool

    private struct HostSchedule {
        let host: Host
        let effectiveInterval: Duration
        var nextDue: ContinuousClock.Instant
    }

    private let pingOperation: PingOperation
    private let healthRecorder: HealthRecorder
    private let clock = ContinuousClock()

    private var pingTask: Task<Void, Never>?
    private var currentHosts: [Host] = []
    private var intervalFallback: Duration = .seconds(30)
    private var onResult: ResultHandler?

    init(pingService: PingService, healthTracker: HostHealthTracker) {
        self.pingOperation = { host in
            await pingService.ping(host: host)
        }
        self.healthRecorder = { result in
            await healthTracker.record(result)
        }
    }

    init(
        pingOperation: @escaping PingOperation,
        healthRecorder: @escaping HealthRecorder
    ) {
        self.pingOperation = pingOperation
        self.healthRecorder = healthRecorder
    }

    func setResultHandler(_ handler: @escaping ResultHandler) {
        onResult = handler
    }

    func start(hosts: [Host], intervalFallback: Duration = .seconds(30)) {
        pingTask?.cancel()

        self.currentHosts = hosts
        self.intervalFallback = intervalFallback

        guard !hosts.isEmpty else {
            pingTask = nil
            return
        }

        pingTask = Task {
            await self.runCadenceLoop(hosts: hosts, intervalFallback: intervalFallback)
        }
    }

    func start(hosts: [Host], interval: Duration) {
        start(hosts: hosts, intervalFallback: interval)
    }

    func stop() {
        pingTask?.cancel()
        pingTask = nil
    }

    func updateHosts(_ hosts: [Host], intervalFallback: Duration? = nil) {
        pingTask?.cancel()
        start(hosts: hosts, intervalFallback: intervalFallback ?? self.intervalFallback)
    }

    func refresh(intervalFallback: Duration? = nil) {
        pingTask?.cancel()
        start(hosts: currentHosts, intervalFallback: intervalFallback ?? self.intervalFallback)
    }

    var isRunning: Bool {
        pingTask != nil && !(pingTask?.isCancelled ?? true)
    }

    private func runCadenceLoop(hosts: [Host], intervalFallback: Duration) async {
        var schedules = makeSchedules(hosts: hosts, intervalFallback: intervalFallback, now: clock.now)

        while !Task.isCancelled {
            guard !schedules.isEmpty else {
                return
            }

            let now = clock.now
            let dueIndices = schedules.indices.filter { schedules[$0].nextDue <= now }

            if dueIndices.isEmpty {
                guard let nextDue = schedules.map(\.nextDue).min() else {
                    return
                }
                try? await clock.sleep(until: nextDue)
                continue
            }

            let dueSchedules = dueIndices.map { schedules[$0] }

            for index in dueIndices {
                schedules[index].nextDue = nextDueTime(
                    after: schedules[index].nextDue,
                    interval: schedules[index].effectiveInterval,
                    now: now
                )
            }

            await pingDueHostsWithStagger(dueSchedules)
        }
    }

    private func makeSchedules(
        hosts: [Host],
        intervalFallback: Duration,
        now: ContinuousClock.Instant
    ) -> [HostSchedule] {
        let globalDefaults = GlobalDefaults(interval: intervalFallback)
        return hosts.map { host in
            HostSchedule(
                host: host,
                effectiveInterval: host.effectiveInterval(globalDefaults),
                nextDue: now
            )
        }
    }

    private func nextDueTime(
        after currentDue: ContinuousClock.Instant,
        interval: Duration,
        now: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        var nextDue = currentDue + interval
        while nextDue <= now {
            nextDue += interval
        }
        return nextDue
    }

    private func pingDueHostsWithStagger(_ dueSchedules: [HostSchedule]) async {
        let resultHandler = onResult

        guard !dueSchedules.isEmpty else {
            return
        }

        let shortestInterval = dueSchedules.map(\.effectiveInterval).min() ?? .seconds(1)
        let staggerWindow = (shortestInterval * 4) / 5
        let staggerDelay = staggerWindow / dueSchedules.count

        await withTaskGroup(of: Void.self) { group in
            for (index, schedule) in dueSchedules.enumerated() {
                group.addTask {
                    if index > 0 {
                        try? await Task.sleep(for: staggerDelay * index)
                    }

                    guard !Task.isCancelled else {
                        return
                    }

                    let result = await self.pingOperation(schedule.host)
                    let isHostUp = await self.healthRecorder(result)

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

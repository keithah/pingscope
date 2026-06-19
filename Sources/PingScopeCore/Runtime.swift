import Foundation

public protocol PingProbe: Sendable {
    func measure(_ host: HostConfig) async -> PingResult
}

public protocol ProbeFactory: Sendable {
    func makeProbe(for method: PingMethod) async -> any PingProbe
}

public struct HostTester: Sendable {
    private let probeFactory: any ProbeFactory

    public init(probeFactory: any ProbeFactory) {
        self.probeFactory = probeFactory
    }

    public func test(_ host: HostConfig) async -> PingResult {
        guard host.validationErrors.isEmpty else {
            return .failure(
                hostID: host.id,
                reason: .unknown,
                metadata: ProbeMetadata(note: "Host configuration is invalid")
            ).withHostMetadata(from: host)
        }

        let probe = await probeFactory.makeProbe(for: host.method)
        return await probe.measure(host)
    }
}

public struct DefaultGatewayDetector: Sendable {
    public init() {}

    public func detect() async -> HostConfig? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8),
                  let address = Self.parse(routeOutput: text) else {
                return nil
            }
            return Self.gatewayHost(address: address)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    public static func parse(routeOutput: String) -> String? {
        for line in routeOutput.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, parts[0] == "gateway", !parts[1].isEmpty {
                return parts[1]
            }
        }
        return nil
    }

    public static func gatewayHost(address: String) -> HostConfig {
        HostConfig(
            displayName: "Default Gateway",
            address: address,
            tier: .localGateway,
            method: .tcp,
            port: 80,
            interval: .seconds(2),
            timeout: .seconds(1),
            thresholds: LatencyThresholds(degradedMilliseconds: 20, downAfterFailures: 3)
        )
    }
}

public actor HostStore {
    private var orderedHosts: [HostConfig]
    private var primaryID: UUID?

    public init(defaultHosts: [HostConfig] = [.defaultInternet], primaryHostID: UUID? = nil) {
        self.orderedHosts = defaultHosts
        self.primaryID = primaryHostID ?? defaultHosts.first?.id
    }

    public func hosts() -> [HostConfig] {
        orderedHosts
    }

    public func enabledHosts() -> [HostConfig] {
        orderedHosts.filter(\.isEnabled)
    }

    public func primaryHostID() -> UUID? {
        primaryID ?? orderedHosts.first?.id
    }

    public func primaryHost() -> HostConfig? {
        let selectedID = primaryID ?? orderedHosts.first?.id
        return orderedHosts.first { $0.id == selectedID } ?? orderedHosts.first
    }

    public func upsert(_ host: HostConfig) {
        if let index = orderedHosts.firstIndex(where: { $0.id == host.id }) {
            orderedHosts[index] = host
        } else {
            orderedHosts.append(host)
        }
        if primaryID == nil {
            primaryID = host.id
        }
    }

    public func delete(_ id: UUID) {
        orderedHosts.removeAll { $0.id == id }
        if primaryID == id {
            primaryID = orderedHosts.first?.id
        }
    }

    public func selectPrimaryHost(_ id: UUID) {
        guard orderedHosts.contains(where: { $0.id == id }) else { return }
        primaryID = id
    }

    public func reset(defaultHosts: [HostConfig] = [.defaultInternet]) {
        orderedHosts = defaultHosts
        primaryID = defaultHosts.first?.id
    }
}

public actor MeasurementScheduler {
    private let probeFactory: any ProbeFactory
    private let logger: (@Sendable (String) -> Void)?
    private var tasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<PingResult>.Continuation?
    private var generation = 0

    public init(probeFactory: any ProbeFactory, logger: (@Sendable (String) -> Void)? = nil) {
        self.probeFactory = probeFactory
        self.logger = logger
    }

    public func start(hosts: [HostConfig], allowsLocalNetworkProbes: Bool = true) -> AsyncStream<PingResult> {
        stopTasks()
        continuation?.finish()
        continuation = nil
        generation += 1
        let runGeneration = generation

        let stream = AsyncStream<PingResult> { streamContinuation in
            self.continuation = streamContinuation
            streamContinuation.onTermination = { [weak self] _ in
                Task { await self?.stop(generation: runGeneration) }
            }
        }

        let measurableHosts = hosts.filter { host in
            host.isEnabled && (allowsLocalNetworkProbes || !host.requiresLocalNetworkPermission)
        }
        logger?("scheduler start generation=\(runGeneration) hosts=\(hosts.map(\.diagnosticDescription).joined(separator: "; ")) allowsLocal=\(allowsLocalNetworkProbes) measurable=\(measurableHosts.map(\.diagnosticDescription).joined(separator: "; "))")

        for (offset, host) in measurableHosts.enumerated() {
            let task = Task { [weak self] in
                if offset > 0 {
                    try? await Task.sleep(for: .milliseconds(offset * 250))
                }
                await self?.runLoop(for: host, generation: runGeneration)
            }
            tasks.append(task)
        }

        return stream
    }

    public func stop() {
        stopTasks()
        continuation?.finish()
        continuation = nil
    }

    private func stop(generation stoppedGeneration: Int) {
        guard stoppedGeneration == generation else { return }
        stop()
    }

    private func stopTasks() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func runLoop(for host: HostConfig, generation: Int) async {
        logger?("scheduler runLoop begin generation=\(generation) host=\(host.diagnosticDescription)")
        while !Task.isCancelled {
            let probe = await probeFactory.makeProbe(for: host.method)
            let result = await probe.measure(host)
            guard !Task.isCancelled, generation == self.generation else { return }
            if result.failureReason != nil {
                logger?("scheduler result host=\(host.displayName) failure=\(String(describing: result.failureReason))")
            }
            continuation?.yield(result)
            try? await Task.sleep(for: host.interval)
        }
        logger?("scheduler runLoop end generation=\(generation) host=\(host.diagnosticDescription)")
    }
}

private extension HostConfig {
    var diagnosticDescription: String {
        "\(displayName)|\(address)|\(method.rawValue)|\(port.map(String.init) ?? "-")|enabled=\(isEnabled)|local=\(requiresLocalNetworkPermission)"
    }
}

public actor PingRuntime {
    public let hostStore: HostStore
    private let scheduler: MeasurementScheduler
    private let historyStore: (any PingHistoryStore)?
    private var allowsLocalNetworkProbes: Bool
    private var alertEngine: AlertDecisionEngine
    private var healthByHost: [UUID: HostHealth] = [:]
    private var samplesByHost: [UUID: SampleSeries] = [:]
    private var streamTask: Task<Void, Never>?
    private var continuation: AsyncStream<RuntimeSnapshot>.Continuation?

    public init(
        hostStore: HostStore = HostStore(),
        scheduler: MeasurementScheduler,
        historyStore: (any PingHistoryStore)? = nil,
        allowsLocalNetworkProbes: Bool = true,
        notificationRules: NotificationRuleSet = NotificationRuleSet()
    ) {
        self.hostStore = hostStore
        self.scheduler = scheduler
        self.historyStore = historyStore
        self.allowsLocalNetworkProbes = allowsLocalNetworkProbes
        self.alertEngine = AlertDecisionEngine(rules: notificationRules)
    }

    public func snapshots() -> AsyncStream<RuntimeSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.publishSnapshot()
        }
    }

    public func start() async {
        await restartScheduler()
    }

    public func restartScheduler() async {
        streamTask?.cancel()
        let hosts = await hostStore.enabledHosts()
        let resultStream = await scheduler.start(hosts: hosts, allowsLocalNetworkProbes: allowsLocalNetworkProbes)
        streamTask = Task { [weak self] in
            for await result in resultStream {
                await self?.ingest(result)
            }
        }
        publishSnapshot()
    }

    public func stop() async {
        streamTask?.cancel()
        await scheduler.stop()
        continuation?.finish()
    }

    public func stopMeasurements() async {
        streamTask?.cancel()
        await scheduler.stop()
        publishSnapshot()
    }

    public func ingest(_ result: PingResult) async {
        let host = await hostStore.hosts().first { $0.id == result.hostID }
        var health = healthByHost[result.hostID] ?? HostHealth(hostID: result.hostID, thresholds: host?.thresholds ?? .defaults)
        let previousStatus = health.status
        health.ingest(result)
        healthByHost[result.hostID] = health

        var series = samplesByHost[result.hostID] ?? SampleSeries(hostID: result.hostID)
        series.append(result)
        samplesByHost[result.hostID] = series
        if let historyStore {
            Task {
                await historyStore.append(result)
            }
        }

        let alerts: [AlertDecision]
        if host?.notifications == .muted {
            alerts = []
        } else {
            alerts = alertEngine.evaluate(result: result, previousStatus: previousStatus, currentStatus: health.status).map { [$0] } ?? []
        }
        publishSnapshot(alerts: alerts)
    }

    public func upsertHost(_ host: HostConfig) async {
        let previous = await hostStore.hosts().first { $0.id == host.id }
        await hostStore.upsert(host)
        if let previous, previous.measurementEndpoint != host.measurementEndpoint {
            healthByHost[host.id] = HostHealth(hostID: host.id, thresholds: host.thresholds)
            samplesByHost[host.id] = SampleSeries(hostID: host.id)
        } else {
            healthByHost[host.id, default: HostHealth(hostID: host.id, thresholds: host.thresholds)].thresholds = host.thresholds
        }
        await restartScheduler()
    }

    public func deleteHost(_ id: UUID) async {
        await hostStore.delete(id)
        healthByHost.removeValue(forKey: id)
        samplesByHost.removeValue(forKey: id)
        await restartScheduler()
    }

    public func selectPrimaryHost(_ id: UUID) async {
        await hostStore.selectPrimaryHost(id)
        publishSnapshot()
    }

    public func setAllowsLocalNetworkProbes(_ isEnabled: Bool) async {
        guard allowsLocalNetworkProbes != isEnabled else { return }
        allowsLocalNetworkProbes = isEnabled
        await restartScheduler()
    }

    public func updateNotificationRules(_ rules: NotificationRuleSet) {
        alertEngine.rules = rules
    }

    public func evaluateNetworkChange(previousGateway: String?, currentGateway: String?, at date: Date = Date()) -> AlertDecision? {
        alertEngine.evaluateNetworkChange(previousGateway: previousGateway, currentGateway: currentGateway, at: date)
    }

    public func evaluateInternetLoss(results: [PingResult], at date: Date = Date()) -> AlertDecision? {
        alertEngine.evaluateInternetLoss(results: results, at: date)
    }

    public func reset() async {
        await hostStore.reset()
        healthByHost.removeAll()
        samplesByHost.removeAll()
        await historyStore?.deleteAll()
        await restartScheduler()
    }

    public func historySamples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        await historyStore?.samples(hostID: hostID, since: since, limit: limit) ?? []
    }

    private func publishSnapshot(alerts: [AlertDecision] = []) {
        Task {
            let hosts = await hostStore.hosts()
            let primaryID = await hostStore.primaryHostID()
            continuation?.yield(RuntimeSnapshot(
                hosts: hosts,
                primaryHostID: primaryID,
                healthByHost: healthByHost,
                samplesByHost: samplesByHost,
                alerts: alerts
            ))
        }
    }
}

private extension HostConfig {
    var measurementEndpoint: String {
        "\(method.rawValue)|\(address)|\(port.map(String.init) ?? "")"
    }
}

public struct RuntimeSnapshot: Sendable, Equatable {
    public var hosts: [HostConfig]
    public var primaryHostID: UUID?
    public var healthByHost: [UUID: HostHealth]
    public var samplesByHost: [UUID: SampleSeries]
    public var alerts: [AlertDecision]

    public init(
        hosts: [HostConfig],
        primaryHostID: UUID?,
        healthByHost: [UUID: HostHealth],
        samplesByHost: [UUID: SampleSeries],
        alerts: [AlertDecision] = []
    ) {
        self.hosts = hosts
        self.primaryHostID = primaryHostID
        self.healthByHost = healthByHost
        self.samplesByHost = samplesByHost
        self.alerts = alerts
    }

    public var primaryHost: HostConfig? {
        guard let primaryHostID else { return hosts.first }
        return hosts.first { $0.id == primaryHostID } ?? hosts.first
    }

    public var primaryHealth: HostHealth? {
        guard let id = primaryHost?.id else { return nil }
        return healthByHost[id]
    }

    public var primarySeries: SampleSeries? {
        guard let id = primaryHost?.id else { return nil }
        return samplesByHost[id]
    }
}

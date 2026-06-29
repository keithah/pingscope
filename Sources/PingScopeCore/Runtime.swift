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
    public enum DetectionOutcome: Sendable, Equatable {
        case detected(HostConfig)
        case notFound
        case failed
        case cancelled
    }

    public init() {}

    public func detect() async -> HostConfig? {
        if case let .detected(host) = await detectionOutcome() {
            return host
        }
        return nil
    }

    public func detectionOutcome() async -> DetectionOutcome {
        #if os(macOS)
        do {
            let result = try await AsyncProcess.run(
                executablePath: "/sbin/route",
                arguments: ["-n", "get", "default"],
                timeout: .seconds(3)
            )
            guard result.terminationStatus == 0,
                  let text = String(data: result.standardOutput, encoding: .utf8),
                  let address = Self.parse(routeOutput: text) else {
                return .notFound
            }
            return .detected(Self.gatewayHost(address: address))
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed
        }
        #else
        return .notFound
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

public struct StarlinkDishDetector: Sendable {
    public enum DetectionOutcome: Sendable, Equatable {
        case detected(HostConfig)
        case notFound
        case failed
        case cancelled
    }

    private enum DetectionResult: Sendable {
        case detected(HostConfig)
        case miss
        case failed
        case timeout
        case cancelled
    }

    private let statusClient: any StarlinkStatusFetching
    private let hosts: [HostConfig]

    public init(
        statusClient: any StarlinkStatusFetching = StarlinkStatusGRPCClient(transport: StarlinkHTTP2Transport()),
        hosts: [HostConfig] = HostConfig.starlinkDiscoveryCandidates
    ) {
        self.statusClient = statusClient
        self.hosts = hosts
    }

    public func detectionOutcome(timeout: Duration = .seconds(2)) async -> DetectionOutcome {
        await withTaskGroup(of: DetectionResult.self, returning: DetectionOutcome.self) { group in
            let statusClient = statusClient
            for host in hosts {
                group.addTask {
                    guard !Task.isCancelled else { return .cancelled }
                    do {
                        _ = try await statusClient.fetchStatus(host: host)
                        return .detected(host)
                    } catch is CancellationError {
                        return .cancelled
                    } catch {
                        return .failed
                    }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return .cancelled
                }
                return .timeout
            }

            var pendingCandidates = hosts.count
            var sawFailure = false
            while let result = await group.next() {
                switch result {
                case .detected(let detected):
                    group.cancelAll()
                    return .detected(detected)
                case .timeout:
                    group.cancelAll()
                    return .notFound
                case .cancelled:
                    group.cancelAll()
                    return .cancelled
                case .failed:
                    sawFailure = true
                    pendingCandidates -= 1
                case .miss:
                    pendingCandidates -= 1
                }
                if pendingCandidates == 0 {
                    group.cancelAll()
                    return sawFailure ? .failed : .notFound
                }
            }
            return .failed
        }
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
    private var lastFailureLogByHost: [UUID: (reason: FailureReason, date: Date)] = [:]

    public init(probeFactory: any ProbeFactory, logger: (@Sendable (String) -> Void)? = nil) {
        self.probeFactory = probeFactory
        self.logger = logger
    }

    public func start(hosts: [HostConfig], allowsLocalNetworkProbes: Bool = true) async -> AsyncStream<PingResult> {
        await stopTasks()
        continuation?.finish()
        continuation = nil
        generation += 1
        lastFailureLogByHost.removeAll()
        let runGeneration = generation

        let stream = AsyncStream<PingResult>(bufferingPolicy: .bufferingNewest(1)) { streamContinuation in
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

    public func stop() async {
        await stopTasks()
        continuation?.finish()
        continuation = nil
    }

    private func stop(generation stoppedGeneration: Int) async {
        guard stoppedGeneration == generation else { return }
        await stop()
    }

    private func stopTasks() async {
        let runningTasks = tasks
        tasks.removeAll()
        for task in runningTasks {
            task.cancel()
        }
        for task in runningTasks {
            await task.value
        }
    }

    private func runLoop(for host: HostConfig, generation: Int) async {
        logger?("scheduler runLoop begin generation=\(generation) host=\(host.diagnosticDescription)")
        while !Task.isCancelled {
            let probe = await probeFactory.makeProbe(for: host.method)
            let result = await probe.measure(host)
            guard !Task.isCancelled, generation == self.generation else { return }
            if shouldLogFailure(result) {
                logger?("scheduler result host=\(host.displayName) failure=\(String(describing: result.failureReason))")
            }
            continuation?.yield(result)
            try? await Task.sleep(for: host.interval)
        }
        logger?("scheduler runLoop end generation=\(generation) host=\(host.diagnosticDescription)")
    }

    private func shouldLogFailure(_ result: PingResult) -> Bool {
        guard let failureReason = result.failureReason else {
            lastFailureLogByHost.removeValue(forKey: result.hostID)
            return false
        }
        let last = lastFailureLogByHost[result.hostID]
        if last?.reason == failureReason,
           let lastDate = last?.date,
           result.timestamp.timeIntervalSince(lastDate) < 60 {
            return false
        }
        lastFailureLogByHost[result.hostID] = (failureReason, result.timestamp)
        return true
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
    private let historyWriter: HistoryWriteBuffer?
    private var allowsLocalNetworkProbes: Bool
    private var alertEngine: AlertDecisionEngine
    private let networkDiagnoser = NetworkPerspectiveDiagnoser()
    private var healthByHost: [UUID: HostHealth] = [:]
    private var samplesByHost: [UUID: SampleSeries] = [:]
    private var streamTask: Task<Void, Never>?
    private var continuation: AsyncStream<RuntimeSnapshot>.Continuation?
    private var continuationToken: UUID?
    private var cachedHosts: [HostConfig] = []
    private var hostByID: [UUID: HostConfig] = [:]
    private var cachedPrimaryHostID: UUID?

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
        self.historyWriter = historyStore.map { HistoryWriteBuffer(store: $0) }
        self.allowsLocalNetworkProbes = allowsLocalNetworkProbes
        self.alertEngine = AlertDecisionEngine(rules: notificationRules)
    }

    public func snapshots() async -> AsyncStream<RuntimeSnapshot> {
        await refreshHostCache()
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            self.continuationToken = token
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation(token: token) }
            }
            self.publishSnapshot()
        }
    }

    public func start() async {
        await restartScheduler()
    }

    public func restartScheduler() async {
        streamTask?.cancel()
        await refreshHostCache()
        let resultStream = await scheduler.start(hosts: cachedHosts.filter(\.isEnabled), allowsLocalNetworkProbes: allowsLocalNetworkProbes)
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
        await historyWriter?.flushNow()
        continuation?.finish()
        continuation = nil
        continuationToken = nil
    }

    public func stopMeasurements() async {
        streamTask?.cancel()
        await scheduler.stop()
        publishSnapshot()
    }

    public func ingest(_ result: PingResult) async {
        if cachedHosts.isEmpty {
            await refreshHostCache()
        }
        let host = hostByID[result.hostID]
        var health = healthByHost[result.hostID] ?? HostHealth(hostID: result.hostID, thresholds: host?.thresholds ?? .defaults)
        let previousStatus = health.status
        health.ingest(result)
        healthByHost[result.hostID] = health

        samplesByHost[result.hostID, default: SampleSeries(hostID: result.hostID)].append(result)
        await historyWriter?.append(result)

        let alerts: [AlertDecision]
        if host?.notifications == .muted {
            alerts = []
        } else {
            let diagnosis = networkDiagnoser.diagnose(hosts: cachedHosts, healthByHost: healthByHost)
            if let diagnosisAlert = alertEngine.evaluateDiagnosis(diagnosis, at: result.timestamp),
               !shouldSuppressDiagnosisAlert(diagnosisAlert) {
                alerts = [diagnosisAlert]
            } else {
                alerts = alertEngine.evaluate(result: result, previousStatus: previousStatus, currentStatus: health.status).map { [$0] } ?? []
            }
        }
        publishSnapshot(alerts: alerts)
    }

    public func upsertHost(_ host: HostConfig) async {
        await refreshHostCache()
        let previous = hostByID[host.id]
        guard previous != host else {
            publishSnapshot()
            return
        }
        await hostStore.upsert(host)
        await refreshHostCache()
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
        await refreshHostCache()
        healthByHost.removeValue(forKey: id)
        samplesByHost.removeValue(forKey: id)
        await restartScheduler()
    }

    public func removeStarlinkHosts() async -> [UUID] {
        await refreshHostCache()
        let ids = cachedHosts.filter { $0.method == .starlink }.map(\.id)
        guard !ids.isEmpty else { return [] }
        for id in ids {
            await hostStore.delete(id)
            healthByHost.removeValue(forKey: id)
            samplesByHost.removeValue(forKey: id)
        }
        await refreshHostCache()
        await restartScheduler()
        return ids
    }

    public func selectPrimaryHost(_ id: UUID) async {
        await hostStore.selectPrimaryHost(id)
        await refreshHostCache()
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
        await historyWriter?.discardPending()
        await hostStore.reset()
        await refreshHostCache()
        healthByHost.removeAll()
        samplesByHost.removeAll()
        await historyStore?.deleteAll()
        await restartScheduler()
    }

    public func historySamples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        await historyWriter?.flushNow()
        return await historyStore?.samples(hostID: hostID, since: since, limit: limit) ?? []
    }

    private func refreshHostCache() async {
        cachedHosts = await hostStore.hosts()
        hostByID = Dictionary(uniqueKeysWithValues: cachedHosts.map { ($0.id, $0) })
        cachedPrimaryHostID = await hostStore.primaryHostID()
    }

    private func publishSnapshot(alerts: [AlertDecision] = []) {
        continuation?.yield(RuntimeSnapshot(
            hosts: cachedHosts,
            primaryHostID: cachedPrimaryHostID,
            healthByHost: healthByHost,
            samplesByHost: samplesByHost,
            alerts: alerts
        ))
    }

    private func clearContinuation(token: UUID) {
        guard continuationToken == token else { return }
        continuation = nil
        continuationToken = nil
    }

    private func shouldSuppressDiagnosisAlert(_ alert: AlertDecision) -> Bool {
        switch alert {
        case let .remoteServiceDown(hostIDs):
            let mutedHostIDs = Set(cachedHosts.filter { $0.notifications == .muted }.map(\.id))
            return !hostIDs.isEmpty && hostIDs.allSatisfy { id in
                mutedHostIDs.contains(id)
            }
        default:
            return false
        }
    }
}

private extension HostConfig {
    var measurementEndpoint: String {
        "\(method.rawValue)|\(address)|\(port.map(String.init) ?? "")"
    }
}

private actor HistoryWriteBuffer {
    private let store: any PingHistoryStore
    private let maxBatchSize: Int
    private let flushDelay: Duration
    private var pending: [PingResult] = []
    private var flushTask: Task<Void, Never>?
    private var isDiscarding = false
    private var generation = 0

    init(
        store: any PingHistoryStore,
        maxBatchSize: Int = 32,
        flushDelay: Duration = .milliseconds(250)
    ) {
        self.store = store
        self.maxBatchSize = max(1, maxBatchSize)
        self.flushDelay = flushDelay
    }

    func append(_ result: PingResult) {
        pending.append(result)
        guard !isDiscarding else { return }
        if pending.count >= maxBatchSize {
            guard flushTask == nil else { return }
            scheduleImmediateFlush()
            return
        }
        scheduleFlushIfNeeded()
    }

    func flushNow() async {
        generation += 1
        while true {
            await cancelFlushTasks()
            guard !pending.isEmpty else { return }
            await drainAllPending()
        }
    }

    func discardPending() async {
        generation += 1
        isDiscarding = true
        while true {
            pending.removeAll()
            guard flushTask != nil else {
                pending.removeAll()
                isDiscarding = false
                return
            }
            await cancelFlushTasks()
        }
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil, !pending.isEmpty else { return }
        let scheduledGeneration = generation
        flushTask = Task { [flushDelay] in
            do {
                try await Task.sleep(for: flushDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await autoFlush(generation: scheduledGeneration)
        }
    }

    private func scheduleImmediateFlush() {
        guard flushTask == nil else { return }
        let scheduledGeneration = generation
        flushTask = Task {
            guard !Task.isCancelled else { return }
            await autoFlush(generation: scheduledGeneration)
        }
    }

    private func autoFlush(generation scheduledGeneration: Int) async {
        guard scheduledGeneration == generation, !Task.isCancelled else { return }
        await drainPending()
        guard scheduledGeneration == generation, !Task.isCancelled else { return }
        flushTask = nil
        if pending.count >= maxBatchSize {
            scheduleImmediateFlush()
        } else {
            scheduleFlushIfNeeded()
        }
    }

    private func drainAllPending() async {
        while !pending.isEmpty {
            await drainPending()
        }
    }

    private func drainPending() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        await store.append(batch)
    }

    private func cancelFlushTasks() async {
        while let task = flushTask {
            flushTask = nil
            task.cancel()
            await task.value
        }
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

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
                    } catch StarlinkStatusFetchError.unavailable, StarlinkStatusFetchError.timedOut {
                        return .miss
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
    private let probePermits: AsyncPermitPool
    private var tasks: [Task<Void, Never>] = []
    private var continuation: AsyncStream<PingResult>.Continuation?
    private var generation = 0
    private var lastFailureLogByHost: [UUID: (reason: FailureReason, date: Date)] = [:]

    public init(
        probeFactory: any ProbeFactory,
        logger: (@Sendable (String) -> Void)? = nil,
        maxConcurrentProbes: Int = 8
    ) {
        self.probeFactory = probeFactory
        self.logger = logger
        self.probePermits = AsyncPermitPool(permits: max(1, maxConcurrentProbes))
    }

    public func start(hosts: [HostConfig], allowsLocalNetworkProbes: Bool = true) async -> AsyncStream<PingResult> {
        await stopTasks()
        continuation?.finish()
        continuation = nil
        generation += 1
        lastFailureLogByHost.removeAll()
        let runGeneration = generation

        // Deep but bounded: multiple hosts probe concurrently and the runtime
        // consumes results serially, so `bufferingNewest(1)` silently dropped
        // results (skewing loss statistics and delaying down-transition
        // detection). Fully unbounded is the other failure mode -- a consumer
        // stalled on slow history writes would accumulate results without limit
        // over a long unattended session. 1024 absorbs any realistic burst.
        let stream = AsyncStream<PingResult>(bufferingPolicy: .bufferingNewest(1024)) { streamContinuation in
            self.continuation = streamContinuation
            streamContinuation.onTermination = { [weak self] _ in
                Task { await self?.stop(generation: runGeneration) }
            }
        }

        var measurableHosts: [HostConfig] = []
        var disabledCount = 0
        var localSuppressedCount = 0
        for host in hosts {
            if !host.isEnabled {
                disabledCount += 1
            } else if !allowsLocalNetworkProbes, host.requiresLocalNetworkPermission {
                localSuppressedCount += 1
            } else {
                measurableHosts.append(host)
            }
        }
        logger?("scheduler start generation=\(runGeneration) hosts=\(hosts.count) measurable=\(measurableHosts.count) disabled=\(disabledCount) localSuppressed=\(localSuppressedCount) allowsLocal=\(allowsLocalNetworkProbes)")

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

    private nonisolated func runLoop(for host: HostConfig, generation: Int) async {
        logger?("scheduler runLoop begin generation=\(generation) hostID=\(host.id.uuidString) method=\(host.method.rawValue)")
        while !Task.isCancelled {
            let probe = await probeFactory.makeProbe(for: host.method)
            await probePermits.acquire()
            let result = await probe.measure(host)
            await probePermits.release()
            guard !Task.isCancelled, await publish(result, for: host, generation: generation) else { return }
            try? await Task.sleep(for: host.interval)
        }
        logger?("scheduler runLoop end generation=\(generation) hostID=\(host.id.uuidString)")
    }

    private func publish(_ result: PingResult, for host: HostConfig, generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        if shouldLogFailure(result) {
            logger?("scheduler result hostID=\(host.id.uuidString) failure=\(String(describing: result.failureReason))")
        }
        continuation?.yield(result)
        return true
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

private actor AsyncPermitPool {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.availablePermits = permits
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            waiters.removeFirst().resume()
        }
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
    private var alertContinuation: AsyncStream<RuntimeAlertEvent>.Continuation?
    private var alertContinuationToken: UUID?
    private var pendingAlertEvents: [RuntimeAlertEvent] = []
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

    /// Latest-state stream. Deliberately conflating (`bufferingNewest(1)`): a slow
    /// consumer should skip to the newest state, not replay stale intermediates.
    /// One-shot events must never ride this stream -- use ``alerts()``.
    public func snapshots() async -> AsyncStream<RuntimeSnapshot> {
        await refreshHostCache()
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Finish a superseded subscriber's stream so its `for await` loop
            // ends instead of hanging on an orphaned continuation forever.
            self.continuation?.finish()
            self.continuation = continuation
            self.continuationToken = token
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearContinuation(token: token) }
            }
            self.publishSnapshot()
        }
    }

    /// One-shot alert events. Unbounded: unlike snapshots, an alert dropped by a
    /// conflating buffer is lost permanently (the decision engine has already
    /// committed its cooldown and edge-transition state by the time it is yielded).
    /// Alerts produced before any subscriber attached are held and replayed to
    /// the next subscriber, so an outage present at launch is never lost to the
    /// registration race with the scheduler's first results.
    public func alerts() -> AsyncStream<RuntimeAlertEvent> {
        let token = UUID()
        return AsyncStream(bufferingPolicy: .unbounded) { continuation in
            // Finish a superseded subscriber's stream so its `for await` loop
            // ends instead of hanging on an orphaned continuation forever.
            self.alertContinuation?.finish()
            self.alertContinuation = continuation
            self.alertContinuationToken = token
            continuation.onTermination = { [weak self] _ in
                Task { await self?.clearAlertContinuation(token: token) }
            }
            for event in self.pendingAlertEvents {
                continuation.yield(event)
            }
            self.pendingAlertEvents.removeAll()
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
        alertContinuation?.finish()
        alertContinuation = nil
        alertContinuationToken = nil
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

        if host?.notifications != .muted {
            var alerts: [AlertDecision] = []
            // Commit the diagnosis engine's cooldown/signature state only once we
            // know the alert will actually be delivered; otherwise a suppressed
            // (all-muted) diagnosis would burn the cooldown of a later real one.
            let diagnosis = networkDiagnoser.diagnose(hosts: cachedHosts, healthByHost: healthByHost)
            var diagnosisAlert: AlertDecision?
            if let candidate = alertEngine.diagnosisAlertCandidate(diagnosis, at: result.timestamp),
               !shouldSuppressDiagnosisAlert(candidate.decision) {
                alertEngine.commit(candidate)
                diagnosisAlert = candidate.decision
            }
            // Always evaluate the per-host transition so edge detection and the
            // high-latency streak counters are never perturbed by unrelated
            // diagnosis activity. A same-tick diagnosis alert already tells the
            // user something went down, so only the redundant hostDown is elided;
            // recovery and high-latency transitions are never swallowed.
            let transitionCandidate = alertEngine.transitionAlertCandidate(
                result: result,
                previousStatus: previousStatus,
                currentStatus: health.status
            )
            if let diagnosisAlert {
                alerts.append(diagnosisAlert)
            }
            if let transitionCandidate {
                if case .hostDown = transitionCandidate.decision, diagnosisAlert != nil {
                    // Superseded by the root-cause diagnosis for this tick.
                    // Deliberately not committed: an elided alert must not burn
                    // the per-host cooldown, or a second outage inside the
                    // window would produce no notification at all.
                } else {
                    alertEngine.commit(transitionCandidate)
                    alerts.append(transitionCandidate.decision)
                }
            }
            publishAlerts(alerts)
        }
        publishSnapshot()
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

    private func publishSnapshot() {
        continuation?.yield(RuntimeSnapshot(
            hosts: cachedHosts,
            primaryHostID: cachedPrimaryHostID,
            healthByHost: healthByHost,
            samplesByHost: samplesByHost
        ))
    }

    private func publishAlerts(_ decisions: [AlertDecision]) {
        guard !decisions.isEmpty else { return }
        let event = RuntimeAlertEvent(decisions: decisions, hosts: cachedHosts)
        guard let alertContinuation else {
            // The decision engine has already committed its cooldown and edge
            // state, so an alert with no subscriber yet would be permanently
            // lost. Hold it for the next subscriber; capped so a runtime nobody
            // ever subscribes to cannot grow without bound.
            pendingAlertEvents.append(event)
            if pendingAlertEvents.count > 64 {
                pendingAlertEvents.removeFirst()
            }
            return
        }
        alertContinuation.yield(event)
    }

    private func clearContinuation(token: UUID) {
        guard continuationToken == token else { return }
        continuation = nil
        continuationToken = nil
    }

    private func clearAlertContinuation(token: UUID) {
        guard alertContinuationToken == token else { return }
        alertContinuation = nil
        alertContinuationToken = nil
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
    private var pending: BoundedBuffer<PingResult>
    private var flushTask: Task<Void, Never>?
    private var isDiscarding = false
    private var generation = 0

    init(
        store: any PingHistoryStore,
        maxBatchSize: Int = 32,
        maxPendingResults: Int = 2048,
        flushDelay: Duration = .milliseconds(250)
    ) {
        self.store = store
        self.maxBatchSize = max(1, maxBatchSize)
        self.pending = BoundedBuffer(capacity: max(self.maxBatchSize, maxPendingResults))
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
        let batch = pending.popPrefix(maxBatchSize)
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

/// A batch of alert decisions produced by a single ingested result, together with
/// the host list needed to render them. Delivered on ``PingRuntime/alerts()``, a
/// non-conflating stream, so no decision is ever silently dropped.
public struct RuntimeAlertEvent: Sendable, Equatable {
    public let decisions: [AlertDecision]
    public let hosts: [HostConfig]

    public init(decisions: [AlertDecision], hosts: [HostConfig]) {
        self.decisions = decisions
        self.hosts = hosts
    }
}

public struct RuntimeSnapshot: Sendable, Equatable {
    public var hosts: [HostConfig]
    public var primaryHostID: UUID?
    public var healthByHost: [UUID: HostHealth]
    public var samplesByHost: [UUID: SampleSeries]

    public init(
        hosts: [HostConfig],
        primaryHostID: UUID?,
        healthByHost: [UUID: HostHealth],
        samplesByHost: [UUID: SampleSeries]
    ) {
        self.hosts = hosts
        self.primaryHostID = primaryHostID
        self.healthByHost = healthByHost
        self.samplesByHost = samplesByHost
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

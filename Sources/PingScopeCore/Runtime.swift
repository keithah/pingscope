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

public struct DefaultGatewayEndpointResolver: Sendable {
    public struct Candidate: Equatable, Hashable, Sendable {
        public var method: PingMethod
        public var port: UInt16?

        public init(method: PingMethod, port: UInt16?) {
            self.method = method
            self.port = port
        }
    }

    public static let defaultCandidates: [Candidate] = [
        Candidate(method: .tcp, port: 80),
        Candidate(method: .tcp, port: 443),
        Candidate(method: .https, port: 443),
        Candidate(method: .udp, port: 53)
    ]

    private let probeFactory: any ProbeFactory
    private let candidates: [Candidate]

    public init(
        probeFactory: any ProbeFactory,
        candidates: [Candidate] = Self.defaultCandidates
    ) {
        self.probeFactory = probeFactory
        self.candidates = candidates.isEmpty ? Self.defaultCandidates : candidates
    }

    public func resolve(address: String) async -> HostConfig {
        let fallback = host(address: address, candidate: candidates[0])
        return await withTaskGroup(of: HostConfig?.self, returning: HostConfig.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let candidateHost = host(address: address, candidate: candidate)
                    let probe = await probeFactory.makeProbe(for: candidate.method)
                    let result = await probe.measure(candidateHost)
                    guard !Task.isCancelled, result.isSuccess else { return nil }
                    return candidateHost
                }
            }

            for await host in group {
                if let host {
                    group.cancelAll()
                    return host
                }
            }
            return fallback
        }
    }

    private func host(address: String, candidate: Candidate) -> HostConfig {
        var host = DefaultGatewayDetector.gatewayHost(address: address)
        host.method = candidate.method
        host.port = candidate.port
        return host
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
        case cancelled
    }

    private let statusClient: any StarlinkStatusFetching
    private let hosts: [HostConfig]

    public init(
        statusClient: any StarlinkStatusFetching = StarlinkStatusGRPCClient(transport: StarlinkHTTP2Transport()),
        hosts: [HostConfig] = HostConfig.starlinkDiscoveryCandidates
    ) {
        self.statusClient = statusClient
        self.hosts = Array(hosts.prefix(8))
    }

    public func detectionOutcome(timeout: Duration = .seconds(2)) async -> DetectionOutcome {
        let race = AsyncFirstResult<DetectionOutcome>()
        let detectionTask = Task {
            await race.finish(await detectCandidateOutcome())
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(for: timeout)
                await race.finish(.notFound)
            } catch {
                await race.finish(.cancelled)
            }
        }

        let outcome = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            detectionTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.finish(.cancelled)
            }
        }
        detectionTask.cancel()
        timeoutTask.cancel()
        return outcome
    }

    private func detectCandidateOutcome() async -> DetectionOutcome {
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

            var pendingCandidates = hosts.count
            var sawFailure = false
            while let result = await group.next() {
                switch result {
                case .detected(let detected):
                    group.cancelAll()
                    return .detected(detected)
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
        let normalized = Self.coalescingManagedDefaultGatewayHosts(
            defaultHosts,
            primaryID: primaryHostID ?? defaultHosts.first?.id
        )
        self.orderedHosts = normalized.hosts
        self.primaryID = normalized.primaryID
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
        } else if let index = orderedHosts.firstIndex(where: { Self.isManagedDefaultGateway($0) && Self.isManagedDefaultGateway(host) }) {
            let replacedID = orderedHosts[index].id
            orderedHosts[index] = host
            if primaryID == replacedID {
                primaryID = host.id
            }
        } else {
            orderedHosts.append(host)
        }
        if primaryID == nil {
            primaryID = host.id
        }
        coalesceManagedDefaultGatewayHosts()
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
        coalesceManagedDefaultGatewayHosts()
    }

    private static func isManagedDefaultGateway(_ host: HostConfig) -> Bool {
        host.displayName == "Default Gateway"
    }

    private func coalesceManagedDefaultGatewayHosts() {
        let normalized = Self.coalescingManagedDefaultGatewayHosts(orderedHosts, primaryID: primaryID)
        orderedHosts = normalized.hosts
        primaryID = normalized.primaryID
    }

    private static func coalescingManagedDefaultGatewayHosts(
        _ hosts: [HostConfig],
        primaryID: UUID?
    ) -> (hosts: [HostConfig], primaryID: UUID?) {
        guard let keptGatewayIndex = hosts.firstIndex(where: Self.isManagedDefaultGateway) else {
            return (hosts, primaryID)
        }
        let keptGatewayID = hosts[keptGatewayIndex].id
        var removedPrimary = false
        var seenGateway = false
        let normalizedHosts = hosts.filter { host in
            guard Self.isManagedDefaultGateway(host) else { return true }
            if !seenGateway {
                seenGateway = true
                return true
            }
            if primaryID == host.id {
                removedPrimary = true
            }
            return false
        }
        return (normalizedHosts, removedPrimary ? keptGatewayID : primaryID)
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
        if !tasks.isEmpty {
            logger?("scheduler restart generation=\(generation) cancelingTasks=\(tasks.count)")
        }
        cancelRunningTasks()
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
                Task { await self?.logResultStreamTermination(generation: runGeneration) }
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
                    do {
                        try await Task.sleep(for: .milliseconds(offset * 250))
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
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

    private func logResultStreamTermination(generation terminatedGeneration: Int) {
        logger?("scheduler result stream terminated generation=\(terminatedGeneration) currentGeneration=\(generation)")
    }

    private func cancelRunningTasks() {
        let runningTasks = tasks
        tasks.removeAll()
        for task in runningTasks {
            task.cancel()
        }
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
            do {
                try await probePermits.acquire()
            } catch {
                return
            }
            let permitLease = AsyncPermitLease(pool: probePermits)
            let result = await withTaskCancellationHandler {
                let result = await probe.measure(host)
                await permitLease.release()
                return result
            } onCancel: {
                Task { await permitLease.release() }
            }
            guard !Task.isCancelled, await publish(result, for: host, generation: generation) else { return }
            do {
                try await Task.sleep(for: host.interval)
            } catch {
                break
            }
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
    private var pendingAlertStartIndex = 0
    private var cachedHosts: [HostConfig] = []
    private var hostByID: [UUID: HostConfig] = [:]
    private var cachedPrimaryHostID: UUID?

    public init(
        hostStore: HostStore = HostStore(),
        scheduler: MeasurementScheduler,
        historyStore: (any PingHistoryStore)? = nil,
        allowsLocalNetworkProbes: Bool = true,
        notificationRules: NotificationRuleSet = NotificationRuleSet(),
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.hostStore = hostStore
        self.scheduler = scheduler
        self.historyStore = historyStore
        self.historyWriter = historyStore.map { HistoryWriteBuffer(store: $0, logger: logger) }
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

    /// One-shot alert events. Alerts produced before any subscriber attached are
    /// held and replayed to the next subscriber, so an outage present at launch is
    /// not lost to the registration race with the scheduler's first results.
    ///
    /// Deliberately unbounded: these are edge transitions, not conflatable state.
    /// Dropping an old "outage started" while keeping its later recovery can leave
    /// consumers with an impossible alert timeline.
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
            for event in self.pendingAlertEvents[self.pendingAlertStartIndex...] {
                continuation.yield(event)
            }
            self.pendingAlertEvents.removeAll()
            self.pendingAlertStartIndex = 0
        }
    }

    public func start() async {
        await restartScheduler()
    }

    public func restartScheduler(refreshCache: Bool = true) async {
        streamTask?.cancel()
        if refreshCache {
            await refreshHostCache()
        }
        let resultStream = await scheduler.start(hosts: cachedHosts.filter(\.isEnabled), allowsLocalNetworkProbes: allowsLocalNetworkProbes)
        streamTask = Task { [self] in
            for await result in resultStream {
                await ingest(result)
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
        await restartScheduler(refreshCache: false)
    }

    public func deleteHost(_ id: UUID) async {
        await hostStore.delete(id)
        await refreshHostCache()
        healthByHost.removeValue(forKey: id)
        samplesByHost.removeValue(forKey: id)
        await restartScheduler(refreshCache: false)
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
        await restartScheduler(refreshCache: false)
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
        await restartScheduler(refreshCache: false)
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
        await restartScheduler(refreshCache: false)
    }

    public func historySamples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        await historyWriter?.flushNow()
        return await historyStore?.samples(hostID: hostID, since: since, limit: limit) ?? []
    }

    public func exportHistory(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        await historyWriter?.flushNow()
        guard let historyStore else { return 0 }
        return try await historyStore.exportSamples(host: host, since: since, format: format, to: url)
    }

    private func refreshHostCache() async {
        cachedHosts = HostConfig.sanitizedHosts(await hostStore.hosts())
        hostByID = Dictionary(uniqueKeysWithValues: cachedHosts.map { ($0.id, $0) })
        let primaryID = await hostStore.primaryHostID()
        cachedPrimaryHostID = cachedHosts.contains { $0.id == primaryID } ? primaryID : cachedHosts.first?.id
        alertEngine.prune(activeHostIDs: Set(cachedHosts.map(\.id)))
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
            if pendingAlertEvents.count - pendingAlertStartIndex > 64 {
                pendingAlertStartIndex += 1
            }
            compactPendingAlertsIfNeeded()
            return
        }
        alertContinuation.yield(event)
    }

    private func compactPendingAlertsIfNeeded() {
        if pendingAlertStartIndex == pendingAlertEvents.count {
            pendingAlertEvents.removeAll(keepingCapacity: true)
            pendingAlertStartIndex = 0
        } else if pendingAlertStartIndex > 32, pendingAlertStartIndex * 2 > pendingAlertEvents.count {
            pendingAlertEvents = Array(pendingAlertEvents[pendingAlertStartIndex...])
            pendingAlertStartIndex = 0
        }
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

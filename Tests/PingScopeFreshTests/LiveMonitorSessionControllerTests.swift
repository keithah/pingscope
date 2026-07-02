import XCTest
import PingScopeCore
import PingScopeiOS

final class LiveMonitorSessionControllerTests: XCTestCase {
    func testControllerStartsFiniteSessionAndPublishesProbeResult() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10))
        )

        await controller.start(duration: .thirtySeconds)
        try await Task.sleep(for: .milliseconds(40))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .thirtySeconds)
        XCTAssertEqual(snapshot.session?.phase(), .live)
        XCTAssertEqual(snapshot.health.status, HealthStatus.healthy)
        XCTAssertEqual(snapshot.health.latestResult?.latency?.milliseconds.rounded(), 18)
        XCTAssertGreaterThanOrEqual(snapshot.series.samples.count, 1)
        XCTAssertEqual(snapshot.series.stats.received, snapshot.series.samples.count)
        let measurementCount = await probe.measurementCount
        XCTAssertGreaterThanOrEqual(measurementCount, 1)
    }

    func testControllerWritesMeasuredSamplesToHistoryStore() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let history = RecordingLiveMonitorHistoryStore()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(50)),
            historyStore: history
        )

        await controller.start(duration: .thirtySeconds)
        try await Task.sleep(for: .milliseconds(40))
        let samplesBeforeStop = await history.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(samplesBeforeStop.count, 0)
        await controller.stop()

        let samples = await history.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].latency, .milliseconds(18))
    }

    func testControllerHistoryStoreKeepsHostMetadata() async throws {
        let host = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1", method: .tcp, port: 443)
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(6))
        ])
        let history = RecordingLiveMonitorHistoryStore()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(50)),
            historyStore: history
        )

        await controller.start(duration: .thirtySeconds)
        try await Task.sleep(for: .milliseconds(40))
        await controller.stop()

        let samples = await history.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(samples.first?.address, "192.168.1.1")
        XCTAssertEqual(samples.first?.method, .tcp)
        XCTAssertEqual(samples.first?.port, 443)
    }

    func testControllerRestartClearsPreviousSessionSamples() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18)),
            .success(hostID: host.id, latency: .milliseconds(19))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(100))
        )

        await controller.start(duration: .thirtySeconds)
        try await Task.sleep(for: .milliseconds(35))
        let firstSnapshot = await controller.snapshot()
        XCTAssertEqual(firstSnapshot.series.samples.count, 1)

        await controller.start(duration: .oneMinute)
        try await Task.sleep(for: .milliseconds(35))

        let secondSnapshot = await controller.snapshot()
        XCTAssertEqual(secondSnapshot.session?.duration, .oneMinute)
        XCTAssertEqual(secondSnapshot.series.samples.count, 1)
        XCTAssertEqual(secondSnapshot.series.samples.first?.latency?.milliseconds.rounded(), 19)
    }

    func testControllerStopsWithUserStoppedReasonAndCancelsFurtherMeasurements() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18)),
            .success(hostID: host.id, latency: .milliseconds(19)),
            .success(hostID: host.id, latency: .milliseconds(20))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10))
        )

        await controller.start(duration: .oneMinute)
        try await Task.sleep(for: .milliseconds(25))
        await controller.stop(reason: .userStopped)
        let countAfterStop = await probe.measurementCount
        try await Task.sleep(for: .milliseconds(40))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.phase(), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .userStopped)
        let finalCount = await probe.measurementCount
        XCTAssertEqual(finalCount, countAfterStop)
    }

    func testControllerContinuousSessionRunsUntilStopped() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18)),
            .success(hostID: host.id, latency: .milliseconds(19)),
            .success(hostID: host.id, latency: .milliseconds(20))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10))
        )

        await controller.start(duration: .continuous)
        try await Task.sleep(for: .milliseconds(45))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .continuous)
        XCTAssertEqual(snapshot.session?.phase(), .live)
        XCTAssertGreaterThanOrEqual(snapshot.series.samples.count, 2)
    }

    func testControllerEndsWhenBackgroundRuntimeExpiresBeforeSelectedDuration() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            backgroundRuntimeLimit: .milliseconds(35)
        )

        await controller.start(duration: .oneMinute)
        try await Task.sleep(for: .milliseconds(80))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.phase(), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .backgroundRuntimeExpired)
        let measurementCount = await probe.measurementCount
        XCTAssertGreaterThanOrEqual(measurementCount, 1)
    }

    func testIOSHostStorePersistsSelectedHost() {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        ]
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts)

        store.save(hosts: hosts, selectedHostID: hosts[1].id)
        let state = store.load()

        XCTAssertEqual(state.hosts, hosts)
        XCTAssertEqual(state.selectedHost.id, hosts[1].id)
    }

    func testIOSHostStoreFallsBackWhenSelectedHostIsMissing() {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        ]
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts)

        store.save(hosts: [hosts[0]], selectedHostID: hosts[1].id)
        let state = store.load()

        XCTAssertEqual(state.hosts, [hosts[0]])
        XCTAssertEqual(state.selectedHost.id, hosts[0].id)
    }

    func testIOSHostStoreLeavesUndecodableHostsBlobIntact() {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // A blob this build cannot decode (written by a newer app version, or
        // transiently corrupt). Loading must fall back to defaults without
        // overwriting it: replacing the stored hosts would permanently orphan
        // every history row keyed by their IDs, even after upgrading back.
        let undecodable = Data("not host json".utf8)
        defaults.set(undecodable, forKey: "PingScope.iOS.hosts")
        let store = PingScopeIOSHostStore(defaults: defaults)

        let state = store.load()

        XCTAssertEqual(state.hosts, PingScopeIOSHostStore.defaultHosts)
        XCTAssertEqual(defaults.data(forKey: "PingScope.iOS.hosts"), undecodable)
    }

    func testIOSHostDraftBuildsValidatedHostFromEditableFields() {
        let host = HostConfig(
            id: UUID(),
            displayName: " Original ",
            address: " 1.1.1.1 ",
            method: .tcp,
            port: 443,
            interval: .seconds(2),
            timeout: .seconds(2),
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 3)
        )
        var draft = PingScopeIOSHostDraft(host: host)

        draft.displayName = " Cloudflare "
        draft.address = " one.one.one.one "
        draft.portText = "8443"
        draft.intervalMilliseconds = 500
        draft.timeoutMilliseconds = 750
        draft.degradedMilliseconds = 125
        draft.downAfterFailures = 4

        let finalized = draft.finalizedHost
        XCTAssertEqual(finalized.id, host.id)
        XCTAssertEqual(finalized.displayName, "Cloudflare")
        XCTAssertEqual(finalized.address, "one.one.one.one")
        XCTAssertEqual(finalized.port, 8443)
        XCTAssertEqual(finalized.interval, .milliseconds(500))
        XCTAssertEqual(finalized.timeout, .milliseconds(750))
        XCTAssertEqual(finalized.thresholds.degradedMilliseconds, 125)
        XCTAssertEqual(finalized.thresholds.downAfterFailures, 4)
        XCTAssertTrue(draft.validationErrors.isEmpty)
    }

    func testIOSHostDraftAppliesMethodAwarePortAndRejectsInvalidInput() {
        var draft = PingScopeIOSHostDraft(host: HostConfig(displayName: "Cloudflare", address: "1.1.1.1"))

        draft.apply(method: .udp)
        XCTAssertEqual(draft.method, .udp)
        XCTAssertEqual(draft.portText, "53")

        draft.displayName = " "
        draft.address = ""
        draft.portText = "0"
        draft.intervalMilliseconds = 100
        draft.timeoutMilliseconds = 100
        draft.degradedMilliseconds = 0
        draft.downAfterFailures = 0

        XCTAssertFalse(draft.validationErrors.isEmpty)
        XCTAssertFalse(draft.canSave)

        draft.displayName = "Cloudflare"
        draft.address = "1.1.1.1"
        draft.portText = "99999"
        draft.intervalMilliseconds = 1_000
        draft.timeoutMilliseconds = 1_000
        draft.degradedMilliseconds = 100
        draft.downAfterFailures = 3

        XCTAssertEqual(draft.validationErrors, [.invalidPort])
        XCTAssertFalse(draft.canSave)
    }

    func testIOSGatewayDetectorDerivesLikelyPrivateGatewayAddresses() {
        XCTAssertEqual(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "192.168.101.34"), "192.168.101.1")
        XCTAssertEqual(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "10.20.30.40"), "10.20.30.1")
        XCTAssertEqual(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "172.20.4.3"), "172.20.4.1")
        XCTAssertEqual(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "169.254.44.9"), "169.254.44.1")
    }

    func testIOSGatewayDetectorDoesNotInventGatewayForPublicOrInvalidAddresses() {
        XCTAssertNil(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "8.8.8.8"))
        XCTAssertNil(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "192.168.1.1"))
        XCTAssertNil(PingScopeIOSGatewayDetector.likelyGatewayAddress(fromIPv4Address: "not-an-ip"))
    }

    func testBackgroundRuntimeEndsPreviousTaskWhenBeginningAgain() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(client: client)

        await runtime.begin {}
        await runtime.begin {}

        let startedNames = await client.startedNamesSnapshot()
        let endedIDs = await client.endedIDsSnapshot()
        XCTAssertEqual(startedNames, ["PingScope Live Monitor", "PingScope Live Monitor"])
        XCTAssertEqual(endedIDs, [LiveMonitorBackgroundTaskID(rawValue: 1)])
    }

    func testBackgroundRuntimeExpirationCallsCleanupAndEndsTaskOnce() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(client: client)
        let cleanup = ExpirationCleanupRecorder()

        await runtime.begin {
            await cleanup.record()
        }
        await client.expireMostRecent()
        // The expiration handler only spawns a Task; wait for the cleanup to
        // actually run rather than racing it against a wall-clock sleep.
        await cleanup.waitForRecord()
        await runtime.end()

        let cleanupCount = await cleanup.countSnapshot()
        let endedIDs = await client.endedIDsSnapshot()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertEqual(endedIDs, [LiveMonitorBackgroundTaskID(rawValue: 1)])
    }

    func testBackgroundRuntimeExpirationRunsCleanupBeforeEndingTask() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(client: client)
        let cleanup = ExpirationCleanupRecorder()
        let endsSeenByCleanup = ExpirationObservationBox()

        await runtime.begin {
            // Capture whether the OS task had already been ended when the
            // cleanup ran: ending first frees iOS to suspend the process
            // before the history flush and Live Activity end have happened.
            let ended = await client.endedIDsSnapshot()
            await endsSeenByCleanup.set(ended)
            await cleanup.record()
        }
        await client.expireMostRecent()
        await cleanup.waitForRecord()

        // The task must still end promptly once the cleanup finishes.
        var endedIDs = await client.endedIDsSnapshot()
        var attempts = 0
        while endedIDs.isEmpty, attempts < 200 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(10))
            endedIDs = await client.endedIDsSnapshot()
        }

        let observed = await endsSeenByCleanup.get()
        XCTAssertEqual(observed, [], "cleanup must run while the background task is still alive")
        XCTAssertEqual(endedIDs, [LiveMonitorBackgroundTaskID(rawValue: 1)])
    }

    func testBackgroundRuntimeExpirationEndsTaskEvenWhenCleanupStalls() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(
            client: client,
            expirationCleanupDeadline: .milliseconds(20)
        )

        await runtime.begin {
            // A cleanup stuck on I/O must not hold the background task past the
            // deadline; overrunning the watchdog grace period kills the process.
            try? await Task.sleep(for: .seconds(60))
        }
        await client.expireMostRecent()

        var endedIDs = await client.endedIDsSnapshot()
        var attempts = 0
        while endedIDs.isEmpty, attempts < 200 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(10))
            endedIDs = await client.endedIDsSnapshot()
        }

        XCTAssertEqual(endedIDs, [LiveMonitorBackgroundTaskID(rawValue: 1)])
    }

    func testBackgroundRuntimeEndPreventsLateExpirationCleanup() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(client: client)
        let cleanup = ExpirationCleanupRecorder()

        await runtime.begin {
            await cleanup.record()
        }
        await runtime.end()
        await client.expireMostRecent()
        try? await Task.sleep(for: .milliseconds(20))

        let cleanupCount = await cleanup.countSnapshot()
        let endedIDs = await client.endedIDsSnapshot()
        XCTAssertEqual(cleanupCount, 0)
        XCTAssertEqual(endedIDs, [LiveMonitorBackgroundTaskID(rawValue: 1)])
    }
}

private actor RecordingProbe: PingProbe {
    private var results: [PingResult]
    private(set) var measurementCount = 0

    init(results: [PingResult]) {
        self.results = results
    }

    func measure(_ host: HostConfig) async -> PingResult {
        measurementCount += 1
        let index = min(measurementCount - 1, results.count - 1)
        return results[index].withHostMetadata(from: host)
    }
}

private struct StaticProbeFactory: ProbeFactory {
    let probe: RecordingProbe

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

private actor RecordingLiveMonitorHistoryStore: PingHistoryStore {
    private var stored: [PingResult] = []

    func append(_ result: PingResult) async {
        stored.append(result)
    }

    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(stored.filter { $0.hostID == hostID && $0.timestamp >= since }.prefix(limit))
    }

    func prune(olderThan cutoff: Date) async {
        stored.removeAll { $0.timestamp < cutoff }
    }

    func deleteAll() async {
        stored.removeAll()
    }
}

private actor RecordingBackgroundTaskClient: LiveMonitorBackgroundTaskClient {
    private(set) var startedNames: [String] = []
    private(set) var endedIDs: [LiveMonitorBackgroundTaskID] = []
    private var nextID = 1
    private var mostRecentExpirationHandler: (@Sendable () -> Void)?

    func beginBackgroundTask(named name: String, expirationHandler: @escaping @Sendable () -> Void) async -> LiveMonitorBackgroundTaskID? {
        startedNames.append(name)
        mostRecentExpirationHandler = expirationHandler
        let id = LiveMonitorBackgroundTaskID(rawValue: nextID)
        nextID += 1
        return id
    }

    func endBackgroundTask(_ id: LiveMonitorBackgroundTaskID) async {
        endedIDs.append(id)
    }

    func expireMostRecent() {
        mostRecentExpirationHandler?()
    }

    func startedNamesSnapshot() -> [String] {
        startedNames
    }

    func endedIDsSnapshot() -> [LiveMonitorBackgroundTaskID] {
        endedIDs
    }
}

private actor ExpirationCleanupRecorder {
    private(set) var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        count += 1
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForRecord() async {
        while count == 0 {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func countSnapshot() -> Int {
        count
    }
}

private actor ExpirationObservationBox {
    private var value: [LiveMonitorBackgroundTaskID]?

    func set(_ newValue: [LiveMonitorBackgroundTaskID]) {
        value = newValue
    }

    func get() -> [LiveMonitorBackgroundTaskID]? {
        value
    }
}

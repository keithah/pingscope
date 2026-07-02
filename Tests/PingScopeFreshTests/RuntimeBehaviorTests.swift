import XCTest
@testable import PingScopeCore

final class RuntimeBehaviorTests: XCTestCase {
    func testHostStoreDefaultsAndPrimarySelection() async {
        let store = HostStore(defaultHosts: [.defaultInternet])

        let hosts = await store.hosts()
        XCTAssertEqual(hosts.map(\.displayName), ["Cloudflare DNS"])
        let initialPrimaryID = await store.primaryHostID()
        XCTAssertEqual(initialPrimaryID, hosts.first?.id)

        let second = HostConfig(displayName: "Router", address: "192.168.1.1")
        await store.upsert(second)
        await store.selectPrimaryHost(second.id)

        let selectedPrimaryID = await store.primaryHostID()
        let enabledHostNames = await store.enabledHosts().map(\.displayName)
        XCTAssertEqual(selectedPrimaryID, second.id)
        XCTAssertEqual(enabledHostNames, ["Cloudflare DNS", "Router"])
    }

    func testMeasurementSchedulerUsesFreshProbePerMeasurement() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com", interval: .milliseconds(20))
        let factory = CountingProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(7)))
        let scheduler = MeasurementScheduler(probeFactory: factory)
        let stream = await scheduler.start(hosts: [host])

        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        _ = await iterator.next()
        await scheduler.stop()

        let createdProbeCount = await factory.createdProbeCount
        XCTAssertGreaterThanOrEqual(createdProbeCount, 2)
    }

    func testMeasurementSchedulerSkipsDisabledHosts() async {
        let disabled = HostConfig(displayName: "Disabled", address: "example.com", isEnabled: false)
        let factory = CountingProbeFactory(result: .success(hostID: disabled.id, latency: .milliseconds(7)))
        let scheduler = MeasurementScheduler(probeFactory: factory)
        _ = await scheduler.start(hosts: [disabled])

        try? await Task.sleep(for: .milliseconds(50))
        await scheduler.stop()

        let createdProbeCount = await factory.createdProbeCount
        XCTAssertEqual(createdProbeCount, 0)
    }

    func testMeasurementSchedulerSkipsLocalHostsUnlessAllowed() async {
        let router = HostConfig(displayName: "Router", address: "192.168.1.1", interval: .milliseconds(20))
        let factory = CountingProbeFactory(result: .success(hostID: router.id, latency: .milliseconds(7)))
        let scheduler = MeasurementScheduler(probeFactory: factory)
        _ = await scheduler.start(hosts: [router], allowsLocalNetworkProbes: false)

        try? await Task.sleep(for: .milliseconds(50))
        await scheduler.stop()

        let createdProbeCount = await factory.createdProbeCount
        XCTAssertEqual(createdProbeCount, 0)
    }

    func testMeasurementSchedulerRestartDoesNotLeakLateResultsFromPreviousRun() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .milliseconds(20))
        let newHost = HostConfig(displayName: "New", address: "new.example", interval: .milliseconds(20))
        let scheduler = MeasurementScheduler(probeFactory: DelayedProbeFactory(delay: .milliseconds(80)))
        _ = await scheduler.start(hosts: [oldHost])

        try? await Task.sleep(for: .milliseconds(10))
        let newStream = await scheduler.start(hosts: [newHost])
        let firstResult = try await firstResult(from: newStream, timeout: .milliseconds(300))

        XCTAssertEqual(firstResult?.hostID, newHost.id)
        await scheduler.stop()
    }

    func testMeasurementSchedulerOldStreamTerminationDoesNotCancelNewRun() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .milliseconds(20))
        let newHost = HostConfig(displayName: "New", address: "new.example", interval: .milliseconds(20))
        let scheduler = MeasurementScheduler(probeFactory: DelayedProbeFactory(delay: .milliseconds(20)))
        let oldStream = await scheduler.start(hosts: [oldHost])
        let oldConsumer = Task {
            var iterator = oldStream.makeAsyncIterator()
            _ = await iterator.next()
        }

        let newStream = await scheduler.start(hosts: [newHost])
        oldConsumer.cancel()
        let firstResult = try await firstResult(from: newStream, timeout: .milliseconds(300))

        XCTAssertEqual(firstResult?.hostID, newHost.id)
        await scheduler.stop()
    }

    func testRuntimePublishesOneShotAlertEventsOnDedicatedStream() async throws {
        let host = HostConfig(
            displayName: "Example",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let store = HostStore(defaultHosts: [host])
        let runtime = PingRuntime(hostStore: store, scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .failure(hostID: host.id, reason: .timeout))))
        let alertStream = await runtime.alerts()

        await runtime.ingest(.failure(hostID: host.id, reason: .timeout))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertEqual(decisions, [.remoteServiceDown(hostIDs: [host.id])])
    }

    func testRuntimeSuppressesAlertEventsForMutedHosts() async throws {
        let host = HostConfig(
            displayName: "Muted",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1),
            notifications: .muted
        )
        let store = HostStore(defaultHosts: [host])
        let runtime = PingRuntime(hostStore: store, scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .failure(hostID: host.id, reason: .timeout))))
        let alertStream = await runtime.alerts()

        await runtime.ingest(.failure(hostID: host.id, reason: .timeout))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertEqual(decisions, [])
    }

    func testRuntimeDeliversRecoveryAlongsideSameTickDiagnosisAlert() async throws {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let hostA = HostConfig(displayName: "A", address: "a.example", thresholds: thresholds)
        let hostB = HostConfig(displayName: "B", address: "b.example", thresholds: thresholds)
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [hostA, hostB]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            notificationRules: NotificationRuleSet(cooldown: .seconds(0), diagnosisSensitivity: .sensitive)
        )
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 7_000)

        await runtime.ingest(.failure(hostID: hostA.id, reason: .timeout, timestamp: base))
        await runtime.ingest(.failure(hostID: hostB.id, reason: .timeout, timestamp: base.addingTimeInterval(1)))
        // Host A recovers on the same tick that shifts the network diagnosis to
        // "B only": the diagnosis alert must not swallow A's recovery transition.
        await runtime.ingest(.success(hostID: hostA.id, latency: .milliseconds(8), timestamp: base.addingTimeInterval(2)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertTrue(decisions.contains(.recovered(hostID: hostA.id)), "expected recovery in \(decisions)")
    }

    func testRuntimeSuppressedMutedDiagnosisDoesNotConsumeCooldown() async throws {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let muted = HostConfig(displayName: "Muted", address: "muted.example", thresholds: thresholds, notifications: .muted)
        let other = HostConfig(displayName: "Other", address: "other.example", thresholds: thresholds)
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [muted, other]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            notificationRules: NotificationRuleSet(diagnosisSensitivity: .sensitive)
        )
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 8_000)

        // The muted host's outage produces an all-muted diagnosis that is never
        // delivered; it must not consume the .remoteServiceDown cooldown.
        await runtime.ingest(.failure(hostID: muted.id, reason: .timeout, timestamp: base))
        await runtime.ingest(.success(hostID: other.id, latency: .milliseconds(8), timestamp: base.addingTimeInterval(1)))
        // 60s later (well inside the 300s cooldown) the unmuted host fails too.
        await runtime.ingest(.failure(hostID: other.id, reason: .timeout, timestamp: base.addingTimeInterval(60)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertEqual(decisions, [.remoteServiceDown(hostIDs: [muted.id, other.id])])
    }

    func testRuntimeCanPauseMeasurementsWithoutClosingSnapshots() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(9))))
        )
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await runtime.stopMeasurements()
        let nextSnapshot = await iterator.next()
        let snapshotAfterPause = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(snapshotAfterPause.hosts, [host])
        await runtime.stop()
    }

    func testRuntimeClearsSamplesWhenHostEndpointChanges() async throws {
        let host = HostConfig(displayName: "Default Gateway", address: "192.168.1.1", method: .tcp, port: 80)
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(9))))
        )
        await runtime.ingest(.success(hostID: host.id, latency: .milliseconds(7)).withHostMetadata(from: host))

        var updated = host
        updated.address = "192.168.4.1"
        await runtime.upsertHost(updated)
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        let nextSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(snapshot.primaryHost?.address, "192.168.4.1")
        XCTAssertNil(snapshot.primaryHealth?.latestResult)
        XCTAssertEqual(snapshot.primarySeries?.samples, [])
        await runtime.stop()
    }

    func testRuntimeDeletingPrimaryHostSelectsFallbackAndClearsSamples() async throws {
        let gateway = HostConfig(displayName: "Default Gateway", address: "192.168.101.1", method: .tcp, port: 80)
        let starlink = HostConfig.defaultStarlinkDish
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [gateway, starlink], primaryHostID: starlink.id),
            scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .success(hostID: gateway.id, latency: .milliseconds(9))))
        )
        await runtime.ingest(.success(hostID: starlink.id, latency: .milliseconds(22)).withHostMetadata(from: starlink))

        await runtime.deleteHost(starlink.id)
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        let nextSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(snapshot.hosts.map(\.id), [gateway.id])
        XCTAssertEqual(snapshot.primaryHost?.id, gateway.id)
        XCTAssertNil(snapshot.healthByHost[starlink.id])
        XCTAssertNil(snapshot.samplesByHost[starlink.id])
        await runtime.stop()
    }

    func testRuntimeResetPreventsFullHistoryBatchFromWritingAfterDiscard() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let historyStore = DelayedHistoryStore(appendDelay: .milliseconds(80))
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            historyStore: historyStore
        )

        for index in 0..<32 {
            await runtime.ingest(.success(
                hostID: host.id,
                latency: .milliseconds(Double(index + 1)),
                timestamp: Date(timeIntervalSince1970: Double(index))
            ).withHostMetadata(from: host))
        }

        try await Task.sleep(for: .milliseconds(10))
        await runtime.reset()
        try await Task.sleep(for: .milliseconds(120))

        let samples = await historyStore.samples(hostID: host.id, since: .distantPast, limit: 100)
        XCTAssertTrue(samples.isEmpty)
        await runtime.stop()
    }

    func testRuntimeStopFlushesPendingHistoryFromCancelledTask() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let historyStore = DelayedHistoryStore(appendDelay: .milliseconds(1))
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .success(hostID: host.id, latency: .milliseconds(7)))),
            historyStore: historyStore
        )
        await runtime.ingest(.success(hostID: host.id, latency: .milliseconds(12)).withHostMetadata(from: host))

        let stopTask = Task {
            await runtime.stop()
        }
        stopTask.cancel()
        await stopTask.value

        let samples = await historyStore.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(samples.count, 1)
    }

    func testRuntimeDiscardPendingLeavesNoLiveFlushTask() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let historyStore = ControlledHistoryStore()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            historyStore: historyStore
        )

        for index in 0..<32 {
            await runtime.ingest(.success(
                hostID: host.id,
                latency: .milliseconds(Double(index + 1)),
                timestamp: Date(timeIntervalSince1970: Double(index))
            ).withHostMetadata(from: host))
        }
        await historyStore.waitForAppendCount(1)

        let resetTask = Task {
            await runtime.reset()
        }
        try await Task.sleep(for: .milliseconds(50))
        for index in 32..<64 {
            await runtime.ingest(.success(
                hostID: host.id,
                latency: .milliseconds(Double(index + 1)),
                timestamp: Date(timeIntervalSince1970: Double(index))
            ).withHostMetadata(from: host))
        }

        await historyStore.releaseAppends()
        await resetTask.value
        let appendCountAfterReset = await historyStore.appendCount
        try await Task.sleep(for: .milliseconds(350))
        let finalAppendCount = await historyStore.appendCount
        let finalSamples = await historyStore.samples(hostID: host.id, since: .distantPast, limit: 100)

        XCTAssertEqual(finalAppendCount, appendCountAfterReset)
        XCTAssertTrue(finalSamples.isEmpty)
        await runtime.stop()
    }

    func testRuntimeRemovesStaleStarlinkBeforeSnapshotObservation() async throws {
        let gateway = HostConfig(displayName: "Default Gateway", address: "192.168.101.1", method: .tcp, port: 80)
        let starlink = HostConfig.defaultStarlinkDish
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [gateway, starlink], primaryHostID: starlink.id),
            scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .success(hostID: gateway.id, latency: .milliseconds(9))))
        )
        await runtime.ingest(.success(hostID: starlink.id, latency: .milliseconds(22)).withHostMetadata(from: starlink))

        let removedIDs = await runtime.removeStarlinkHosts()
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        let nextSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(removedIDs, [starlink.id])
        XCTAssertEqual(snapshot.hosts.map(\.id), [gateway.id])
        XCTAssertEqual(snapshot.primaryHost?.id, gateway.id)
        XCTAssertNil(snapshot.healthByHost[starlink.id])
        XCTAssertNil(snapshot.samplesByHost[starlink.id])
        await runtime.stop()
    }

    func testDisplayPresenterFiltersSamplesToSelectedRange() {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        var series = SampleSeries(hostID: hostID, capacity: 10)
        series.append(.success(hostID: hostID, latency: .milliseconds(10), timestamp: now.addingTimeInterval(-400)))
        series.append(.success(hostID: hostID, latency: .milliseconds(20), timestamp: now.addingTimeInterval(-299)))
        series.append(.failure(hostID: hostID, reason: .timeout, timestamp: now))

        let visible = DisplayStatePresenter().visibleSamples(in: series, range: .fiveMinutes, now: now)

        XCTAssertEqual(visible.map(\.timestamp), [now.addingTimeInterval(-299), now])
    }

    func testDisplayPresenterMergesHistoryAndLiveSamplesWithoutDuplicates() {
        let hostID = UUID()
        let duplicateID = UUID()
        let now = Date(timeIntervalSince1970: 20_000)
        let old = PingResult.success(hostID: hostID, latency: .milliseconds(1), timestamp: now.addingTimeInterval(-400))
        let duplicateFromHistory = PingResult(id: duplicateID, hostID: hostID, timestamp: now.addingTimeInterval(-20), latency: .milliseconds(10), failureReason: nil)
        let duplicateFromLive = PingResult(id: duplicateID, hostID: hostID, timestamp: now.addingTimeInterval(-20), latency: .milliseconds(11), failureReason: nil)
        let newest = PingResult.failure(hostID: hostID, reason: .timeout, timestamp: now)

        let merged = DisplayStatePresenter().mergedSamples(
            history: [old, duplicateFromHistory],
            live: [duplicateFromLive, newest],
            range: .fiveMinutes,
            now: now
        )

        XCTAssertEqual(merged.map(\.id), [duplicateID, newest.id])
        XCTAssertEqual(merged.first?.latency?.milliseconds, 11)
    }

    func testMenuDisplayStateFormatsStableStatus() {
        let host = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        let presenter = DisplayStatePresenter()

        XCTAssertEqual(presenter.menuBarState(for: host, health: health).text, "--ms")
        XCTAssertEqual(presenter.menuBarState(for: host, health: health).color, .gray)

        health.ingest(.success(hostID: host.id, latency: .milliseconds(14.6)))

        XCTAssertEqual(presenter.menuBarState(for: host, health: health).text, "15ms")
        XCTAssertEqual(presenter.menuBarState(for: host, health: health).color, .green)
    }

    func testRangeStatusAgesOutStaleLatestResult() {
        let now = Date(timeIntervalSince1970: 30_000)
        let host = HostConfig(displayName: "Default Gateway", address: "192.168.101.1")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(6), timestamp: now.addingTimeInterval(-90)))

        let presenter = DisplayStatePresenter()
        let state = presenter.rangeStatusState(for: host, health: health, range: .oneMinute, now: now)

        XCTAssertEqual(state.text, "--ms")
        XCTAssertEqual(state.color, .gray)
        XCTAssertEqual(presenter.rangeStatusLabel(for: health, range: .oneMinute, now: now), "No Recent Data")
    }

    func testRangeStatusUsesRecentLatestResult() {
        let now = Date(timeIntervalSince1970: 30_000)
        let host = HostConfig(displayName: "Default Gateway", address: "192.168.101.1")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(6), timestamp: now.addingTimeInterval(-20)))

        let presenter = DisplayStatePresenter()
        let state = presenter.rangeStatusState(for: host, health: health, range: .oneMinute, now: now)

        XCTAssertEqual(state.text, "6ms")
        XCTAssertEqual(state.color, .green)
        XCTAssertEqual(presenter.rangeStatusLabel(for: health, range: .oneMinute, now: now), "Healthy")
    }

    func testLatencyGraphScaleUsesReadableMaximumFromVisibleSamples() {
        let scale = LatencyGraphScale(latencies: [14, 78, 107])

        XCTAssertEqual(scale.maximumMilliseconds, 107)
        XCTAssertEqual(scale.axisMaximumMilliseconds, 125)
        XCTAssertEqual(scale.tickMilliseconds, [125, 62.5, 0])
        XCTAssertEqual(scale.label(for: scale.axisMaximumMilliseconds), "125ms")
    }

    func testMenuBarGlyphContentStacksDotOverLatency() {
        let host = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(22)))

        let content = DisplayStatePresenter().menuBarGlyphContent(for: host, health: health)

        XCTAssertEqual(content.latencyText, "22ms")
        XCTAssertEqual(content.dotDiameter, 8)
        XCTAssertEqual(content.itemWidth, 34)
        XCTAssertEqual(content.fontSize, 9.5)
        XCTAssertEqual(content.fontWeight, .regular)
        XCTAssertEqual(content.textBaselineY, 0)
        XCTAssertEqual(content.color, .green)
        XCTAssertTrue(content.accessibilityLabel.contains("22ms"))
    }
}

private struct TestTimeout: Error {}

/// Drains the alert stream once the runtime has been stopped (which finishes the
/// continuation) and flattens the decisions in publish order.
private func collectDecisions(from stream: AsyncStream<RuntimeAlertEvent>) async -> [AlertDecision] {
    var decisions: [AlertDecision] = []
    for await event in stream {
        decisions.append(contentsOf: event.decisions)
    }
    return decisions
}

private func firstResult(from stream: AsyncStream<PingResult>, timeout: Duration) async throws -> PingResult? {
    try await withThrowingTaskGroup(of: PingResult?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestTimeout()
        }
        let result = try await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

private actor CountingProbeFactory: ProbeFactory {
    private let result: PingResult
    private(set) var createdProbeCount = 0

    init(result: PingResult) {
        self.result = result
    }

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        createdProbeCount += 1
        return StaticProbe(result: result)
    }
}

private struct StaticProbe: PingProbe {
    let result: PingResult

    func measure(_ host: HostConfig) async -> PingResult {
        result.withHostMetadata(from: host)
    }
}

private struct DelayedProbeFactory: ProbeFactory {
    let delay: Duration

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        DelayedProbe(delay: delay)
    }
}

private struct DelayedProbe: PingProbe {
    let delay: Duration

    func measure(_ host: HostConfig) async -> PingResult {
        try? await Task.sleep(for: delay)
        return .success(hostID: host.id, latency: .milliseconds(12)).withHostMetadata(from: host)
    }
}

private struct HangingProbeFactory: ProbeFactory {
    func makeProbe(for method: PingMethod) async -> any PingProbe {
        HangingProbe()
    }
}

private struct HangingProbe: PingProbe {
    func measure(_ host: HostConfig) async -> PingResult {
        try? await Task.sleep(for: .seconds(60))
        return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
    }
}

private actor DelayedHistoryStore: PingHistoryStore {
    private let appendDelay: Duration
    private var stored: [PingResult] = []

    init(appendDelay: Duration) {
        self.appendDelay = appendDelay
    }

    func append(_ result: PingResult) async {
        await append([result])
    }

    func append(_ results: [PingResult]) async {
        try? await Task.sleep(for: appendDelay)
        stored.append(contentsOf: results)
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

private actor ControlledHistoryStore: PingHistoryStore {
    private(set) var appendCount = 0
    private var stored: [PingResult] = []
    private var isReleased = false
    private var appendWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func append(_ result: PingResult) async {
        await append([result])
    }

    func append(_ results: [PingResult]) async {
        appendCount += 1
        appendWaiters.forEach { $0.resume() }
        appendWaiters.removeAll()
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        stored.append(contentsOf: results)
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

    func waitForAppendCount(_ count: Int) async {
        while appendCount < count {
            await withCheckedContinuation { continuation in
                appendWaiters.append(continuation)
            }
        }
    }

    func releaseAppends() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

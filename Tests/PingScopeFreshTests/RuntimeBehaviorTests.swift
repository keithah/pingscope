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

    func testRuntimePublishesOneShotAlertEvents() async throws {
        let host = HostConfig(
            displayName: "Example",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let store = HostStore(defaultHosts: [host])
        let runtime = PingRuntime(hostStore: store, scheduler: MeasurementScheduler(probeFactory: CountingProbeFactory(result: .failure(hostID: host.id, reason: .timeout))))
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await runtime.ingest(.failure(hostID: host.id, reason: .timeout))
        let nextSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(snapshot.alerts, [.remoteServiceDown(hostIDs: [host.id])])
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
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await runtime.ingest(.failure(hostID: host.id, reason: .timeout))
        let nextSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(nextSnapshot)

        XCTAssertEqual(snapshot.alerts, [])
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

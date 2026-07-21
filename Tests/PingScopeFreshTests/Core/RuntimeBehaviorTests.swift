import XCTest
@testable import PingScopeCore

final class RuntimeBehaviorTests: XCTestCase {
    func testConfirmedDownProbeBackoffUsesBaseForDetectionThenDoublesToCap() {
        let base = Duration.seconds(2)

        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 0, baseInterval: base), base)
        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 1, baseInterval: base), base)
        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 2, baseInterval: base), .seconds(4))
        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 3, baseInterval: base), .seconds(8))
        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 8, baseInterval: base), .seconds(30))
        XCTAssertEqual(ProbeIdleBackoffPolicy.interval(confirmedDownFailureCount: 20, baseInterval: base), .seconds(30))
    }

    func testBackoffCadenceUsesAuthoritativeStatusTransition() {
        var tracker = ProbeIdleBackoffTracker()
        let hostID = UUID()
        let failure = PingResult.failure(hostID: hostID, reason: .timeout)

        XCTAssertEqual(
            tracker.interval(
                after: failure,
                previousStatus: .degraded,
                currentStatus: .down,
                baseInterval: .seconds(2)
            ),
            .seconds(2)
        )
        XCTAssertEqual(
            tracker.interval(
                after: failure,
                previousStatus: .down,
                currentStatus: .down,
                baseInterval: .seconds(2)
            ),
            .seconds(4)
        )
    }

    func testConfirmedDownProbeBackoffResetsOnAnySuccessfulResponse() {
        let hostID = UUID()
        var health = HostHealth(
            hostID: hostID,
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 3)
        )
        var tracker = ProbeIdleBackoffTracker()

        func interval(after result: PingResult) -> Duration {
            let previousStatus = health.status
            health.ingest(result)
            return tracker.interval(
                after: result,
                previousStatus: previousStatus,
                currentStatus: health.status,
                baseInterval: .seconds(2)
            )
        }

        XCTAssertEqual(interval(after: .failure(hostID: hostID, reason: .timeout)), .seconds(2))
        XCTAssertEqual(interval(after: .failure(hostID: hostID, reason: .timeout)), .seconds(2))
        XCTAssertEqual(interval(after: .failure(hostID: hostID, reason: .timeout)), .seconds(2))
        XCTAssertEqual(interval(after: .failure(hostID: hostID, reason: .timeout)), .seconds(4))
        XCTAssertEqual(interval(after: .success(hostID: hostID, latency: .milliseconds(150))), .seconds(2))
        XCTAssertEqual(interval(after: .failure(hostID: hostID, reason: .timeout)), .seconds(2))
    }

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

    func testHostStoreCoalescesDefaultGatewayUpsertsByName() async {
        let existingGateway = HostConfig(
            id: UUID(),
            displayName: "Default Gateway",
            address: "192.168.42.1",
            tier: .localGateway,
            method: .tcp,
            port: 80
        )
        let store = HostStore(defaultHosts: [.defaultInternet, existingGateway], primaryHostID: existingGateway.id)
        let rediscoveredGateway = HostConfig(
            id: UUID(),
            displayName: "Default Gateway",
            address: "192.168.42.1",
            tier: .localGateway,
            method: .udp,
            port: 53
        )

        await store.upsert(rediscoveredGateway)

        let hosts = await store.hosts()
        let primaryHostID = await store.primaryHostID()
        XCTAssertEqual(hosts.map(\.displayName), ["Cloudflare DNS", "Default Gateway"])
        XCTAssertEqual(hosts.last?.id, rediscoveredGateway.id)
        XCTAssertEqual(hosts.last?.method, .udp)
        XCTAssertEqual(primaryHostID, rediscoveredGateway.id)
    }

    func testHostStoreNormalizesPersistedDefaultGatewayDuplicates() async {
        let firstGateway = HostConfig(
            id: UUID(),
            displayName: "Default Gateway",
            address: "192.168.42.1",
            tier: .localGateway,
            method: .tcp,
            port: 80
        )
        let duplicateGateway = HostConfig(
            id: UUID(),
            displayName: "Default Gateway",
            address: "192.168.42.1",
            tier: .localGateway,
            method: .tcp,
            port: 80
        )
        let store = HostStore(defaultHosts: [.defaultInternet, firstGateway, duplicateGateway], primaryHostID: duplicateGateway.id)

        let hosts = await store.hosts()
        let primaryHostID = await store.primaryHostID()

        XCTAssertEqual(hosts.map(\.displayName), ["Cloudflare DNS", "Default Gateway"])
        XCTAssertEqual(hosts.last?.id, firstGateway.id)
        XCTAssertEqual(primaryHostID, firstGateway.id)
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

    func testMeasurementSchedulerRestartJoinsCancellationResponsivePreviousProbe() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .milliseconds(20))
        let newHost = HostConfig(displayName: "New", address: "new.example", interval: .milliseconds(20))
        let scheduler = MeasurementScheduler(probeFactory: HostSensitiveProbeFactory(hangingAddress: oldHost.address))
        let oldStream = await scheduler.start(hosts: [oldHost])

        let replacementResult = try await withThrowingTaskGroup(of: PingResult?.self) { group in
            group.addTask {
                let newStream = await scheduler.start(hosts: [newHost])
                return try await firstResult(from: newStream, timeout: .milliseconds(300))
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(300))
                throw TestTimeout()
            }
            let result = try await group.next() ?? nil
            group.cancelAll()
            return result
        }

        XCTAssertEqual(replacementResult?.hostID, newHost.id)
        withExtendedLifetime(oldStream) {}
        await scheduler.stop()
    }

    func testMeasurementSchedulerRestartJoinsCooperativePreviousGeneration() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .seconds(60))
        let newHost = HostConfig(displayName: "New", address: "new.example", interval: .seconds(60))
        let tracker = RestartCleanupTracker(oldHostID: oldHost.id)
        let scheduler = MeasurementScheduler(
            probeFactory: RestartCleanupProbeFactory(tracker: tracker, cleanupDelay: .milliseconds(40))
        )
        _ = await scheduler.start(hosts: [oldHost])
        await tracker.waitUntilOldProbeStarts()

        let newStream = await scheduler.start(hosts: [newHost])
        let firstResult = try await firstResult(from: newStream, timeout: .milliseconds(500))

        XCTAssertEqual(firstResult?.hostID, newHost.id)
        let newStartedAfterCleanup = await tracker.newStartedAfterOldCleanup
        XCTAssertTrue(newStartedAfterCleanup, "a replacement generation must not launch before cooperative cleanup joins")
        await scheduler.stop()
    }

    func testMeasurementSchedulerRestartWaitsForExplicitPriorGenerationCleanupGate() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .seconds(60))
        let newHost = HostConfig(displayName: "New", address: "new.example", interval: .seconds(60))
        let tracker = StrictSchedulerJoinTracker(oldHostID: oldHost.id)
        let callState = SchedulerCallState()
        let scheduler = MeasurementScheduler(probeFactory: StrictSchedulerJoinProbeFactory(tracker: tracker))
        _ = await scheduler.start(hosts: [oldHost])
        await tracker.waitUntilOldProbeStarts()

        let restartTask = Task {
            let stream = await scheduler.start(hosts: [newHost])
            await callState.recordReturn()
            return stream
        }
        await tracker.waitUntilOldCancellationStarts()
        try await Task.sleep(for: .milliseconds(150))

        let restartReturnedWhileCleanupWasGated = await callState.didReturn
        let replacementStartedWhileCleanupWasGated = await tracker.didNewProbeStart
        XCTAssertFalse(restartReturnedWhileCleanupWasGated)
        XCTAssertFalse(replacementStartedWhileCleanupWasGated)

        await tracker.releaseOldCleanup()
        let newStream = await restartTask.value
        let firstResult = try await firstResult(from: newStream, timeout: .milliseconds(300))
        XCTAssertEqual(firstResult?.hostID, newHost.id)
        let cleanupFinishedBeforeReplacement = await tracker.newStartedAfterOldCleanup
        XCTAssertTrue(cleanupFinishedBeforeReplacement)
        await scheduler.stop()
    }

    func testMeasurementSchedulerStopWaitsForExplicitPriorGenerationCleanupGate() async throws {
        let oldHost = HostConfig(displayName: "Old", address: "old.example", interval: .seconds(60))
        let tracker = StrictSchedulerJoinTracker(oldHostID: oldHost.id)
        let callState = SchedulerCallState()
        let scheduler = MeasurementScheduler(probeFactory: StrictSchedulerJoinProbeFactory(tracker: tracker))
        _ = await scheduler.start(hosts: [oldHost])
        await tracker.waitUntilOldProbeStarts()

        let stopTask = Task {
            await scheduler.stop()
            await callState.recordReturn()
        }
        await tracker.waitUntilOldCancellationStarts()
        try await Task.sleep(for: .milliseconds(150))

        let stopReturnedWhileCleanupWasGated = await callState.didReturn
        XCTAssertFalse(stopReturnedWhileCleanupWasGated)

        await tracker.releaseOldCleanup()
        await stopTask.value
        let stopReturnedAfterCleanup = await callState.didReturn
        XCTAssertTrue(stopReturnedAfterCleanup)
    }

    func testSchedulerBuffersRealisticBurstWithoutDroppingResults() async throws {
        // The scheduler's result stream is bufferingNewest(1024): deep enough
        // that a realistic burst survives a stalled consumer intact -- the old
        // bufferingNewest(1) policy conflated results and skewed loss stats.
        // Two hosts each produce 150 results while nothing consumes; all 300
        // must then drain out with per-host counts exact.
        let hostA = HostConfig(displayName: "A", address: "a.example", interval: .milliseconds(1))
        let hostB = HostConfig(displayName: "B", address: "b.example", interval: .milliseconds(1))
        let perHost = 150
        let scheduler = MeasurementScheduler(probeFactory: LimitedBurstProbeFactory(limit: perHost))
        let stream = await scheduler.start(hosts: [hostA, hostB])

        // Both host loops finish their whole burst (second host starts after
        // the scheduler's 250ms stagger) before we read a single result.
        try await Task.sleep(for: .seconds(1.5))

        let expected = perHost * 2
        let consumer = Task { () -> [UUID: Int] in
            var received: [UUID: Int] = [:]
            var total = 0
            for await result in stream {
                received[result.hostID, default: 0] += 1
                total += 1
                if total == expected { break }
            }
            return received
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            consumer.cancel()
        }
        let received = await consumer.value
        deadline.cancel()

        XCTAssertEqual(received[hostA.id], perHost, "dropped results for host A: \(received)")
        XCTAssertEqual(received[hostB.id], perHost, "dropped results for host B: \(received)")
        await scheduler.stop()
    }

    func testMeasurementSchedulerLimitsConcurrentProbeMeasurements() async throws {
        let hosts = (0..<5).map { index in
            HostConfig(displayName: "Host \(index)", address: "host-\(index).example", interval: .seconds(60))
        }
        let tracker = ConcurrentProbeTracker()
        let scheduler = MeasurementScheduler(
            probeFactory: ConcurrentProbeFactory(delay: .milliseconds(700), tracker: tracker),
            maxConcurrentProbes: 2
        )
        _ = await scheduler.start(hosts: hosts)

        try await Task.sleep(for: .seconds(2))
        await scheduler.stop()

        let maxConcurrentMeasurements = await tracker.maxConcurrentMeasurements
        XCTAssertGreaterThan(maxConcurrentMeasurements, 0)
        XCTAssertLessThanOrEqual(maxConcurrentMeasurements, 2)
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

    func testRuntimeAlertBufferCoalescesUnobservedTransitionPairsToBoundBurst() async {
        let host = HostConfig(
            displayName: "Flapping",
            address: "flapping.example",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            notificationRules: NotificationRuleSet(
                cooldown: .seconds(0),
                alertTypes: [.hostDown, .recovered]
            )
        )
        // Attach a subscriber but deliberately do not request its first element;
        // the delivery queue, rather than only the pre-subscription queue, must
        // remain finite while the host flaps.
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 15_000)
        for index in 0..<400 {
            await runtime.ingest(.failure(
                hostID: host.id,
                reason: .timeout,
                timestamp: base.addingTimeInterval(Double(index * 2))
            ))
            await runtime.ingest(.success(
                hostID: host.id,
                latency: .milliseconds(8),
                timestamp: base.addingTimeInterval(Double(index * 2 + 1))
            ))
        }
        await runtime.ingest(.failure(
            hostID: host.id,
            reason: .timeout,
            timestamp: base.addingTimeInterval(1_000)
        ))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertEqual(decisions, [.hostDown(hostID: host.id)])
    }

    func testAlertBufferRetainsRecoveryForTransitionDiscardedAtCapacity() {
        let hostIDs = (0..<129).map { _ in UUID() }
        var buffer = RuntimeAlertEventBuffer(capacity: 128)
        for hostID in hostIDs {
            buffer.append(RuntimeAlertEvent(decisions: [.hostDown(hostID: hostID)], hosts: []))
        }

        buffer.append(RuntimeAlertEvent(decisions: [.recovered(hostID: hostIDs[0])], hosts: []))

        var decisions: [AlertDecision] = []
        while let event = buffer.popFirst() {
            decisions.append(contentsOf: event.decisions)
        }
        XCTAssertTrue(
            decisions.contains(.recovered(hostID: hostIDs[0])),
            "discarding an undelivered down edge must advance its tracked state so recovery is not lost"
        )
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

    func testRuntimeSuppressesPartialHostRecoveryDuringBroadOutage() async throws {
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
        // Host A recovers while Host B is still down. This used to create a
        // host-level recovery notification in the middle of an internet outage.
        await runtime.ingest(.success(hostID: hostA.id, latency: .milliseconds(8), timestamp: base.addingTimeInterval(2)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertFalse(decisions.contains(.recovered(hostID: hostA.id)), "expected partial recovery to be coalesced in \(decisions)")
        XCTAssertFalse(decisions.contains(.pathRecovered), "expected no path recovery until every outage host recovers in \(decisions)")
    }

    func testRuntimeElidedHostDownDoesNotConsumeItsCooldown() async throws {
        let host = HostConfig(
            displayName: "Example",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory())
        )
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 9_000)

        // First outage: the same-tick diagnosis supersedes the hostDown
        // transition, which is elided -- but must not burn its cooldown.
        await runtime.ingest(.failure(hostID: host.id, reason: .timeout, timestamp: base))
        await runtime.ingest(.success(hostID: host.id, latency: .milliseconds(8), timestamp: base.addingTimeInterval(10)))
        // Second outage inside hostDown's cooldown window: the diagnosis is now
        // suppressed by its own cooldown, so if the elided hostDown had consumed
        // its cooldown too, this outage would produce no notification at all.
        await runtime.ingest(.failure(hostID: host.id, reason: .timeout, timestamp: base.addingTimeInterval(60)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertTrue(decisions.contains(.hostDown(hostID: host.id)), "expected hostDown in \(decisions)")
    }

    func testRuntimeCoalescesAggregateInternetOutageAndRecoveryAlerts() async throws {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let hostA = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", thresholds: thresholds)
        let hostB = HostConfig(displayName: "Default Gateway", address: "192.168.42.1", thresholds: thresholds)
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [hostA, hostB]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            notificationRules: NotificationRuleSet(cooldown: .seconds(0), diagnosisSensitivity: .sensitive)
        )
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 11_000)

        await runtime.ingest(.failure(hostID: hostA.id, reason: .timeout, timestamp: base))
        await runtime.ingest(.failure(hostID: hostB.id, reason: .timeout, timestamp: base.addingTimeInterval(1)))
        await runtime.ingest(.success(hostID: hostA.id, latency: .milliseconds(5), timestamp: base.addingTimeInterval(2)))
        await runtime.ingest(.success(hostID: hostB.id, latency: .milliseconds(5), timestamp: base.addingTimeInterval(3)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        let broadDownCount = decisions.filter { decision in
            [.internetLoss, .localNetworkDown, .ispPathDown, .upstreamDown].contains(decision)
        }.count
        XCTAssertEqual(broadDownCount, 1, "expected one broad outage alert in \(decisions)")
        XCTAssertEqual(decisions.filter { $0 == .pathRecovered }.count, 1, "expected one path recovery alert in \(decisions)")
        XCTAssertFalse(decisions.contains(.hostDown(hostID: hostB.id)), "expected gateway hostDown to be coalesced in \(decisions)")
        XCTAssertFalse(decisions.contains(.recovered(hostID: hostA.id)), "expected first host recovery to be coalesced in \(decisions)")
        XCTAssertFalse(decisions.contains(.recovered(hostID: hostB.id)), "expected second host recovery to be coalesced in \(decisions)")
    }

    func testRuntimeDoesNotSuppressHostTransitionsWhenBroadAlertTypeIsDisabled() async throws {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let hostA = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", thresholds: thresholds)
        let hostB = HostConfig(displayName: "Google DNS", address: "8.8.8.8", thresholds: thresholds)
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [hostA, hostB]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory()),
            notificationRules: NotificationRuleSet(
                cooldown: .seconds(0),
                alertTypes: [.hostDown, .recovered],
                diagnosisSensitivity: .sensitive
            )
        )
        let alertStream = await runtime.alerts()
        let base = Date(timeIntervalSince1970: 12_000)

        await runtime.ingest(PingResult.failure(hostID: hostA.id, reason: .timeout, timestamp: base))
        await runtime.ingest(PingResult.failure(hostID: hostB.id, reason: .timeout, timestamp: base.addingTimeInterval(1)))
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertTrue(decisions.contains(AlertDecision.hostDown(hostID: hostA.id)), "expected host A down alert in \(decisions)")
        XCTAssertTrue(decisions.contains(AlertDecision.hostDown(hostID: hostB.id)), "expected host B down alert in \(decisions)")
        XCTAssertFalse(decisions.contains(AlertDecision.internetLoss), "expected disabled broad alert type to stay silent in \(decisions)")
    }

    func testRuntimeHoldsAlertsProducedBeforeAnySubscriber() async throws {
        let host = HostConfig(
            displayName: "Example",
            address: "example.com",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory())
        )

        // An outage present at launch can produce its alert before the UI's
        // alerts() subscription reaches the actor. The decision engine has
        // already committed its cooldown and edge state, so the event must be
        // held for the first subscriber, not dropped.
        await runtime.ingest(.failure(hostID: host.id, reason: .timeout))

        let alertStream = await runtime.alerts()
        await runtime.stop()

        let decisions = await collectDecisions(from: alertStream)
        XCTAssertEqual(decisions, [.remoteServiceDown(hostIDs: [host.id])])
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
            scheduler: MeasurementScheduler(probeFactory: HangingProbeFactory())
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

    func testRuntimeColorOnlyEditDoesNotRestartActiveProbeGeneration() async throws {
        let host = HostConfig(displayName: "Edge", address: "edge.example")
        let tracker = ProbeCancellationTracker()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: CancellationTrackingProbeFactory(tracker: tracker))
        )
        await runtime.start()
        try await tracker.waitUntilMeasurementStarts()

        var recolored = host
        recolored.displayColor = HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        await runtime.upsertHost(recolored)

        let cancellationCount = await tracker.cancellationCount
        XCTAssertEqual(cancellationCount, 0)
        let stream = await runtime.snapshots()
        var iterator = stream.makeAsyncIterator()
        let emittedSnapshot = await iterator.next()
        let snapshot = try XCTUnwrap(emittedSnapshot)
        XCTAssertEqual(snapshot.primaryHost?.displayColor, recolored.displayColor)
        await runtime.stop()
    }

    func testRuntimeReconcilesAcceptedRemoteColorWithoutProbeRestartOrSampleLoss() async throws {
        let host = HostConfig(displayName: "Edge", address: "edge.example")
        let tracker = ProbeCancellationTracker()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host], primaryHostID: host.id),
            scheduler: MeasurementScheduler(probeFactory: CancellationTrackingProbeFactory(tracker: tracker))
        )
        let retainedSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(17),
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        await runtime.ingest(retainedSample)
        await runtime.start()
        try await tracker.waitUntilMeasurementStarts()
        var remote = host
        remote.displayColor = HostDisplayColor(red: 0.18, green: 0.46, blue: 0.79)

        await runtime.reconcileAcceptedHostState(
            SharedHostStoreState(hosts: [remote], primaryHostID: host.id)
        )

        let reconciledStream = await runtime.snapshots()
        var iterator = reconciledStream.makeAsyncIterator()
        let maybeReconciled = await iterator.next()
        let reconciled = try XCTUnwrap(maybeReconciled)
        XCTAssertEqual(reconciled.primaryHost, remote)
        XCTAssertEqual(reconciled.primarySeries?.samples, [retainedSample])
        let cancellationCountAfterRemoteEdit = await tracker.cancellationCount
        XCTAssertEqual(cancellationCountAfterRemoteEdit, 0)

        var unrelatedLocalEdit = try XCTUnwrap(reconciled.primaryHost)
        unrelatedLocalEdit.notifications = .muted
        await runtime.upsertHost(unrelatedLocalEdit)
        let editedStream = await runtime.snapshots()
        var editedIterator = editedStream.makeAsyncIterator()
        let maybeAfterLocalEdit = await editedIterator.next()
        let afterLocalEdit = try XCTUnwrap(maybeAfterLocalEdit)
        XCTAssertEqual(afterLocalEdit.primaryHost?.displayColor, remote.displayColor)
        XCTAssertEqual(afterLocalEdit.primaryHost?.notifications, .muted)
        XCTAssertEqual(afterLocalEdit.primarySeries?.samples, [retainedSample])
        let cancellationCountAfterLocalEdit = await tracker.cancellationCount
        XCTAssertEqual(cancellationCountAfterLocalEdit, 0)
        await runtime.stop()
    }

    func testRuntimeEveryProbeEditRestartsActiveProbeGeneration() async throws {
        let edits: [(String, (inout HostConfig) -> Void)] = [
            ("address", { $0.address = "other.example" }),
            ("method", { $0.method = .udp }),
            ("port", { $0.port = 8443 }),
            ("interval", { $0.interval = .seconds(5) }),
            ("timeout", { $0.timeout = .seconds(3) }),
            ("thresholds", { $0.thresholds = LatencyThresholds(degradedMilliseconds: 250, downAfterFailures: 4) }),
        ]

        for (field, edit) in edits {
            let host = HostConfig(displayName: "Edge", address: "edge.example")
            let tracker = ProbeCancellationTracker()
            let runtime = PingRuntime(
                hostStore: HostStore(defaultHosts: [host]),
                scheduler: MeasurementScheduler(probeFactory: CancellationTrackingProbeFactory(tracker: tracker))
            )
            await runtime.start()
            try await tracker.waitUntilMeasurementStarts()

            var edited = host
            edit(&edited)
            await runtime.upsertHost(edited)

            let cancellationCount = await tracker.cancellationCount
            XCTAssertEqual(cancellationCount, 1, "\(field) must restart the probe generation")
            await runtime.stop()
        }
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

    func testHostStatusSummariesIncludeEndpointLatencyAndStatus() {
        let gateway = HostConfig(
            displayName: "Default Gateway",
            address: "192.168.42.1",
            tier: .localGateway,
            method: .tcp,
            port: 80
        )
        var health = HostHealth(hostID: gateway.id, thresholds: gateway.thresholds)
        health.ingest(.success(hostID: gateway.id, latency: .milliseconds(5.4)).withHostMetadata(from: gateway))
        let snapshot = RuntimeSnapshot(
            hosts: [gateway],
            primaryHostID: gateway.id,
            healthByHost: [gateway.id: health],
            samplesByHost: [:]
        )

        let summaries = DisplayStatePresenter().hostStatusSummaries(in: snapshot)

        XCTAssertEqual(summaries.map(\.name), ["Default Gateway"])
        XCTAssertEqual(summaries.map(\.endpoint), ["TCP 192.168.42.1:80"])
        XCTAssertEqual(summaries.map(\.statusText), ["Healthy"])
        XCTAssertEqual(summaries.map(\.latencyText), ["5ms"])
        XCTAssertEqual(summaries.map(\.color), [.green])
        XCTAssertTrue(summaries.first?.accessibilityLabel.contains("Default Gateway TCP 192.168.42.1:80 Healthy 5ms") == true)
    }

    func testHostStatusSummariesKeepHostsWithoutMeasurementsVisible() {
        let gateway = HostConfig(displayName: "Default Gateway", address: "192.168.42.1", tier: .localGateway, method: .tcp, port: 80)
        let internet = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", tier: .upstream, method: .https, port: 443)
        let snapshot = RuntimeSnapshot(
            hosts: [gateway, internet],
            primaryHostID: gateway.id,
            healthByHost: [:],
            samplesByHost: [:]
        )

        let summaries = DisplayStatePresenter().hostStatusSummaries(in: snapshot)

        XCTAssertEqual(summaries.map(\.name), ["Default Gateway", "Cloudflare DNS"])
        XCTAssertEqual(summaries.map(\.statusText), ["No Data", "No Data"])
        XCTAssertEqual(summaries.map(\.latencyText), ["--", "--"])
        XCTAssertEqual(summaries.map(\.color), [.gray, .gray])
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

private actor ProbeCancellationTracker {
    private(set) var cancellationCount = 0
    private var started = false

    func markStarted() { started = true }
    func markCancelled() { cancellationCount += 1 }

    func waitUntilMeasurementStarts() async throws {
        for _ in 0..<100 where !started {
            try await Task.sleep(for: .milliseconds(10))
        }
        if !started { throw TestTimeout() }
    }
}

private struct CancellationTrackingProbeFactory: ProbeFactory {
    let tracker: ProbeCancellationTracker

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        CancellationTrackingProbe(tracker: tracker)
    }
}

private struct CancellationTrackingProbe: PingProbe {
    let tracker: ProbeCancellationTracker

    func measure(_ host: HostConfig) async -> PingResult {
        await tracker.markStarted()
        return await withTaskCancellationHandler {
            try? await Task.sleep(for: .seconds(60))
            return .failure(hostID: host.id, reason: .timeout)
        } onCancel: {
            Task { await tracker.markCancelled() }
        }
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

private struct HostSensitiveProbeFactory: ProbeFactory {
    let hangingAddress: String

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        HostSensitiveProbe(hangingAddress: hangingAddress)
    }
}

private struct HostSensitiveProbe: PingProbe {
    let hangingAddress: String

    func measure(_ host: HostConfig) async -> PingResult {
        if host.address == hangingAddress {
            try? await Task.sleep(for: .seconds(60))
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        }
        return .success(hostID: host.id, latency: .milliseconds(12)).withHostMetadata(from: host)
    }
}

private struct RestartCleanupProbeFactory: ProbeFactory {
    let tracker: RestartCleanupTracker
    let cleanupDelay: Duration

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        RestartCleanupProbe(tracker: tracker, cleanupDelay: cleanupDelay)
    }
}

private struct RestartCleanupProbe: PingProbe {
    let tracker: RestartCleanupTracker
    let cleanupDelay: Duration

    func measure(_ host: HostConfig) async -> PingResult {
        if await tracker.isOldHost(host.id) {
            await tracker.oldProbeStarted()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await runtimeTestUncancellableSleep(for: cleanupDelay)
                await tracker.oldProbeCleanupFinished()
            }
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        }
        await tracker.newProbeStarted()
        return .success(hostID: host.id, latency: .milliseconds(12)).withHostMetadata(from: host)
    }
}

private actor RestartCleanupTracker {
    private let oldHostID: UUID
    private var oldStarted = false
    private var oldCleanupFinished = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var newStartedAfterOldCleanup = false

    init(oldHostID: UUID) {
        self.oldHostID = oldHostID
    }

    func isOldHost(_ hostID: UUID) -> Bool {
        hostID == oldHostID
    }

    func oldProbeStarted() {
        oldStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func waitUntilOldProbeStarts() async {
        guard !oldStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func oldProbeCleanupFinished() {
        oldCleanupFinished = true
    }

    func newProbeStarted() {
        newStartedAfterOldCleanup = oldCleanupFinished
    }
}

private struct StrictSchedulerJoinProbeFactory: ProbeFactory {
    let tracker: StrictSchedulerJoinTracker

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        StrictSchedulerJoinProbe(tracker: tracker)
    }
}

private struct StrictSchedulerJoinProbe: PingProbe {
    let tracker: StrictSchedulerJoinTracker

    func measure(_ host: HostConfig) async -> PingResult {
        guard await tracker.isOldHost(host.id) else {
            await tracker.newProbeStarted()
            return .success(hostID: host.id, latency: .milliseconds(12)).withHostMetadata(from: host)
        }

        await tracker.oldProbeStarted()
        await withTaskCancellationHandler {
            await tracker.waitForOldCleanupRelease()
        } onCancel: {
            Task { await tracker.oldCancellationStarted() }
        }
        await tracker.oldCleanupFinished()
        return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
    }
}

private actor StrictSchedulerJoinTracker {
    private let oldHostID: UUID
    private(set) var didNewProbeStart = false
    private(set) var newStartedAfterOldCleanup = false
    private var oldStarted = false
    private var oldCancellationDidStart = false
    private var oldCleanupDidFinish = false
    private var oldStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var oldCancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var oldCleanupReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var oldCleanupReleased = false

    init(oldHostID: UUID) {
        self.oldHostID = oldHostID
    }

    func isOldHost(_ hostID: UUID) -> Bool {
        hostID == oldHostID
    }

    func oldProbeStarted() {
        oldStarted = true
        oldStartWaiters.forEach { $0.resume() }
        oldStartWaiters.removeAll()
    }

    func oldCancellationStarted() {
        oldCancellationDidStart = true
        oldCancellationWaiters.forEach { $0.resume() }
        oldCancellationWaiters.removeAll()
    }

    func oldCleanupFinished() {
        oldCleanupDidFinish = true
    }

    func newProbeStarted() {
        didNewProbeStart = true
        newStartedAfterOldCleanup = oldCleanupDidFinish
    }

    func waitUntilOldProbeStarts() async {
        guard !oldStarted else { return }
        await withCheckedContinuation { continuation in
            oldStartWaiters.append(continuation)
        }
    }

    func waitUntilOldCancellationStarts() async {
        guard !oldCancellationDidStart else { return }
        await withCheckedContinuation { continuation in
            oldCancellationWaiters.append(continuation)
        }
    }

    func waitForOldCleanupRelease() async {
        guard !oldCleanupReleased else { return }
        await withCheckedContinuation { continuation in
            oldCleanupReleaseWaiters.append(continuation)
        }
    }

    func releaseOldCleanup() {
        oldCleanupReleased = true
        oldCleanupReleaseWaiters.forEach { $0.resume() }
        oldCleanupReleaseWaiters.removeAll()
    }
}

private actor SchedulerCallState {
    private(set) var didReturn = false

    func recordReturn() {
        didReturn = true
    }
}

private func runtimeTestUncancellableSleep(for duration: Duration) async {
    let nanoseconds = max(0, UInt64(duration.seconds * 1_000_000_000))
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
            continuation.resume()
        }
    }
}

private struct HangingProbeFactory: ProbeFactory {
    func makeProbe(for method: PingMethod) async -> any PingProbe {
        HangingProbe()
    }
}

private struct ConcurrentProbeFactory: ProbeFactory {
    let delay: Duration
    let tracker: ConcurrentProbeTracker

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        ConcurrentProbe(delay: delay, tracker: tracker)
    }
}

private struct ConcurrentProbe: PingProbe {
    private let delay: Duration
    private let tracker: ConcurrentProbeTracker

    init(delay: Duration, tracker: ConcurrentProbeTracker) {
        self.delay = delay
        self.tracker = tracker
    }

    func measure(_ host: HostConfig) async -> PingResult {
        await tracker.started()
        try? await Task.sleep(for: delay)
        await tracker.finished()
        return .success(hostID: host.id, latency: .milliseconds(5)).withHostMetadata(from: host)
    }
}

private actor ConcurrentProbeTracker {
    private var activeMeasurements = 0
    private(set) var maxConcurrentMeasurements = 0

    func started() {
        activeMeasurements += 1
        maxConcurrentMeasurements = max(maxConcurrentMeasurements, activeMeasurements)
    }

    func finished() {
        activeMeasurements -= 1
    }
}

/// Returns an instant success for the first `limit` measurements of each host,
/// then hangs, so a test can bound exactly how many results a scheduler run
/// produces per host.
private struct LimitedBurstProbeFactory: ProbeFactory {
    let probe: LimitedBurstProbe

    init(limit: Int) {
        probe = LimitedBurstProbe(limit: limit)
    }

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

private actor LimitedBurstProbe: PingProbe {
    private let limit: Int
    private var countsByHost: [UUID: Int] = [:]

    init(limit: Int) {
        self.limit = limit
    }

    func measure(_ host: HostConfig) async -> PingResult {
        guard countsByHost[host.id, default: 0] < limit else {
            try? await Task.sleep(for: .seconds(60))
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        }
        countsByHost[host.id, default: 0] += 1
        return .success(hostID: host.id, latency: .milliseconds(5)).withHostMetadata(from: host)
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

    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(stored
            .filter { $0.hostID == hostID && $0.timestamp >= since }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(1, limit)))
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

    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(stored
            .filter { $0.hostID == hostID && $0.timestamp >= since }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(1, limit)))
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

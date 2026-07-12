import XCTest
import PingScopeCore
import PingScopeiOS

final class LiveMonitorSessionControllerTests: XCTestCase {
    func testIOSRunControlSelectionMapsDurationsAndStop() {
        XCTAssertEqual(PingScopeIOSRunControlAction.selectionChanged(to: .continuous), .start(.continuous))
        XCTAssertEqual(PingScopeIOSRunControlAction.selectionChanged(to: .thirtySeconds), .start(.thirtySeconds))
        XCTAssertEqual(PingScopeIOSRunControlAction.selectionChanged(to: .oneMinute), .start(.oneMinute))
        XCTAssertEqual(PingScopeIOSRunControlAction.selectionChanged(to: nil), .stop)
    }

    func testIOSRunControlOneMinuteDoesNotMapToStop() {
        XCTAssertNotEqual(PingScopeIOSRunControlAction.selectionChanged(to: .oneMinute), .stop)
    }

    func testIOSLiveActivityDecisionDoesNothingWithoutActiveSession() {
        let hostID = UUID()

        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: false,
                previousScope: .focused,
                newScope: .allHosts,
                previousFocusedHostID: hostID,
                newFocusedHostID: hostID
            ),
            .none
        )
    }

    func testIOSLiveActivityDecisionUpdatesForOrdinaryContentRefresh() {
        let hostID = UUID()

        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: true,
                previousScope: .focused,
                newScope: .focused,
                previousFocusedHostID: hostID,
                newFocusedHostID: hostID
            ),
            .update
        )
        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: true,
                previousScope: .allHosts,
                newScope: .allHosts,
                previousFocusedHostID: hostID,
                newFocusedHostID: UUID()
            ),
            .update
        )
    }

    func testIOSLiveActivityDecisionRestartsForFocusedHostChange() {
        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: true,
                previousScope: .focused,
                newScope: .focused,
                previousFocusedHostID: UUID(),
                newFocusedHostID: UUID()
            ),
            .restart
        )
    }

    func testIOSLiveActivityDecisionRestartsAcrossHostScopes() {
        let hostID = UUID()

        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: true,
                previousScope: .focused,
                newScope: .allHosts,
                previousFocusedHostID: hostID,
                newFocusedHostID: hostID
            ),
            .restart
        )
        XCTAssertEqual(
            PingScopeIOSLiveActivityDecision.decide(
                isSessionActive: true,
                previousScope: .allHosts,
                newScope: .focused,
                previousFocusedHostID: hostID,
                newFocusedHostID: hostID
            ),
            .restart
        )
    }

    func testIOSDisplayModeDefaultsToSignalAndPersistsRing() {
        let suiteName = "PingScopeIOSDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removeObject(forKey: "pingScopeIOSDisplayMode")
        XCTAssertEqual(defaults.pingScopeIOSDisplayMode, .signal)

        defaults.pingScopeIOSDisplayMode = .ring
        XCTAssertEqual(defaults.pingScopeIOSDisplayMode, .ring)
    }

    func testInitialSessionCoordinatorAllowsActiveBackstopAfterSupersededStart() {
        var coordinator = PingScopeIOSInitialSessionCoordinator()
        var startedDurations: [MonitorSessionDuration] = []

        XCTAssertTrue(coordinator.shouldStartInitialSession)

        if coordinator.shouldStartInitialSession {
            // The original launch attempt was superseded before completion, so
            // it must not permanently mark initial monitoring as started.
        }

        XCTAssertTrue(coordinator.shouldStartInitialSession)

        if coordinator.shouldStartInitialSession {
            startedDurations.append(.continuous)
            coordinator.markInitialSessionStarted()
        }

        XCTAssertEqual(startedDurations, [.continuous])
        XCTAssertFalse(coordinator.shouldStartInitialSession)
    }

    func testInitialSessionCoordinatorDoesNotRetryAfterExplicitSessionAction() {
        var coordinator = PingScopeIOSInitialSessionCoordinator()

        coordinator.markExplicitSessionAction()

        XCTAssertFalse(coordinator.shouldStartInitialSession)
    }

    func testControllerStartsFiniteSessionAndPublishesProbeResult() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        // The loop has probed exactly once when it parks on the clock.
        try await clock.waitForSleepers(atLeast: 1)

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .thirtySeconds)
        XCTAssertEqual(snapshot.session?.phase(at: clock.currentDate), .live)
        XCTAssertEqual(snapshot.health.status, HealthStatus.healthy)
        XCTAssertEqual(snapshot.health.latestResult?.latency?.milliseconds.rounded(), 18)
        XCTAssertEqual(snapshot.series.samples.count, 1)
        XCTAssertEqual(snapshot.series.stats.received, 1)
        let measurementCount = await probe.measurementCount
        XCTAssertEqual(measurementCount, 1)
    }

    func testControllerDefaultStartUsesInjectedDateProvider() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds)
        try await clock.waitForSleepers(atLeast: 1)

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.startedAt, clock.baseDate)
    }

    func testControllerDefaultStopUsesInjectedDateProvider() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(25))
        await controller.stop(reason: .userStopped)

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.endedAt, clock.currentDate)
    }

    func testControllerWritesMeasuredSamplesToHistoryStore() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let history = RecordingLiveMonitorHistoryStore()
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(50)),
            historyStore: history,
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        // The write buffer's delayed flush has not fired; nothing is stored yet.
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
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(50)),
            historyStore: history,
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
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
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(100)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        let firstSnapshot = await controller.snapshot()
        XCTAssertEqual(firstSnapshot.series.samples.count, 1)

        // Restart cancels the first loop's parked sleep synchronously, so the
        // next sleeper the clock sees belongs to the new session's loop.
        await controller.start(duration: .oneMinute, at: clock.currentDate)
        try await clock.waitForSleepers(atLeast: 1)

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
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .oneMinute, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        await controller.stop(reason: .userStopped, at: clock.currentDate)
        let countAfterStop = await probe.measurementCount
        XCTAssertEqual(countAfterStop, 1)
        // Advancing past several probe intervals must not wake the cancelled
        // loop back up.
        clock.advance(by: .milliseconds(50))
        await Task.yield()

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.phase(at: clock.currentDate), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .userStopped)
        let finalCount = await probe.measurementCount
        XCTAssertEqual(finalCount, countAfterStop)
    }

    func testControllerIgnoresLateProbeResultAfterStop() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = BlockingProbe()
        let now = Date(timeIntervalSince1970: 1_000)
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: BlockingProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            now: { now }
        )

        await controller.start(duration: .oneMinute, at: now)
        try await probe.waitForMeasurements(atLeast: 1)
        await controller.stop(reason: .userStopped, at: now.addingTimeInterval(1))

        await probe.releaseNext(.success(hostID: host.id, latency: .milliseconds(18)))
        try await Task.sleep(for: .milliseconds(20))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.endReason, .userStopped)
        XCTAssertEqual(snapshot.series.samples.count, 0)
        XCTAssertNil(snapshot.health.latestResult)
    }

    func testControllerIgnoresLateProbeResultFromPreviousSessionAfterRestart() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = BlockingProbe()
        let now = Date(timeIntervalSince1970: 1_000)
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: BlockingProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            now: { now }
        )

        await controller.start(duration: .thirtySeconds, at: now)
        try await probe.waitForMeasurements(atLeast: 1)
        await controller.start(duration: .oneMinute, at: now.addingTimeInterval(1))
        try await probe.waitForMeasurements(atLeast: 2)

        await probe.releaseNext(.success(hostID: host.id, latency: .milliseconds(18)))
        await probe.releaseNext(.success(hostID: host.id, latency: .milliseconds(19)))
        try await Task.sleep(for: .milliseconds(20))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .oneMinute)
        XCTAssertEqual(snapshot.series.samples.count, 1)
        XCTAssertEqual(snapshot.series.samples.first?.latency, .milliseconds(19))
        await controller.stop(reason: .userStopped, at: now.addingTimeInterval(2))
    }

    func testControllerContinuousSessionRunsUntilStopped() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18)),
            .success(hostID: host.id, latency: .milliseconds(19)),
            .success(hostID: host.id, latency: .milliseconds(20))
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .continuous, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await clock.waitForSleepers(atLeast: 1)

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .continuous)
        XCTAssertEqual(snapshot.session?.phase(at: clock.currentDate), .live)
        XCTAssertEqual(snapshot.series.samples.count, 2)
    }

    func testControllerEndsWhenBackgroundRuntimeExpiresBeforeSelectedDuration() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            backgroundRuntimeLimit: .milliseconds(35),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .oneMinute, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        // 10ms elapsed: still inside the 35ms budget, so a second probe runs.
        clock.advance(by: .milliseconds(10))
        try await clock.waitForSleepers(atLeast: 1)
        // 40ms elapsed: past the budget, so the loop finishes instead of probing.
        clock.advance(by: .milliseconds(30))

        var snapshot = await controller.snapshot()
        var attempts = 0
        while snapshot.session?.endReason == nil, attempts < 200 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(5))
            snapshot = await controller.snapshot()
        }

        XCTAssertEqual(snapshot.session?.phase(at: clock.currentDate), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .backgroundRuntimeExpired)
        let measurementCount = await probe.measurementCount
        XCTAssertEqual(measurementCount, 2)
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

    func testIOSHostStorePersistsAllHostsIndependentlyFromConcreteSelection() {
        let suite = "PingScopeIOSHostScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PingScopeIOSHostStore(defaults: defaults)
        let hosts = PingScopeIOSHostStore.defaultHosts

        store.save(hosts: hosts, selectedHostID: hosts[1].id, hostScope: .allHosts)

        let state = store.load()
        XCTAssertEqual(state.hostScope, .allHosts)
        XCTAssertEqual(state.selectedHost.id, hosts[1].id)
    }

    func testIOSHostStorePreservesAllHostsThroughHostMutationSaves() {
        let suite = "PingScopeIOSHostScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8"),
            HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1")
        ]
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts)
        let selectedHostID = hosts[1].id

        store.save(hosts: hosts, selectedHostID: selectedHostID, hostScope: .allHosts)

        let reordered = PingScopeIOSHostOrdering.reordered(hosts: hosts, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.save(hosts: reordered, selectedHostID: selectedHostID)
        XCTAssertEqual(store.load().hostScope, .allHosts)

        var edited = reordered
        edited[0].displayName = "Edited Router"
        store.save(hosts: edited, selectedHostID: selectedHostID)
        XCTAssertEqual(store.load().hostScope, .allHosts)

        let deleted = Array(edited.dropFirst())
        store.save(hosts: deleted, selectedHostID: selectedHostID)
        XCTAssertEqual(store.load().hostScope, .allHosts)

        var disabled = deleted
        disabled[0].isEnabled = false
        store.save(hosts: disabled, selectedHostID: selectedHostID)
        let state = store.load()
        XCTAssertEqual(state.hostScope, .allHosts)
        XCTAssertEqual(state.selectedHost.id, selectedHostID)
        XCTAssertFalse(state.hosts[0].isEnabled)
    }

    func testIOSHostStoreDefaultsMissingScopeToFocusedWithExistingStoredValues() {
        let suite = "PingScopeIOSHostScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hosts = PingScopeIOSHostStore.defaultHosts

        defaults.set(try! JSONEncoder().encode(hosts), forKey: "PingScope.iOS.hosts")
        defaults.set(hosts[0].id.uuidString, forKey: "PingScope.iOS.selectedHostID")
        XCTAssertNil(defaults.object(forKey: "PingScope.iOS.hostScope"))

        let state = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts).load()
        XCTAssertEqual(state.hostScope, .focused)
        XCTAssertEqual(state.selectedHost.id, hosts[0].id)
    }

    func testIOSHostStoreDefaultsInvalidScopeToFocused() {
        let suite = "PingScopeIOSHostScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hosts = PingScopeIOSHostStore.defaultHosts
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts)

        defaults.set("unsupported", forKey: "PingScope.iOS.hostScope")
        XCTAssertEqual(store.load().hostScope, .focused)
    }

    func testIOSHostOrderingReordersAndPreservesSelectedHostWhenPersisted() {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8"),
            HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1")
        ]
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: hosts)

        let reordered = PingScopeIOSHostOrdering.reordered(hosts: hosts, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        store.save(hosts: reordered, selectedHostID: hosts[1].id)
        let state = store.load()

        XCTAssertEqual(state.hosts.map(\.id), [hosts[2].id, hosts[0].id, hosts[1].id])
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

    func testIOSHostStoreFallsBackToDefaultsWhenSavedHostsAreInvalid() {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsHosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        ]
        let invalidHosts = [
            HostConfig(id: UUID(), displayName: " ", address: " ")
        ]
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: defaultsHosts)

        store.save(hosts: invalidHosts, selectedHostID: invalidHosts[0].id)
        let state = store.load()

        XCTAssertEqual(state.hosts, defaultsHosts)
        XCTAssertEqual(state.selectedHost.id, defaultsHosts[0].id)
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

    func testIOSAllHostsCoordinatorFansOutToEnabledHostsInSavedOrder() async {
        let enabledA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let disabledB = HostConfig(id: UUID(), displayName: "Disabled", address: "8.8.8.8", isEnabled: false)
        let enabledC = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let factory = RecordingIOSAllHostsControllerFactory(statuses: [
            enabledA.id: .healthy,
            enabledC.id: .down
        ])
        let startedAt = Date(timeIntervalSince1970: 20_000)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: factory,
            now: { startedAt }
        )

        await coordinator.reconcile(hosts: [enabledA, disabledB, enabledC])
        await coordinator.start(duration: .oneMinute)

        let createdHostIDs = await factory.createdHostIDs
        let startedHostIDs = await factory.startedHostIDs
        let startedDurations = await factory.startedDurations
        let snapshots = await coordinator.snapshots()
        let aggregateHealth = await coordinator.aggregateHealth()
        XCTAssertEqual(createdHostIDs, [enabledA.id, enabledC.id])
        XCTAssertEqual(startedHostIDs, [enabledA.id, enabledC.id])
        XCTAssertEqual(startedDurations, [.oneMinute, .oneMinute])
        XCTAssertEqual(snapshots[enabledA.id]?.host.id, enabledA.id)
        XCTAssertEqual(snapshots[enabledC.id]?.host.id, enabledC.id)
        XCTAssertNil(snapshots[disabledB.id])
        XCTAssertEqual(aggregateHealth, .down)

        let session = await coordinator.session()
        XCTAssertEqual(session?.duration, .oneMinute)
        XCTAssertEqual(session?.startedAt, startedAt)
        XCTAssertEqual(session?.remainingDuration(at: startedAt), .seconds(60))
    }

    func testIOSAllHostsCoordinatorStopsAndFlushesRemovedOrDisabledControllersBeforeDroppingThem() async {
        let enabledA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let enabledB = HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        let enabledC = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [enabledA, enabledB, enabledC])
        await coordinator.start(duration: .continuous)
        await coordinator.reconcile(hosts: [enabledA, HostConfig(
            id: enabledB.id,
            displayName: enabledB.displayName,
            address: enabledB.address,
            isEnabled: false
        )])

        let stoppedHostIDs = await factory.stoppedAndFlushedHostIDs
        let snapshots = await coordinator.snapshots()
        XCTAssertEqual(stoppedHostIDs, [enabledB.id, enabledC.id])
        XCTAssertEqual(Set(snapshots.keys), Set([enabledA.id]))
    }

    func testIOSAllHostsCoordinatorStopsEveryActiveControllerWithOneReason() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostA, hostB])
        await coordinator.start(duration: .thirtySeconds)
        await coordinator.stop(reason: .backgroundRuntimeExpired)

        let stoppedHostIDs = await factory.stoppedAndFlushedHostIDs
        let stopReasons = await factory.stopReasons
        let session = await coordinator.session()
        XCTAssertEqual(stoppedHostIDs, [hostA.id, hostB.id])
        XCTAssertEqual(stopReasons, [.backgroundRuntimeExpired, .backgroundRuntimeExpired])
        XCTAssertEqual(session?.endReason, .backgroundRuntimeExpired)
    }

    func testIOSAllHostsCoordinatorDropsRemovedControllerAfterStopFlushCompletes() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let stopGate = IOSAllHostsStopGate()
        let factory = RecordingIOSAllHostsControllerFactory(stopGate: stopGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        let reconciliation = Task {
            await coordinator.reconcile(hosts: [])
        }
        await stopGate.waitForStop()

        let snapshotsDuringStop = await coordinator.snapshots()
        XCTAssertEqual(snapshotsDuringStop[host.id]?.host.id, host.id)

        await stopGate.release()
        await reconciliation.value

        let snapshotsAfterStop = await coordinator.snapshots()
        XCTAssertNil(snapshotsAfterStop[host.id])
    }

    func testIOSAllHostsCoordinatorSerializesOverlappingStartAndStop() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let startGate = IOSAllHostsStartGate()
        let factory = RecordingIOSAllHostsControllerFactory(startGate: startGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        let start = Task {
            await coordinator.start(duration: .continuous)
        }
        await startGate.waitForStart()

        let stop = Task {
            await coordinator.stop(reason: .userStopped)
        }
        for _ in 0..<100 where await factory.stopCount == 0 {
            await Task.yield()
        }
        await startGate.release()
        await start.value
        await stop.value

        let createdControllerTokens = await factory.createdControllerTokens
        let controllerToken = try! XCTUnwrap(createdControllerTokens.first)
        let events = await factory.events
        let isRunning = await factory.isRunning(controllerToken: controllerToken)
        XCTAssertFalse(isRunning)
        XCTAssertEqual(events, [.startBegan(controllerToken), .startFinished(controllerToken), .stopped(controllerToken)])
    }

    func testIOSAllHostsCoordinatorSerializesOverlappingReplacementAndRemovalReconciliations() async {
        let original = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        var replacement = original
        replacement.address = "1.0.0.1"
        let firstStopGate = IOSAllHostsFirstStopGate()
        let factory = RecordingIOSAllHostsControllerFactory(firstStopGate: firstStopGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let removalCompleted = IOSAllHostsCompletion()

        await coordinator.reconcile(hosts: [original])
        let replacementReconciliation = Task {
            await coordinator.reconcile(hosts: [replacement])
        }
        await firstStopGate.waitForFirstStop()

        let removalReconciliation = Task {
            await coordinator.reconcile(hosts: [])
            await removalCompleted.markComplete()
        }
        for _ in 0..<100 where !(await removalCompleted.isComplete) {
            await Task.yield()
        }

        let completedBeforeFirstReconcileFinished = await removalCompleted.isComplete
        XCTAssertFalse(completedBeforeFirstReconcileFinished)
        await firstStopGate.release()
        await replacementReconciliation.value
        await removalReconciliation.value

        let snapshots = await coordinator.snapshots()
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testIOSAllHostsCoordinatorProcessesCancelledQueuedStopAndKeepsTransactionQueueUsable() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let startGate = IOSAllHostsStartGate()
        let factory = RecordingIOSAllHostsControllerFactory(startGate: startGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        let start = Task {
            await coordinator.start(duration: .continuous)
        }
        await startGate.waitForStart()
        let cancelledStop = Task {
            await coordinator.stop(reason: .userStopped)
        }
        cancelledStop.cancel()

        await startGate.release()
        await start.value
        await cancelledStop.value
        await coordinator.reconcile(hosts: [host])

        let events = await factory.events
        let orderedSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(events, [.startBegan(1), .startFinished(1), .stopped(1)])
        XCTAssertEqual(orderedSnapshots.map(\.host.id), [host.id])
    }

    func testIOSAllHostsCoordinatorReturnsOrderedSnapshotsInSavedHostOrder() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let disabledB = HostConfig(id: UUID(), displayName: "Disabled", address: "8.8.8.8", isEnabled: false)
        let hostC = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostC, disabledB, hostA])

        let orderedSnapshots = await coordinator.orderedSnapshots()
        let snapshotsByHostID = await coordinator.snapshotsByHostID()
        XCTAssertEqual(orderedSnapshots.map(\.host.id), [hostC.id, hostA.id])
        XCTAssertEqual(Set(snapshotsByHostID.keys), Set([hostC.id, hostA.id]))
    }

    func testIOSAllHostsCoordinatorReorderPreservesControllerIdentity() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostA, hostB])
        let controllerTokensBeforeReorder = await factory.createdControllerTokens
        await coordinator.reconcile(hosts: [hostB, hostA])

        let controllerTokensAfterReorder = await factory.createdControllerTokens
        let stoppedHostIDs = await factory.stoppedAndFlushedHostIDs
        let orderedSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(controllerTokensBeforeReorder, [1, 2])
        XCTAssertEqual(controllerTokensAfterReorder, controllerTokensBeforeReorder)
        XCTAssertTrue(stoppedHostIDs.isEmpty)
        XCTAssertEqual(orderedSnapshots.map(\.host.id), [hostB.id, hostA.id])
    }

    func testIOSAllHostsCoordinatorReplacesEditedHostAfterStoppingOldController() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        var editedHost = host
        editedHost.address = "1.0.0.1"
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        await coordinator.reconcile(hosts: [editedHost])

        let createdControllerTokens = await factory.createdControllerTokens
        let stoppedControllerTokens = await factory.stoppedControllerTokens
        let stoppedHostIDs = await factory.stoppedAndFlushedHostIDs
        let orderedSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(createdControllerTokens, [1, 2])
        XCTAssertEqual(stoppedControllerTokens, [1])
        XCTAssertEqual(stoppedHostIDs, [host.id])
        XCTAssertEqual(orderedSnapshots.first?.host.address, editedHost.address)
    }

    func testIOSAllHostsCoordinatorUsesCommonStartAndStopTimestampsForAddedHost() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let clock = ManualClock(baseDate: Date(timeIntervalSince1970: 50_000))
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: factory,
            now: { clock.currentDate }
        )

        await coordinator.reconcile(hosts: [hostA])
        await coordinator.start(duration: .oneMinute)
        clock.advance(by: .seconds(10))
        await coordinator.reconcile(hosts: [hostA, hostB])
        clock.advance(by: .seconds(2))
        await coordinator.stop(reason: .backgroundRuntimeExpired)

        let startRecords = await factory.startRecords
        let stopRecords = await factory.stopRecords
        XCTAssertEqual(startRecords.map(\.hostID), [hostA.id, hostB.id])
        XCTAssertEqual(startRecords.map(\.duration), [.oneMinute, .oneMinute])
        XCTAssertEqual(startRecords.map(\.date), [clock.baseDate, clock.baseDate])
        XCTAssertEqual(stopRecords.map(\.hostID), [hostA.id, hostB.id])
        XCTAssertEqual(stopRecords.map(\.date), [clock.baseDate.addingTimeInterval(12), clock.baseDate.addingTimeInterval(12)])
    }

    func testIOSAllHostsCoordinatorSnapshotCollectionUsesSingleCapturedTopology() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let originalHostB = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        var replacementHostB = originalHostB
        replacementHostB.address = "192.168.1.254"
        let snapshotGate = IOSAllHostsFirstSnapshotGate()
        let factory = RecordingIOSAllHostsControllerFactory(snapshotGate: snapshotGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostA, originalHostB])
        let inFlightSnapshots = Task {
            await coordinator.orderedSnapshots()
        }
        await snapshotGate.waitForFirstSnapshot()

        await coordinator.reconcile(hosts: [hostA, replacementHostB])
        await snapshotGate.release()

        let capturedSnapshots = await inFlightSnapshots.value
        let currentSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(capturedSnapshots.map(\.host.address), [hostA.address, originalHostB.address])
        XCTAssertEqual(currentSnapshots.map(\.host.address), [hostA.address, replacementHostB.address])
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

private actor BlockingProbe: PingProbe {
    private var continuations: [CheckedContinuation<PingResult, Never>] = []
    private(set) var measurementCount = 0

    func measure(_ host: HostConfig) async -> PingResult {
        measurementCount += 1
        let result = await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return result.withHostMetadata(from: host)
    }

    func waitForMeasurements(atLeast expectedCount: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while measurementCount < expectedCount {
            if Date() > deadline {
                XCTFail("timed out waiting for \(expectedCount) measurements")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func releaseNext(_ result: PingResult) {
        guard !continuations.isEmpty else {
            XCTFail("no pending blocked probe measurement")
            return
        }
        continuations.removeFirst().resume(returning: result)
    }
}

private struct BlockingProbeFactory: ProbeFactory {
    let probe: BlockingProbe

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

private actor RecordingIOSAllHostsControllerFactory: PingScopeIOSMultiHostSessionControllerFactory {
    private let statuses: [UUID: HealthStatus]
    private let startGate: IOSAllHostsStartGate?
    private let stopGate: IOSAllHostsStopGate?
    private let firstStopGate: IOSAllHostsFirstStopGate?
    private let snapshotGate: IOSAllHostsFirstSnapshotGate?
    private var nextControllerToken = 0
    private var runningByControllerToken: [Int: Bool] = [:]
    private(set) var createdHostIDs: [UUID] = []
    private(set) var createdControllerTokens: [Int] = []
    private(set) var startedHostIDs: [UUID] = []
    private(set) var startedDurations: [MonitorSessionDuration] = []
    private(set) var startRecords: [IOSAllHostsStartRecord] = []
    private(set) var stoppedAndFlushedHostIDs: [UUID] = []
    private(set) var stoppedControllerTokens: [Int] = []
    private(set) var stopReasons: [MonitorSessionEndReason] = []
    private(set) var stopRecords: [IOSAllHostsStopRecord] = []
    private(set) var events: [IOSAllHostsControllerEvent] = []

    init(
        statuses: [UUID: HealthStatus] = [:],
        startGate: IOSAllHostsStartGate? = nil,
        stopGate: IOSAllHostsStopGate? = nil,
        firstStopGate: IOSAllHostsFirstStopGate? = nil,
        snapshotGate: IOSAllHostsFirstSnapshotGate? = nil
    ) {
        self.statuses = statuses
        self.startGate = startGate
        self.stopGate = stopGate
        self.firstStopGate = firstStopGate
        self.snapshotGate = snapshotGate
    }

    func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?
    ) async -> any PingScopeIOSMultiHostSessionControlling {
        nextControllerToken += 1
        createdHostIDs.append(host.id)
        createdControllerTokens.append(nextControllerToken)
        runningByControllerToken[nextControllerToken] = false
        return RecordingIOSAllHostsController(host: host, controllerToken: nextControllerToken, factory: self)
    }

    var stopCount: Int {
        stoppedAndFlushedHostIDs.count
    }

    func recordStart(hostID: UUID, controllerToken: Int, duration: MonitorSessionDuration, at date: Date) async {
        startedHostIDs.append(hostID)
        startedDurations.append(duration)
        startRecords.append(IOSAllHostsStartRecord(hostID: hostID, duration: duration, date: date))
        events.append(.startBegan(controllerToken))
        await startGate?.recordStart()
        await startGate?.waitForRelease()
        runningByControllerToken[controllerToken] = true
        events.append(.startFinished(controllerToken))
    }

    func recordStop(hostID: UUID, controllerToken: Int, reason: MonitorSessionEndReason, at date: Date) async {
        stoppedAndFlushedHostIDs.append(hostID)
        stoppedControllerTokens.append(controllerToken)
        stopReasons.append(reason)
        stopRecords.append(IOSAllHostsStopRecord(hostID: hostID, reason: reason, date: date))
        runningByControllerToken[controllerToken] = false
        events.append(.stopped(controllerToken))
        let blocksFirstStop = await firstStopGate?.recordStop() ?? false
        await stopGate?.recordStop()
        if blocksFirstStop {
            await firstStopGate?.waitForRelease()
        }
        await stopGate?.waitForRelease()
    }

    func isRunning(controllerToken: Int) -> Bool {
        runningByControllerToken[controllerToken] ?? false
    }

    func snapshot(for host: HostConfig) async -> LiveMonitorSessionSnapshot {
        if await snapshotGate?.recordSnapshot() == true {
            await snapshotGate?.waitForRelease()
        }

        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.status = statuses[host.id] ?? .noData
        return LiveMonitorSessionSnapshot(host: host, session: nil, health: health)
    }
}

private actor RecordingIOSAllHostsController: PingScopeIOSMultiHostSessionControlling {
    private let host: HostConfig
    private let controllerToken: Int
    private let factory: RecordingIOSAllHostsControllerFactory

    init(host: HostConfig, controllerToken: Int, factory: RecordingIOSAllHostsControllerFactory) {
        self.host = host
        self.controllerToken = controllerToken
        self.factory = factory
    }

    func start(duration: MonitorSessionDuration, at date: Date) async {
        await factory.recordStart(hostID: host.id, controllerToken: controllerToken, duration: duration, at: date)
    }

    func stop(reason: MonitorSessionEndReason, at date: Date) async {
        await factory.recordStop(hostID: host.id, controllerToken: controllerToken, reason: reason, at: date)
    }

    func snapshot() async -> LiveMonitorSessionSnapshot {
        await factory.snapshot(for: host)
    }
}

private actor IOSAllHostsStopGate {
    private var stopRecorded = false
    private var released = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStop() {
        stopRecorded = true
        stopWaiters.forEach { $0.resume() }
        stopWaiters.removeAll()
    }

    func waitForStop() async {
        while !stopRecorded {
            await withCheckedContinuation { continuation in
                stopWaiters.append(continuation)
            }
        }
    }

    func waitForRelease() async {
        while !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private enum IOSAllHostsControllerEvent: Equatable {
    case startBegan(Int)
    case startFinished(Int)
    case stopped(Int)
}

private struct IOSAllHostsStartRecord: Equatable {
    let hostID: UUID
    let duration: MonitorSessionDuration
    let date: Date
}

private struct IOSAllHostsStopRecord: Equatable {
    let hostID: UUID
    let reason: MonitorSessionEndReason
    let date: Date
}

private actor IOSAllHostsStartGate {
    private var startRecorded = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        startRecorded = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
    }

    func waitForStart() async {
        while !startRecorded {
            await withCheckedContinuation { continuation in
                startWaiters.append(continuation)
            }
        }
    }

    func waitForRelease() async {
        while !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor IOSAllHostsFirstStopGate {
    private var stopCount = 0
    private var released = false
    private var firstStopWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStop() -> Bool {
        stopCount += 1
        if stopCount == 1 {
            firstStopWaiters.forEach { $0.resume() }
            firstStopWaiters.removeAll()
            return true
        }
        return false
    }

    func waitForFirstStop() async {
        while stopCount == 0 {
            await withCheckedContinuation { continuation in
                firstStopWaiters.append(continuation)
            }
        }
    }

    func waitForRelease() async {
        while !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor IOSAllHostsFirstSnapshotGate {
    private var snapshotCount = 0
    private var released = false
    private var firstSnapshotWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func recordSnapshot() -> Bool {
        snapshotCount += 1
        guard snapshotCount == 1 else { return false }

        firstSnapshotWaiters.forEach { $0.resume() }
        firstSnapshotWaiters.removeAll()
        return true
    }

    func waitForFirstSnapshot() async {
        while snapshotCount == 0 {
            await withCheckedContinuation { continuation in
                firstSnapshotWaiters.append(continuation)
            }
        }
    }

    func waitForRelease() async {
        while !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor IOSAllHostsCompletion {
    private(set) var isComplete = false

    func markComplete() {
        isComplete = true
    }
}

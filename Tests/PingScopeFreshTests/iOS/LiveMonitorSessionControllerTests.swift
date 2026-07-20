import XCTest
import PingScopeCore
@testable import PingScopeiOS

final class LiveMonitorSessionControllerTests: XCTestCase {
    func testContinuousLiveActivityUpdateKeepsRollingStaleDeadline() {
        let now = Date(timeIntervalSince1970: 10_000)

        let staleDate = PingScopeIOSLiveActivityStaleness.updateStaleDate(
            override: nil,
            scheduledEndAt: nil,
            now: now
        )

        XCTAssertEqual(
            staleDate,
            now.addingTimeInterval(PingScopeIOSPausedLiveActivityState.staleInterval)
        )
    }

    func testIOSHostEditorDraftAcceptsAndRoundTripsHTTPSWithDefaultPort() {
        var draft = PingScopeIOSHostDraft(
            host: HostConfig(displayName: "Web", address: "example.com", method: .tcp, port: 80)
        )

        draft.apply(method: .https)

        XCTAssertTrue(PingMethod.appStoreAvailableCases.contains(.https))
        XCTAssertEqual(draft.method, .https)
        XCTAssertEqual(draft.portText, "443")
        XCTAssertEqual(draft.finalizedHost.method, .https)
        XCTAssertEqual(draft.finalizedHost.port, 443)
    }
    func testIOSLiveActivityUpdatePolicySuppressesDuplicateContentUntilItChanges() {
        var policy = PingScopeIOSLiveActivityUpdatePolicy(minimumUpdateInterval: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        let initial = PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: 12,
            status: .healthy,
            lastUpdatedAt: Date(timeIntervalSince1970: 100),
            remainingSeconds: 0,
            isStale: false
        )

        XCTAssertTrue(policy.shouldPublish(initial, at: start))
        XCTAssertFalse(policy.shouldPublish(initial, at: start.addingTimeInterval(1)))

        var changed = initial
        changed.latencyMilliseconds = 18
        XCTAssertFalse(policy.shouldPublish(changed, at: start.addingTimeInterval(1)))
        XCTAssertTrue(policy.shouldPublish(changed, at: start.addingTimeInterval(10)))
        XCTAssertFalse(policy.shouldPublish(changed, at: start.addingTimeInterval(11)))

        var degraded = changed
        degraded.status = .degraded
        XCTAssertTrue(policy.shouldPublish(degraded, at: start.addingTimeInterval(11)))

        policy.reset()
        XCTAssertTrue(policy.shouldPublish(changed, at: start.addingTimeInterval(12)))
    }

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

    @MainActor
    func testBackgroundExpirationWithKeepAlivePublishesRollingStaleDeadlineWithoutStopping() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let recorder = IOSLiveActivityRuntimeRecorder(activityID: "activity-1")

        await PingScopeIOSLiveActivityRuntimeOrchestrator.expireForBackgroundRuntime(
            keepAliveActive: true,
            at: now,
            publishContinuous: { staleDate in recorder.recordContinuous(staleDate: staleDate) },
            publishPaused: { recorder.record("paused") },
            stopMonitoring: { recorder.record("stopped") },
            persistSnapshotAndHistory: { recorder.record("persisted") }
        )

        XCTAssertEqual(recorder.events, ["continuous"])
        XCTAssertEqual(
            recorder.lastStaleDate,
            now.addingTimeInterval(PingScopeIOSPausedLiveActivityState.staleInterval)
        )
    }

    @MainActor
    func testBackgroundExpirationPublishesPausedActivityBeforeStoppingAndPersistence() async {
        let recorder = IOSLiveActivityRuntimeRecorder(activityID: "activity-1")

        await PingScopeIOSLiveActivityRuntimeOrchestrator.expireForBackgroundRuntime(
            keepAliveActive: false,
            at: Date(timeIntervalSince1970: 1_000),
            publishContinuous: { _ in recorder.record("continuous") },
            publishPaused: { recorder.record("paused") },
            stopMonitoring: { recorder.record("stopped") },
            persistSnapshotAndHistory: { recorder.record("persisted") }
        )

        XCTAssertEqual(recorder.events, ["paused", "stopped", "persisted"])
        XCTAssertEqual(recorder.activityID, "activity-1")
    }

    @MainActor
    func testForegroundAfterBackgroundPauseReusesSameLiveActivityID() async {
        let recorder = IOSLiveActivityRuntimeRecorder(activityID: "activity-1")

        let resumedID = await PingScopeIOSLiveActivityRuntimeOrchestrator.resumeOnForeground(
            releaseIfDefunct: { recorder.record("released-defunct") },
            currentActivityID: { recorder.activityID },
            updateExisting: { recorder.record("updated:activity-1") },
            requestActivity: { recorder.request("activity-2") }
        )

        XCTAssertEqual(resumedID, "activity-1")
        XCTAssertEqual(recorder.events, ["released-defunct", "updated:activity-1"])
    }

    @MainActor
    func testForegroundReplacesActivityThatBecomesDefunctDuringResume() async {
        let recorder = IOSLiveActivityRuntimeRecorder(activityID: "activity-1")

        let resumedID = await PingScopeIOSLiveActivityRuntimeOrchestrator.resumeOnForeground(
            releaseIfDefunct: { recorder.record("released-defunct") },
            currentActivityID: { recorder.activityID },
            updateExisting: {
                recorder.record("update-lost")
                recorder.activityID = nil
            },
            requestActivity: { recorder.request("activity-2") }
        )

        XCTAssertEqual(resumedID, "activity-2")
        XCTAssertEqual(
            recorder.events,
            ["released-defunct", "update-lost", "requested:activity-2"]
        )
    }

    @MainActor
    func testExplicitStopAndFiniteCompletionEndButScopeSuspensionAndBackgroundExpirationDoNot() async {
        let recorder = IOSLiveActivityRuntimeRecorder(activityID: "activity-1")

        let stopped = await PingScopeIOSLiveActivityRuntimeOrchestrator.finishSession(
            reason: .userStopped
        ) { recorder.record("ended:user") }
        let completed = await PingScopeIOSLiveActivityRuntimeOrchestrator.finishSession(
            reason: .completed
        ) { recorder.record("ended:completed") }
        let expired = await PingScopeIOSLiveActivityRuntimeOrchestrator.finishSession(
            reason: .backgroundRuntimeExpired
        ) { recorder.record("ended:background") }
        let suspended = await PingScopeIOSLiveActivityRuntimeOrchestrator.finishSession(
            reason: .scopeSuspended
        ) { recorder.record("ended:scope") }

        XCTAssertTrue(stopped)
        XCTAssertTrue(completed)
        XCTAssertFalse(expired)
        XCTAssertFalse(suspended)
        XCTAssertEqual(recorder.events, ["ended:user", "ended:completed"])
    }

    @MainActor
    func testIOSLifecycleQueueCompletesBlockedScopeTransitionBeforeBackgroundAndActive() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let coordinatorStopGate = IOSAllHostsStopGate()
        let factory = RecordingIOSAllHostsControllerFactory(stopGate: coordinatorStopGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let queue = PingScopeIOSLifecycleOperationQueue()
        let state = IOSLifecycleTestState()

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        queue.enqueue {
            state.events.append("scope-stop-began")
            await coordinator.stop(reason: .userStopped)
            state.scope = .allHosts
            state.events.append(contentsOf: ["scope-committed", "refreshed", "activity-restored", "keepalive-restored"])
        }
        await coordinatorStopGate.waitForStop()

        queue.enqueue {
            state.events.append("background")
        }
        queue.enqueue {
            state.events.append("active")
        }
        await Task.yield()

        XCTAssertEqual(state.scope, .focused)
        XCTAssertEqual(state.events, ["scope-stop-began"])

        await coordinatorStopGate.release()
        await queue.waitForIdle()

        let stopReasons = await factory.stopReasons
        XCTAssertEqual(state.scope, .allHosts)
        XCTAssertEqual(stopReasons, [.userStopped])
        XCTAssertEqual(state.events, [
            "scope-stop-began",
            "scope-committed",
            "refreshed",
            "activity-restored",
            "keepalive-restored",
            "background",
            "active"
        ])
    }

    @MainActor
    func testIOSLifecycleQueueCompletesStartPostconditionsBeforeOverlappingMutation() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let coordinatorStartGate = IOSAllHostsStartGate()
        let factory = RecordingIOSAllHostsControllerFactory(startGate: coordinatorStartGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let queue = PingScopeIOSLifecycleOperationQueue()
        let state = IOSLifecycleTestState()

        await coordinator.reconcile(hosts: [hostA])
        queue.enqueue {
            state.events.append("start-began")
            await coordinator.start(duration: .continuous)
            state.events.append(contentsOf: ["start-finished", "refreshed", "activity-restored", "keepalive-restored"])
        }
        await coordinatorStartGate.waitForStart()

        queue.enqueue {
            await coordinator.reconcile(hosts: [hostA, hostB])
            state.events.append(contentsOf: ["mutation-reconciled", "mutation-refreshed", "mutation-activity-restored", "mutation-keepalive-restored"])
        }
        await Task.yield()

        let createdBeforeRelease = await factory.createdHostIDs
        XCTAssertEqual(createdBeforeRelease, [hostA.id])
        XCTAssertEqual(state.events, ["start-began"])

        await coordinatorStartGate.release()
        await queue.waitForIdle()

        let createdHostIDs = await factory.createdHostIDs
        let startedHostIDs = await factory.startedHostIDs
        XCTAssertEqual(createdHostIDs, [hostA.id, hostB.id])
        XCTAssertEqual(startedHostIDs, [hostA.id, hostB.id])
        XCTAssertEqual(state.events, [
            "start-began",
            "start-finished",
            "refreshed",
            "activity-restored",
            "keepalive-restored",
            "mutation-reconciled",
            "mutation-refreshed",
            "mutation-activity-restored",
            "mutation-keepalive-restored"
        ])
    }

    func testIOSActivityOwnershipDelayedEndCannotClearReplacement() async {
        let ownership = PingScopeIOSActivityOwnership()
        let endGate = IOSLifecycleGate()
        let firstLease = await ownership.claim()

        let delayedEnd = Task {
            await endGate.block()
            return await ownership.clear(ifCurrent: firstLease)
        }
        await endGate.waitUntilBlocked()

        let replacementLease = await ownership.claim()
        await endGate.release()

        let staleEndClearedOwner = await delayedEnd.value
        let replacementIsCurrent = await ownership.isCurrent(replacementLease)

        XCTAssertFalse(staleEndClearedOwner)
        XCTAssertTrue(replacementIsCurrent)
    }

    @MainActor
    func testIOSLiveActivityStartupEndsOrphansBeforeRequestingSingleReplacement() async {
        let orphanedDirectory = RecordingIOSLiveActivityDirectory(currentActivities: ["old"])

        let replacement = await PingScopeIOSLiveActivityStartup.requestReplacingOrphans(
            in: orphanedDirectory
        ) {
            orphanedDirectory.request("new")
        }

        XCTAssertEqual(replacement, "new")
        XCTAssertEqual(orphanedDirectory.events, ["end:old", "request:new"])
        XCTAssertEqual(orphanedDirectory.ownedActivities, ["new"])
        XCTAssertEqual(orphanedDirectory.currentActivities, ["new"])

        let emptyDirectory = RecordingIOSLiveActivityDirectory(currentActivities: [])
        let normalActivity = await PingScopeIOSLiveActivityStartup.requestReplacingOrphans(
            in: emptyDirectory
        ) {
            emptyDirectory.request("new")
        }

        XCTAssertEqual(normalActivity, "new")
        XCTAssertEqual(emptyDirectory.events, ["request:new"])
        XCTAssertEqual(emptyDirectory.ownedActivities, ["new"])
        XCTAssertEqual(emptyDirectory.currentActivities, ["new"])
    }

    func testIOSLiveActivityAvailabilityRequestsWhenActiveAggregateGainsFirstPlaceholder() {
        XCTAssertEqual(
            PingScopeIOSLiveActivityAvailabilityDecision.decide(
                isSessionActive: true,
                hasPlaceholderHost: false,
                hasActivity: false
            ),
            .none
        )
        XCTAssertEqual(
            PingScopeIOSLiveActivityAvailabilityDecision.decide(
                isSessionActive: true,
                hasPlaceholderHost: true,
                hasActivity: false
            ),
            .request
        )
    }

    func testIOSLiveActivityAvailabilityUpdatesExistingActivityWithoutPlaceholder() {
        XCTAssertEqual(
            PingScopeIOSLiveActivityAvailabilityDecision.decide(
                isSessionActive: true,
                hasPlaceholderHost: false,
                hasActivity: true
            ),
            .update
        )
    }

    @MainActor
    func testIOSLifecycleHarnessStaleFiniteCompletionCannotTearDownReplacementSession() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let clock = ManualClock(baseDate: Date(timeIntervalSince1970: 70_000))
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: factory,
            now: { clock.currentDate }
        )
        let harness = PingScopeIOSLifecycleHarness()
        let queueGate = IOSLifecycleGate()
        let state = IOSLifecycleHarnessTestState()

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .oneMinute)
        let firstSessionValue = await coordinator.session()
        let firstSession = try! XCTUnwrap(firstSessionValue)
        let firstIdentity = PingScopeIOSLifecycleSessionIdentity(
            scope: .allHosts,
            focusedHostID: nil,
            startedAt: firstSession.startedAt
        )
        clock.advance(by: .seconds(61))
        harness.recordRefresh(sessionIdentity: firstIdentity, coordinatorState: .ended)
        let firstActivityLease = await harness.claimActivity()

        harness.enqueue {
            await queueGate.block()
        }
        await queueGate.waitUntilBlocked()

        harness.enqueue {
            await coordinator.start(duration: .continuous)
            let replacementSessionValue = await coordinator.session()
            let replacementSession = try! XCTUnwrap(replacementSessionValue)
            let replacementIdentity = PingScopeIOSLifecycleSessionIdentity(
                scope: .allHosts,
                focusedHostID: nil,
                startedAt: replacementSession.startedAt
            )
            harness.recordRefresh(sessionIdentity: replacementIdentity, coordinatorState: .active)
            state.replacementIdentity = replacementIdentity
            state.replacementActivityLease = await harness.claimActivity()
        }
        harness.enqueueFiniteCompletion(for: firstIdentity) {
            state.staleFiniteCleanupCount += 1
            await coordinator.stop(reason: .completed)
            _ = await harness.clearActivity(ifCurrent: firstActivityLease)
        }

        await queueGate.release()
        await harness.waitForIdle()

        let replacementSessionValue = await coordinator.session()
        let replacementSession = try! XCTUnwrap(replacementSessionValue)
        let replacementLease = try! XCTUnwrap(state.replacementActivityLease)
        let replacementLeaseIsCurrent = await harness.isActivityCurrent(replacementLease)
        XCTAssertEqual(state.staleFiniteCleanupCount, 0)
        XCTAssertEqual(harness.currentSessionIdentity, state.replacementIdentity)
        XCTAssertEqual(replacementSession.duration, .continuous)
        XCTAssertTrue(replacementSession.isActive(at: clock.currentDate))
        XCTAssertTrue(replacementLeaseIsCurrent)
    }

    @MainActor
    func testIOSLifecycleHarnessPromptlyProtectsBackgroundAndRejectsStaleExpirationEpoch() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let promptClient = RecordingIOSPromptBackgroundProtectionClient()
        let harness = PingScopeIOSLifecycleHarness(promptBackgroundProtectionClient: promptClient)
        let queueGate = IOSLifecycleGate()
        let state = IOSLifecycleHarnessTestState()

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        let sessionValue = await coordinator.session()
        let session = try! XCTUnwrap(sessionValue)
        let identity = PingScopeIOSLifecycleSessionIdentity(
            scope: .allHosts,
            focusedHostID: nil,
            startedAt: session.startedAt
        )
        harness.recordRefresh(sessionIdentity: identity, coordinatorState: .active)
        _ = harness.transitionScene(to: .active)

        harness.enqueue {
            await queueGate.block()
        }
        await queueGate.waitUntilBlocked()

        let backgroundEpoch = harness.transitionScene(to: .background)
        harness.enqueueBackgroundWork(originatingAt: backgroundEpoch) {
            state.backgroundWorkCount += 1
        }
        XCTAssertEqual(promptClient.beginCount, 1)
        XCTAssertTrue(promptClient.isActive)
        XCTAssertEqual(state.activeWorkCount, 0)

        _ = harness.transitionScene(to: .active)
        harness.enqueue {
            state.activeWorkCount += 1
        }
        let staleExpiration = harness.enqueueBackgroundExpiration(originatingAt: backgroundEpoch) {
            state.staleExpirationCount += 1
            await coordinator.stop(reason: .backgroundRuntimeExpired)
        }

        XCTAssertFalse(promptClient.isActive)
        XCTAssertEqual(promptClient.endCount, 1)

        await queueGate.release()
        await staleExpiration.value
        await harness.waitForIdle()

        let survivingSessionValue = await coordinator.session()
        let survivingSession = try! XCTUnwrap(survivingSessionValue)
        XCTAssertEqual(state.backgroundWorkCount, 0)
        XCTAssertEqual(state.activeWorkCount, 1)
        XCTAssertEqual(state.staleExpirationCount, 0)
        XCTAssertFalse(promptClient.isActive)
        XCTAssertEqual(survivingSession.duration, .continuous)
        XCTAssertNil(survivingSession.endReason)
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

    func testControllerPublishesMeasuredResultWithTheLiveHealthTransition() async throws {
        let host = HostConfig(
            id: UUID(),
            displayName: "Cloudflare",
            address: "1.1.1.1",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let measured = PingResult.failure(hostID: host.id, reason: .timeout)
        let probe = RecordingProbe(results: [measured])
        let observation = IOSMeasurementObservationBox()
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(probeInterval: .milliseconds(10)),
            clock: clock,
            now: { clock.currentDate },
            measurementObserver: { result, previousStatus, currentStatus in
                await observation.record(result, previousStatus: previousStatus, currentStatus: currentStatus)
            }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)

        let recorded = await observation.value()
        XCTAssertEqual(recorded?.result.id, measured.id)
        XCTAssertEqual(recorded?.previousStatus, HealthStatus.noData)
        XCTAssertEqual(recorded?.currentStatus, HealthStatus.down)
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
        XCTAssertNil(samples[0].location)
    }

    func testLiveHistoryWriteBufferSkipsDuplicateAndContinuesWithFreshRow() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-live-buffer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SQLiteHistoryStore(url: directory.appendingPathComponent("History.sqlite"))
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let base = Date(timeIntervalSince1970: 75_000)
        let original = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: base
        ).withHostMetadata(from: host)
        let duplicate = PingResult(
            id: original.id,
            hostID: host.id,
            timestamp: base.addingTimeInterval(1),
            latency: .milliseconds(20),
            failureReason: nil
        )
        let fresh = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(30),
            timestamp: base.addingTimeInterval(2)
        )
        try await store.appendAndWait([original])
        let probe = RecordingProbe(results: [duplicate, fresh])
        let clock = ManualClock(baseDate: base)
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(probeInterval: .milliseconds(50)),
            historyStore: store,
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .continuous, at: base)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(50))
        try await probe.waitForMeasurements(atLeast: 2)
        await controller.stop()
        await controller.stop()

        let stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)
        let diagnostics = await controller.historyWriterDiagnosticsForTesting()
        XCTAssertEqual(Set(stored.map(\.id)), Set([original.id, fresh.id]))
        XCTAssertEqual(stored.first(where: { $0.id == original.id })?.latency?.milliseconds, 10)
        XCTAssertEqual(diagnostics?.pendingCount, 0)
        XCTAssertEqual(diagnostics?.consecutiveFailureCount, 0)
    }

    func testControllerEnrichesOnlyPersistedSample() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let history = RecordingLiveMonitorHistoryStore()
        let clock = ManualClock()
        let location = try XCTUnwrap(SampleLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            horizontalAccuracy: 12,
            networkName: "Wi-Fi",
            networkInterface: "wifi"
        ))
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(50)),
            historyStore: history,
            clock: clock,
            now: { clock.currentDate },
            historySampleEnricher: { result in
                var copy = result
                copy.location = location
                return copy
            }
        )

        await controller.start(duration: .thirtySeconds, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        let snapshot = await controller.snapshot()
        await controller.stop()

        let samples = await history.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(samples.first?.location, location)
        XCTAssertNil(snapshot.health.latestResult?.location)
        XCTAssertNil(snapshot.series.samples.first?.location)
        XCTAssertNil(snapshot.session?.latestResult?.location)
    }

    func testHistoryLocationProviderEnrichesEnabledAuthorizedSampleWithFixAndInterface() throws {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        let fix = try XCTUnwrap(SampleLocation(latitude: 37.7749, longitude: -122.4194, horizontalAccuracy: 12))
        store.update(
            PingScopeIOSHistoryLocationSnapshot(
                isTaggingEnabled: true,
                isAuthorized: true,
                fix: fix,
                networkInterface: "wifi",
                networkName: "Office Wi-Fi",
                isVPN: true
            )
        )
        let result = PingResult.success(hostID: UUID(), latency: .milliseconds(18))

        let enriched = store.makeHistorySampleEnricher()(result)

        XCTAssertEqual(enriched.location?.latitude, fix.latitude)
        XCTAssertEqual(enriched.location?.longitude, fix.longitude)
        XCTAssertEqual(enriched.location?.horizontalAccuracy, 12)
        XCTAssertEqual(enriched.location?.networkName, "Office Wi-Fi")
        XCTAssertEqual(enriched.location?.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Office Wi-Fi")
        XCTAssertTrue(enriched.isVPN)
    }

    func testHistoryLocationProviderCapturesNetworkWhenTaggingDisabled() throws {
        let original = PingResult.success(hostID: UUID(), latency: .milliseconds(18))
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.update(PingScopeIOSHistoryLocationSnapshot(
            isTaggingEnabled: false,
            isAuthorized: true,
            fix: try XCTUnwrap(SampleLocation(latitude: 1, longitude: 2)),
            networkInterface: "wifi",
            networkName: nil,
            isVPN: true
        ))

        let enriched = store.makeHistorySampleEnricher()(original)

        XCTAssertNil(enriched.location)
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Wi-Fi")
        XCTAssertTrue(enriched.isVPN)
        XCTAssertNil(original.networkInterface)
    }

    func testHistoryLocationProviderCapturesNetworkWhenLocationUnauthorized() throws {
        let original = PingResult.success(hostID: UUID(), latency: .milliseconds(18))
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.update(PingScopeIOSHistoryLocationSnapshot(
            isTaggingEnabled: true,
            isAuthorized: false,
            fix: try XCTUnwrap(SampleLocation(latitude: 1, longitude: 2)),
            networkInterface: "cellular",
            networkName: "Cellular · LTE"
        ))

        let enriched = store.makeHistorySampleEnricher()(original)

        XCTAssertNil(enriched.location)
        XCTAssertEqual(enriched.networkInterface, "cellular")
        XCTAssertEqual(enriched.networkName, "Cellular · LTE")
        XCTAssertFalse(enriched.isVPN)
    }

    func testHistoryLocationProviderCapturesNetworkWithoutLocationFix() {
        let original = PingResult.success(hostID: UUID(), latency: .milliseconds(18))
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.update(PingScopeIOSHistoryLocationSnapshot(
            isTaggingEnabled: true,
            isAuthorized: true,
            fix: nil,
            networkInterface: "wifi"
        ))

        let enriched = store.makeHistorySampleEnricher()(original)

        XCTAssertNil(enriched.location)
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Wi-Fi")
    }

    func testHistoryLocationProviderEnrichesWithoutNetworkInterface() throws {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        let fix = try XCTUnwrap(SampleLocation(latitude: 51.5074, longitude: -0.1278, horizontalAccuracy: 9))
        store.update(PingScopeIOSHistoryLocationSnapshot(
            isTaggingEnabled: true,
            isAuthorized: true,
            fix: fix,
            networkInterface: nil
        ))

        let enriched = store.makeHistorySampleEnricher()(.success(hostID: UUID(), latency: .milliseconds(12)))

        XCTAssertEqual(enriched.location?.latitude, fix.latitude)
        XCTAssertEqual(enriched.location?.longitude, fix.longitude)
        XCTAssertNil(enriched.location?.networkName)
        XCTAssertNil(enriched.location?.networkInterface)
        XCTAssertNil(enriched.networkName)
        XCTAssertNil(enriched.networkInterface)
    }

    func testHistoryLocationSnapshotStoreUpdatesNetworkAtomically() {
        let store = PingScopeIOSHistoryLocationSnapshotStore()

        store.updateNetwork(interface: "wifi", name: "Office Wi-Fi", isVPN: true)

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.networkInterface, "wifi")
        XCTAssertEqual(snapshot.networkName, "Office Wi-Fi")
        XCTAssertTrue(snapshot.isVPN)
    }

    func testHistoryLocationSnapshotStoreIgnoresLateWiFiNameAfterInterfaceChanges() {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.updateNetwork(interface: "wifi", name: "Wi-Fi", isVPN: true)
        store.updateNetwork(interface: "cellular", name: "Cellular · LTE", isVPN: false)

        store.updateNetworkName("Late SSID", ifInterfaceMatches: "wifi")

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.networkInterface, "cellular")
        XCTAssertEqual(snapshot.networkName, "Cellular · LTE")
        XCTAssertFalse(snapshot.isVPN)
    }

    func testWiFiNameReadRequiresEntitlementLocationAuthorizationAndWiFiInterface() {
        XCTAssertTrue(PingScopeIOSWiFiNameReadPolicy.isAllowed(
            hasWiFiInfoEntitlement: true,
            authorization: .whenInUse,
            networkInterface: "wifi"
        ))
        XCTAssertTrue(PingScopeIOSWiFiNameReadPolicy.isAllowed(
            hasWiFiInfoEntitlement: true,
            authorization: .always,
            networkInterface: "Wi-Fi"
        ))
        XCTAssertFalse(PingScopeIOSWiFiNameReadPolicy.isAllowed(
            hasWiFiInfoEntitlement: false,
            authorization: .always,
            networkInterface: "wifi"
        ))
        XCTAssertFalse(PingScopeIOSWiFiNameReadPolicy.isAllowed(
            hasWiFiInfoEntitlement: true,
            authorization: .denied,
            networkInterface: "wifi"
        ))
        XCTAssertFalse(PingScopeIOSWiFiNameReadPolicy.isAllowed(
            hasWiFiInfoEntitlement: true,
            authorization: .whenInUse,
            networkInterface: "cellular"
        ))
    }

    func testRevokedWiFiNameAuthorizationClearsCachedSSIDAndFallsBackToInterfaceLabel() {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.updateNetwork(interface: "wifi", name: "Private SSID", isVPN: false)

        store.clearNetworkName(ifInterfaceMatches: "wifi")

        let enriched = store.makeHistorySampleEnricher()(
            .success(hostID: UUID(), latency: .milliseconds(12))
        )
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Wi-Fi")
    }

    func testLateFetchedWiFiNameIsDroppedAfterAuthorizationRevocation() {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.updateNetwork(interface: "wifi", name: "Private SSID", isVPN: false)
        store.clearNetworkName(ifInterfaceMatches: "wifi")

        store.updateFetchedWiFiName(
            "Late Private SSID",
            hasWiFiInfoEntitlement: true,
            authorization: .denied
        )

        let enriched = store.makeHistorySampleEnricher()(
            .success(hostID: UUID(), latency: .milliseconds(12))
        )
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Wi-Fi")
    }

    func testFetchedWiFiNameIsWrittenWhileConsentRemainsAuthorized() {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        store.updateNetwork(interface: "wifi", name: "Wi-Fi", isVPN: false)

        store.updateFetchedWiFiName(
            "Authorized SSID",
            hasWiFiInfoEntitlement: true,
            authorization: .whenInUse
        )

        let enriched = store.makeHistorySampleEnricher()(
            .success(hostID: UUID(), latency: .milliseconds(12))
        )
        XCTAssertEqual(enriched.networkInterface, "wifi")
        XCTAssertEqual(enriched.networkName, "Authorized SSID")
    }

    func testLatestValidHistoryLocationFixUsesNewestValidCandidate() throws {
        let previous = try XCTUnwrap(SampleLocation(latitude: 1, longitude: 2))
        let candidates = [
            PingScopeIOSHistoryLocationFixCandidate(latitude: 10, longitude: 20, horizontalAccuracy: 5),
            PingScopeIOSHistoryLocationFixCandidate(latitude: 200, longitude: 20, horizontalAccuracy: 6),
        ]

        let selected = PingScopeIOSHistoryLocationFixReducer.latestValidFix(
            from: candidates,
            preserving: previous
        )

        XCTAssertEqual(selected, SampleLocation(latitude: 10, longitude: 20, horizontalAccuracy: 5))
    }

    func testLatestValidHistoryLocationFixPreservesPreviousWhenCallbackHasNoValidCandidate() throws {
        let previous = try XCTUnwrap(SampleLocation(latitude: 1, longitude: 2, horizontalAccuracy: 7))
        let candidates = [
            PingScopeIOSHistoryLocationFixCandidate(latitude: .nan, longitude: 20, horizontalAccuracy: 5),
            PingScopeIOSHistoryLocationFixCandidate(latitude: 30, longitude: 400, horizontalAccuracy: 6),
        ]

        XCTAssertEqual(
            PingScopeIOSHistoryLocationFixReducer.latestValidFix(from: candidates, preserving: previous),
            previous
        )
    }

    func testHistoryLocationProviderReadsCoherentSnapshotsDuringConcurrentUpdates() async throws {
        let store = PingScopeIOSHistoryLocationSnapshotStore()
        let first = try XCTUnwrap(SampleLocation(latitude: 10, longitude: 20))
        let second = try XCTUnwrap(SampleLocation(latitude: -30, longitude: -40))
        let result = PingResult.success(hostID: UUID(), latency: .milliseconds(18))
        let enricher = store.makeHistorySampleEnricher()

        let locations = await withTaskGroup(of: [SampleLocation].self, returning: [SampleLocation].self) { group in
            group.addTask {
                for index in 0..<2_000 {
                    store.update(PingScopeIOSHistoryLocationSnapshot(
                        isTaggingEnabled: true,
                        isAuthorized: true,
                        fix: index.isMultiple(of: 2) ? first : second,
                        networkInterface: index.isMultiple(of: 2) ? "wifi" : "cellular"
                    ))
                }
                return []
            }
            for _ in 0..<4 {
                group.addTask {
                    (0..<2_000).compactMap { _ in enricher(result).location }
                }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }

        XCTAssertFalse(locations.isEmpty)
        XCTAssertTrue(locations.allSatisfy { location in
            (location.latitude == 10 && location.longitude == 20 && location.networkInterface == "wifi")
                || (location.latitude == -30 && location.longitude == -40 && location.networkInterface == "cellular")
        })
    }

    func testHistoryLocationPolicyKeepsIndependentModesAndPrefersTaggingAccuracy() {
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: false,
                monitoringActive: true,
                authorization: .whenInUse
            ),
            .inactive
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: false,
                monitoringActive: true,
                authorization: .always
            ),
            .init(updatesActive: true, backgroundActive: true, accuracy: .keepAlive)
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: false,
                taggingEnabled: true,
                monitoringActive: true,
                authorization: .whenInUse
            ),
            .init(updatesActive: true, backgroundActive: false, accuracy: .tagging)
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: true,
                monitoringActive: true,
                authorization: .always
            ),
            .init(updatesActive: true, backgroundActive: true, accuracy: .tagging)
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: true,
                monitoringActive: false,
                authorization: .always
            ),
            .inactive
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: true,
                monitoringActive: true,
                authorization: .denied
            ),
            .inactive
        )
        XCTAssertEqual(
            PingScopeIOSHistoryLocationPolicy.reduce(
                keepAliveEnabled: true,
                taggingEnabled: false,
                monitoringActive: true,
                authorization: .undetermined
            ),
            .inactive
        )
    }

    func testHistoryLocationStateMachineTaggingRequestNeverRequestsAlways() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .undetermined)

        XCTAssertEqual(machine.handle(.requestTaggingAuthorization), [.requestWhenInUseAuthorization])
        XCTAssertEqual(machine.handle(.authorizationChanged(.whenInUse)), [])
        XCTAssertEqual(machine.handle(.authorizationChanged(.always)), [])
    }

    func testHistoryLocationStateMachineTaggingRequestDoesNotRepeatAfterDenialOrRestriction() {
        var denied = PingScopeIOSHistoryLocationStateMachine(authorization: .denied)
        var restricted = PingScopeIOSHistoryLocationStateMachine(authorization: .restricted)

        XCTAssertEqual(denied.handle(.requestTaggingAuthorization), [])
        XCTAssertEqual(restricted.handle(.requestTaggingAuthorization), [])
    }

    func testHistoryLocationStateMachineTaggingRequestPreservesPendingKeepAliveEscalation() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .undetermined)

        XCTAssertEqual(machine.handle(.requestKeepAliveAuthorization), [.requestWhenInUseAuthorization])
        XCTAssertEqual(machine.handle(.requestTaggingAuthorization), [.requestWhenInUseAuthorization])
        XCTAssertEqual(machine.handle(.authorizationChanged(.whenInUse)), [.requestAlwaysAuthorization])
    }

    func testHistoryLocationStateMachineExplicitKeepAliveRequestEscalatesToAlways() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .undetermined)

        XCTAssertEqual(machine.handle(.requestKeepAliveAuthorization), [.requestWhenInUseAuthorization])
        XCTAssertEqual(machine.handle(.authorizationChanged(.whenInUse)), [.requestAlwaysAuthorization])
    }

    func testHistoryLocationStateMachineDisablingKeepAliveCancelsPendingEscalation() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .undetermined)
        _ = machine.handle(.setState(keepAliveEnabled: true, taggingEnabled: false, monitoringActive: false))
        _ = machine.handle(.requestKeepAliveAuthorization)

        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: false, taggingEnabled: false, monitoringActive: false)),
            []
        )
        XCTAssertEqual(machine.handle(.authorizationChanged(.whenInUse)), [])
    }

    func testHistoryLocationStateMachineDisablingOneModeKeepsOtherActive() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .always)

        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: true, taggingEnabled: true, monitoringActive: true)),
            [.configureAccuracy(.tagging), .setBackgroundUpdates(true), .startUpdatingLocation]
        )
        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: false, taggingEnabled: true, monitoringActive: true)),
            [.setBackgroundUpdates(false)]
        )
        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: true, taggingEnabled: false, monitoringActive: true)),
            [.configureAccuracy(.keepAlive), .setBackgroundUpdates(true)]
        )
    }

    func testHistoryLocationStateMachineEmitsDeterministicManagerTransitionCommands() {
        var machine = PingScopeIOSHistoryLocationStateMachine(authorization: .always)

        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: true, taggingEnabled: false, monitoringActive: true)),
            [.configureAccuracy(.keepAlive), .setBackgroundUpdates(true), .startUpdatingLocation]
        )
        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: true, taggingEnabled: false, monitoringActive: true)),
            []
        )
        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: false, taggingEnabled: false, monitoringActive: false)),
            [.setBackgroundUpdates(false), .stopUpdatingLocation]
        )
        XCTAssertEqual(
            machine.handle(.setState(keepAliveEnabled: false, taggingEnabled: false, monitoringActive: false)),
            []
        )
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

    func testControllerRestartWhileDownResetsHealthAndNextSleepDuration() async throws {
        let host = HostConfig(
            id: UUID(),
            displayName: "Cloudflare",
            address: "1.1.1.1",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let failure = PingResult.failure(hostID: host.id, reason: .timeout)
        let probe = RecordingProbe(results: [failure])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(probeInterval: .milliseconds(100)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .continuous, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(100))
        try await clock.waitForSleepers(atLeast: 1)

        let downSnapshot = await controller.snapshot()
        let downMeasurementCount = await probe.measurementCount
        XCTAssertEqual(downSnapshot.health.status, .down)
        XCTAssertEqual(downMeasurementCount, 2)

        await controller.start(duration: .continuous, at: clock.currentDate)
        try await clock.waitForSleepers(atLeast: 1)

        let restartedSnapshot = await controller.snapshot()
        let restartedMeasurementCount = await probe.measurementCount
        XCTAssertEqual(restartedSnapshot.health.status, .down)
        XCTAssertEqual(restartedMeasurementCount, 3)
        XCTAssertEqual(clock.durationUntilNextSleepDeadline, .milliseconds(100))

        clock.advance(by: .milliseconds(99))
        XCTAssertEqual(clock.durationUntilNextSleepDeadline, .milliseconds(1))
        let measurementCountBeforeBaseInterval = await probe.measurementCount
        XCTAssertEqual(measurementCountBeforeBaseInterval, 3)

        clock.advance(by: .milliseconds(1))
        try await clock.waitForSleepers(atLeast: 1)
        let measurementCountAtBaseInterval = await probe.measurementCount
        XCTAssertEqual(measurementCountAtBaseInterval, 4)
        await controller.stop()
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
        let sharedData = defaults.data(forKey: SharedHostStoreKeys.current)
        XCTAssertNotNil(sharedData)
        let sharedState = sharedData.flatMap { try? SharedHostStoreCodec.decode($0) }
        XCTAssertEqual(sharedState, SharedHostStoreState(hosts: hosts, selectedHostID: hosts[1].id))
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

    func testIOSHostStoreDeduplicatesHostIDsWithoutRewritingStoredBlob() throws {
        let suiteName = "PingScopeIOSHostStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let duplicateID = UUID()
        let first = HostConfig(id: duplicateID, displayName: "First", address: "1.1.1.1")
        let second = HostConfig(id: duplicateID, displayName: "Second", address: "8.8.8.8")
        let encoded = try JSONEncoder().encode([first, second])
        defaults.set(encoded, forKey: "PingScope.iOS.hosts")
        defaults.set(duplicateID.uuidString, forKey: "PingScope.iOS.selectedHostID")
        let store = PingScopeIOSHostStore(defaults: defaults, defaultHosts: [first])

        let state = store.load()

        XCTAssertEqual(state.hosts, [first])
        XCTAssertEqual(state.selectedHost, first)
        XCTAssertEqual(defaults.data(forKey: "PingScope.iOS.hosts"), encoded)
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

    func testIOSHostDraftPreservesDisabledStateWhenFinalized() {
        var draft = PingScopeIOSHostDraft(host: HostConfig(displayName: "Paused host", address: "1.1.1.1"))

        draft.isEnabled = false

        XCTAssertFalse(draft.finalizedHost.isEnabled)
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

    func testBackgroundRuntimeIgnoresDelayedExpirationFromPreviousStint() async {
        let client = RecordingBackgroundTaskClient()
        let runtime = LiveMonitorBackgroundRuntime(client: client)
        let oldCleanup = ExpirationCleanupRecorder()
        let currentCleanup = ExpirationCleanupRecorder()

        await runtime.begin { await oldCleanup.record() }
        await runtime.begin { await currentCleanup.record() }
        await client.expire(at: 0)
        try? await Task.sleep(for: .milliseconds(20))

        let oldCleanupCount = await oldCleanup.countSnapshot()
        let currentCleanupCount = await currentCleanup.countSnapshot()
        let endedBeforeCurrentStop = await client.endedIDsSnapshot()
        XCTAssertEqual(oldCleanupCount, 0)
        XCTAssertEqual(currentCleanupCount, 0)
        XCTAssertEqual(endedBeforeCurrentStop, [LiveMonitorBackgroundTaskID(rawValue: 1)])

        await runtime.end()
        let endedAfterCurrentStop = await client.endedIDsSnapshot()
        XCTAssertEqual(
            endedAfterCurrentStop,
            [LiveMonitorBackgroundTaskID(rawValue: 1), LiveMonitorBackgroundTaskID(rawValue: 2)]
        )
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
        XCTAssertEqual(createdHostIDs, [enabledA.id, enabledC.id])
        XCTAssertEqual(startedHostIDs, [enabledA.id, enabledC.id])
        XCTAssertEqual(startedDurations, [.oneMinute, .oneMinute])
        XCTAssertEqual(snapshots[enabledA.id]?.host.id, enabledA.id)
        XCTAssertEqual(snapshots[enabledC.id]?.host.id, enabledC.id)
        XCTAssertNil(snapshots[disabledB.id])

        let session = await coordinator.session()
        XCTAssertEqual(session?.duration, .oneMinute)
        XCTAssertEqual(session?.startedAt, startedAt)
        XCTAssertEqual(session?.remainingDuration(at: startedAt), .seconds(60))
    }

    func testIOSAllHostsScopeRoundTripPreservesEveryHostsGraphSeries() async {
        let hosts = [
            HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8"),
            HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        ]
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let baseDate = Date(timeIntervalSince1970: 30_000)

        await coordinator.reconcile(hosts: hosts)
        await coordinator.start(duration: .continuous)
        for (index, host) in hosts.enumerated() {
            await factory.setSnapshotSamples([
                .success(
                    hostID: host.id,
                    latency: .milliseconds(Double(10 + index)),
                    timestamp: baseDate.addingTimeInterval(Double(index))
                )
            ], for: host.id)
        }

        await coordinator.suspendForScopeChange()
        await coordinator.reconcile(hosts: hosts)
        await coordinator.start(duration: .continuous)

        let restored = await coordinator.orderedSnapshots()
        XCTAssertEqual(restored.map(\.host.id), hosts.map(\.id))
        XCTAssertEqual(restored.map { $0.series.samples.count }, [1, 1, 1])
        XCTAssertEqual(
            restored.compactMap { $0.series.samples.first?.latency?.milliseconds },
            [10, 11, 12]
        )
        let stopReasons = await factory.stopReasons
        XCTAssertEqual(stopReasons, [.scopeSuspended, .scopeSuspended, .scopeSuspended])
    }

    func testEndedFocusedReturnClearsSuspendedAllHostsSeriesBeforeNextStart() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let deadSessionSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(44),
            timestamp: Date(timeIntervalSince1970: 32_000)
        )

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([deadSessionSample], for: host.id)
        await coordinator.suspendForScopeChange()

        // The focused session has already ended, but its refresh-loop completion
        // lost the lifecycle race. Returning to All Hosts must clear the suspended
        // coordinator before the user's next explicit Start.
        await PingScopeIOSAppMonitoringOrchestration.prepareAllHostsReturn(
            restartDuration: nil,
            coordinator: coordinator
        )
        await coordinator.reconcile(hosts: [host])
        await factory.setSnapshotSamples([], for: host.id)
        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertEqual(restarted.first?.series.samples, [])
    }

    func testExplicitStopAfterFocusedScopeSuspensionDoesNotResurrectDeadSessionSeries() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(12),
            timestamp: Date(timeIntervalSince1970: 30_000)
        )

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([sample], for: host.id)
        await coordinator.suspendForScopeChange()

        // This is the all-host half of PingScopeIOSModel.stopMonitoring while
        // the focused controller is visible.
        await coordinator.stop(reason: .userStopped)
        await factory.setSnapshotSamples([], for: host.id)
        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertEqual(restarted.first?.series.samples, [])
    }

    @MainActor
    func testAppModelFocusedFiniteCompletionClearsSuspendedAllHostsSeries() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let deadSessionSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(12),
            timestamp: Date(timeIntervalSince1970: 30_000)
        )

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([deadSessionSample], for: host.id)
        await coordinator.suspendForScopeChange()

        var focusedControllerWasStopped = false
        await PingScopeIOSAppMonitoringOrchestration.stopMonitoring(
            scope: .focused,
            reason: .completed,
            coordinator: coordinator
        ) {
            focusedControllerWasStopped = true
        }
        await factory.setSnapshotSamples([], for: host.id)
        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertTrue(focusedControllerWasStopped)
        XCTAssertEqual(restarted.first?.series.samples, [])
    }

    @MainActor
    func testAppModelFocusedExplicitStartClearsSuspendedAllHostsSeries() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        let deadSessionSample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(18),
            timestamp: Date(timeIntervalSince1970: 31_000)
        )

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([deadSessionSample], for: host.id)
        await coordinator.suspendForScopeChange()

        var focusedControllerWasStarted = false
        await PingScopeIOSAppMonitoringOrchestration.startMonitoring(
            scope: .focused,
            duration: .continuous,
            hosts: [host],
            coordinator: coordinator
        ) {
            focusedControllerWasStarted = true
        }
        await factory.setSnapshotSamples([], for: host.id)
        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertTrue(focusedControllerWasStarted)
        XCTAssertEqual(restarted.first?.series.samples, [])
    }

    func testRemovingHostWhileScopeSuspendedDropsItsPreservedSeries() async {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Gateway", address: "192.168.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        await coordinator.reconcile(hosts: [hostA, hostB])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([
            .success(hostID: hostA.id, latency: .milliseconds(10))
        ], for: hostA.id)
        await factory.setSnapshotSamples([
            .success(hostID: hostB.id, latency: .milliseconds(20))
        ], for: hostB.id)

        await coordinator.suspendForScopeChange()
        await coordinator.reconcile(hosts: [hostA])
        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertEqual(restarted.map(\.host.id), [hostA.id])
        XCTAssertEqual(restarted.first?.series.samples.count, 1)
    }

    func testStartWithoutScopeSuspensionDoesNotMergeSamplesFromPriorStoppedSession() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)
        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await factory.setSnapshotSamples([
            .success(hostID: host.id, latency: .milliseconds(10))
        ], for: host.id)
        await coordinator.stop(reason: .userStopped)
        await factory.setSnapshotSamples([], for: host.id)

        await coordinator.start(duration: .continuous)

        let restarted = await coordinator.orderedSnapshots()
        XCTAssertEqual(restarted.first?.series.samples, [])
    }

    func testIOSAllHostsCoordinatorStartsIndependentControllersConcurrentlyAndKeepsSnapshotOrder() async throws {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        let startGate = IOSAllHostsStartGate()
        let factory = RecordingIOSAllHostsControllerFactory(startGate: startGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostB, hostA])
        let start = Task { await coordinator.start(duration: .continuous) }
        await startGate.waitForStart()
        try await Task.sleep(for: .milliseconds(50))

        let startCount = await factory.startCount
        XCTAssertEqual(startCount, 2)
        await startGate.release()
        await start.value
        let snapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(snapshots.map(\.host.id), [hostB.id, hostA.id])
    }

    func testIOSAllHostsCoordinatorCoalescesDuplicateHostIDsBeforeLifecycleFanOut() async {
        let duplicateID = UUID()
        let first = HostConfig(id: duplicateID, displayName: "First", address: "1.1.1.1")
        let second = HostConfig(id: duplicateID, displayName: "Second", address: "8.8.8.8")
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: factory
        )

        await coordinator.reconcile(hosts: [first, second])
        await coordinator.start(duration: .continuous)
        let snapshots = await coordinator.snapshotsByHostID()
        let createdHostIDs = await factory.createdHostIDs
        let startedHostIDs = await factory.startedHostIDs

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[duplicateID]?.host, first)
        XCTAssertEqual(createdHostIDs, [duplicateID])
        XCTAssertEqual(startedHostIDs, [duplicateID])
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
        let snapshotOrderGate = IOSAllHostsSnapshotOrderGate(blockedHostID: hostC.id)
        let factory = RecordingIOSAllHostsControllerFactory(snapshotOrderGate: snapshotOrderGate)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [hostC, disabledB, hostA])

        let snapshotCollection = Task {
            await coordinator.orderedSnapshots()
        }
        await snapshotOrderGate.waitForBlockedSnapshot()
        await snapshotOrderGate.waitForCompletion(of: hostA.id)
        let completedBeforeRelease = await snapshotOrderGate.completedHostIDs
        XCTAssertEqual(completedBeforeRelease, [hostA.id])
        await snapshotOrderGate.releaseBlockedSnapshot()

        let orderedSnapshots = await snapshotCollection.value
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

    func testIOSAllHostsCoordinatorCosmeticHostEditPreservesRunningControllerAndUpdatesSnapshot() async {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        var renamedHost = host
        renamedHost.displayName = "Primary DNS"
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await coordinator.reconcile(hosts: [renamedHost])

        let createdControllerTokens = await factory.createdControllerTokens
        let stoppedControllerTokens = await factory.stoppedControllerTokens
        let isRunning = await factory.isRunning(controllerToken: 1)
        let orderedSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(createdControllerTokens, [1])
        XCTAssertTrue(stoppedControllerTokens.isEmpty)
        XCTAssertTrue(isRunning)
        XCTAssertEqual(orderedSnapshots.first?.host.displayName, renamedHost.displayName)
    }

    func testIOSAllHostsCoordinatorCosmeticEditPreservesNormalizedProbeMetadata() async {
        let host = HostConfig(
            id: UUID(),
            displayName: "Legacy ICMP",
            address: "1.1.1.1",
            method: .icmp,
            port: nil
        )
        var normalizedHost = host
        normalizedHost.apply(method: .tcp)
        var renamedHost = host
        renamedHost.displayName = "Primary DNS"
        let factory = RecordingIOSAllHostsControllerFactory(snapshotHosts: [host.id: normalizedHost])
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(controllerFactory: factory)

        await coordinator.reconcile(hosts: [host])
        await coordinator.start(duration: .continuous)
        await coordinator.reconcile(hosts: [renamedHost])

        let createdControllerTokens = await factory.createdControllerTokens
        let stoppedControllerTokens = await factory.stoppedControllerTokens
        let orderedSnapshots = await coordinator.orderedSnapshots()
        XCTAssertEqual(createdControllerTokens, [1])
        XCTAssertTrue(stoppedControllerTokens.isEmpty)
        XCTAssertEqual(orderedSnapshots.first?.host.displayName, renamedHost.displayName)
        XCTAssertEqual(orderedSnapshots.first?.host.method, .tcp)
        XCTAssertEqual(orderedSnapshots.first?.host.port, PingMethod.tcp.defaultPort)
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

    func testIOSAllHostsCoordinatorFansOutSameHistoryEnricherToInitialAndReplacementControllers() async throws {
        let hostA = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let hostB = HostConfig(id: UUID(), displayName: "Google", address: "8.8.8.8")
        var replacementA = hostA
        replacementA.address = "1.0.0.1"
        let location = try XCTUnwrap(SampleLocation(
            latitude: 34.0522,
            longitude: -118.2437,
            horizontalAccuracy: 8,
            networkName: "Cellular",
            networkInterface: "cellular"
        ))
        let factory = RecordingIOSAllHostsControllerFactory()
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: factory,
            historySampleEnricher: { result in
                var copy = result
                copy.location = location
                return copy
            }
        )

        await coordinator.reconcile(hosts: [hostA, hostB])
        await coordinator.reconcile(hosts: [replacementA, hostB])

        let receivedLocations = await factory.receivedEnrichedLocations
        XCTAssertEqual(receivedLocations, [location, location, location])
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
        XCTAssertEqual(Set(startRecords.map(\.hostID)), Set([hostA.id, hostB.id]))
        XCTAssertTrue(startRecords.allSatisfy { $0.duration == .oneMinute })
        XCTAssertEqual(startRecords.map(\.date), [clock.baseDate, clock.baseDate])
        XCTAssertEqual(Set(stopRecords.map(\.hostID)), Set([hostA.id, hostB.id]))
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

@MainActor
private final class IOSLifecycleTestState {
    var scope: PingScopeIOSHostScope = .focused
    var events: [String] = []
}

@MainActor
private final class IOSLiveActivityRuntimeRecorder {
    var activityID: String?
    private(set) var events: [String] = []
    private(set) var lastStaleDate: Date?

    init(activityID: String?) {
        self.activityID = activityID
    }

    func record(_ event: String) {
        events.append(event)
    }

    func recordContinuous(staleDate: Date) {
        events.append("continuous")
        lastStaleDate = staleDate
    }

    func request(_ id: String) {
        activityID = id
        events.append("requested:\(id)")
    }
}

@MainActor
private final class RecordingIOSLiveActivityDirectory: PingScopeIOSLiveActivityDirectory {
    private(set) var currentActivities: [String]
    private(set) var ownedActivities: [String] = []
    var events: [String] = []

    init(currentActivities: [String]) {
        self.currentActivities = currentActivities
    }

    func end(_ activity: String) async {
        events.append("end:\(activity)")
        currentActivities.removeAll { $0 == activity }
    }

    func request(_ activity: String) -> String {
        events.append("request:\(activity)")
        ownedActivities = [activity]
        currentActivities = [activity]
        return activity
    }
}

@MainActor
private final class IOSLifecycleHarnessTestState {
    var replacementIdentity: PingScopeIOSLifecycleSessionIdentity?
    var replacementActivityLease: PingScopeIOSActivityOwnershipLease?
    var staleFiniteCleanupCount = 0
    var backgroundWorkCount = 0
    var activeWorkCount = 0
    var staleExpirationCount = 0
}

@MainActor
private final class RecordingIOSPromptBackgroundProtectionClient: PingScopeIOSPromptBackgroundProtectionClient {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var isActive = false

    func beginPromptBackgroundProtection() {
        beginCount += 1
        isActive = true
    }

    func endPromptBackgroundProtection() {
        endCount += 1
        isActive = false
    }
}

private actor IOSLifecycleGate {
    private var isBlocked = false
    private var isReleased = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func block() async {
        isBlocked = true
        blockedWaiters.forEach { $0.resume() }
        blockedWaiters.removeAll()
        while !isReleased {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func waitUntilBlocked() async {
        while !isBlocked {
            await withCheckedContinuation { continuation in
                blockedWaiters.append(continuation)
            }
        }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
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
    private var expirationHandlers: [@Sendable () -> Void] = []

    func beginBackgroundTask(named name: String, expirationHandler: @escaping @Sendable () -> Void) async -> LiveMonitorBackgroundTaskID? {
        startedNames.append(name)
        expirationHandlers.append(expirationHandler)
        let id = LiveMonitorBackgroundTaskID(rawValue: nextID)
        nextID += 1
        return id
    }

    func endBackgroundTask(_ id: LiveMonitorBackgroundTaskID) async {
        endedIDs.append(id)
    }

    func expireMostRecent() {
        expirationHandlers.last?()
    }

    func expire(at index: Int) {
        guard expirationHandlers.indices.contains(index) else { return }
        expirationHandlers[index]()
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

private actor IOSMeasurementObservationBox {
    struct Value: Sendable {
        let result: PingResult
        let previousStatus: HealthStatus
        let currentStatus: HealthStatus
    }

    private var recorded: Value?

    func record(_ result: PingResult, previousStatus: HealthStatus, currentStatus: HealthStatus) {
        recorded = Value(result: result, previousStatus: previousStatus, currentStatus: currentStatus)
    }

    func value() -> Value? {
        recorded
    }
}

private actor RecordingIOSAllHostsControllerFactory: PingScopeIOSMultiHostSessionControllerFactory {
    private let statuses: [UUID: HealthStatus]
    private let snapshotHosts: [UUID: HostConfig]
    private let startGate: IOSAllHostsStartGate?
    private let stopGate: IOSAllHostsStopGate?
    private let firstStopGate: IOSAllHostsFirstStopGate?
    private let snapshotGate: IOSAllHostsFirstSnapshotGate?
    private let snapshotOrderGate: IOSAllHostsSnapshotOrderGate?
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
    private(set) var receivedEnrichedLocations: [SampleLocation?] = []
    private var snapshotSamples: [UUID: [PingResult]] = [:]

    init(
        statuses: [UUID: HealthStatus] = [:],
        snapshotHosts: [UUID: HostConfig] = [:],
        startGate: IOSAllHostsStartGate? = nil,
        stopGate: IOSAllHostsStopGate? = nil,
        firstStopGate: IOSAllHostsFirstStopGate? = nil,
        snapshotGate: IOSAllHostsFirstSnapshotGate? = nil,
        snapshotOrderGate: IOSAllHostsSnapshotOrderGate? = nil
    ) {
        self.statuses = statuses
        self.snapshotHosts = snapshotHosts
        self.startGate = startGate
        self.stopGate = stopGate
        self.firstStopGate = firstStopGate
        self.snapshotGate = snapshotGate
        self.snapshotOrderGate = snapshotOrderGate
    }

    func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher,
        measurementObserver: @escaping PingScopeIOSMeasurementObserver
    ) async -> any PingScopeIOSMultiHostSessionControlling {
        receivedEnrichedLocations.append(historySampleEnricher(.success(hostID: host.id, latency: .milliseconds(1))).location)
        nextControllerToken += 1
        createdHostIDs.append(host.id)
        createdControllerTokens.append(nextControllerToken)
        runningByControllerToken[nextControllerToken] = false
        return RecordingIOSAllHostsController(host: host, controllerToken: nextControllerToken, factory: self)
    }

    var stopCount: Int {
        stoppedAndFlushedHostIDs.count
    }

    var startCount: Int {
        startedHostIDs.count
    }

    func recordStart(hostID: UUID, controllerToken: Int, duration: MonitorSessionDuration, at date: Date) async {
        snapshotSamples[hostID] = []
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

    func setSnapshotSamples(_ samples: [PingResult], for hostID: UUID) {
        snapshotSamples[hostID] = samples
    }

    func snapshot(for host: HostConfig) async -> LiveMonitorSessionSnapshot {
        if await snapshotGate?.recordSnapshot() == true {
            await snapshotGate?.waitForRelease()
        }
        await snapshotOrderGate?.waitIfBlocked(hostID: host.id)

        let snapshotHost = snapshotHosts[host.id] ?? host
        var health = HostHealth(hostID: snapshotHost.id, thresholds: snapshotHost.thresholds)
        health.status = statuses[host.id] ?? .noData
        await snapshotOrderGate?.recordCompletion(hostID: host.id)
        var series = SampleSeries(hostID: snapshotHost.id)
        for sample in snapshotSamples[host.id, default: []] {
            series.append(sample)
        }
        return LiveMonitorSessionSnapshot(host: snapshotHost, session: nil, health: health, series: series)
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

private actor IOSAllHostsSnapshotOrderGate {
    private let blockedHostID: UUID
    private var blockedSnapshotStarted = false
    private var released = false
    private var completed: [UUID] = []
    private var blockedSnapshotWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init(blockedHostID: UUID) {
        self.blockedHostID = blockedHostID
    }

    var completedHostIDs: [UUID] {
        completed
    }

    func waitIfBlocked(hostID: UUID) async {
        guard hostID == blockedHostID else { return }
        blockedSnapshotStarted = true
        blockedSnapshotWaiters.forEach { $0.resume() }
        blockedSnapshotWaiters.removeAll()
        while !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func waitForBlockedSnapshot() async {
        while !blockedSnapshotStarted {
            await withCheckedContinuation { continuation in
                blockedSnapshotWaiters.append(continuation)
            }
        }
    }

    func recordCompletion(hostID: UUID) {
        completed.append(hostID)
        completionWaiters.removeValue(forKey: hostID)?.forEach { $0.resume() }
    }

    func waitForCompletion(of hostID: UUID) async {
        while !completed.contains(hostID) {
            await withCheckedContinuation { continuation in
                completionWaiters[hostID, default: []].append(continuation)
            }
        }
    }

    func releaseBlockedSnapshot() {
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

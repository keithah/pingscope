import Foundation
import CoreGraphics
@testable import PingScopeCore
@testable import PingScopeHistoryKit
@testable import PingScopeiOS
import XCTest

final class IOSResourceEfficiencyTests: XCTestCase {
    func testIOSAllHostsWidgetBuilderFallsBackToFirstEnabledHostWhenRememberedPrimaryIsAbsent() {
        let hosts = (0..<3).map { index in
            HostConfig(
                id: UUID(),
                displayName: "Host \(index + 1)",
                address: "host-\(index + 1).example"
            )
        }
        let snapshots = hosts.map { monitorSnapshot(host: $0, samples: []) }

        let widgetSnapshot = PingScopeIOSWidgetSnapshotBuilder.make(
            savedHosts: hosts,
            liveSnapshots: snapshots,
            rememberedPrimaryHostID: UUID(),
            scope: .allHosts,
            generatedAt: Date(timeIntervalSince1970: 10_000),
            isMonitoringActive: true
        )

        XCTAssertEqual(widgetSnapshot.hosts.map(\.id), hosts.map(\.id))
        XCTAssertEqual(widgetSnapshot.primaryHostID, hosts[0].id)
        XCTAssertEqual(widgetSnapshot.hosts.filter(\.isPrimary).map(\.id), [hosts[0].id])
    }

    func testIOSWidgetBuilderFocusedScopePublishesSavedOrderLiveCachedAndUnavailableHosts() throws {
        var hosts = (0..<6).map { index in
            HostConfig(
                id: UUID(),
                displayName: "Host \(index + 1)",
                address: "host-\(index + 1).example"
            )
        }
        hosts[1].isEnabled = false
        let selected = hosts[2]
        let selectedSamples = [sample(hostID: selected.id, seconds: 50), sample(hostID: selected.id, seconds: 55)]
        let cachedFirstSamples = [sample(hostID: hosts[0].id, seconds: 20)]
        let cachedFourthSamples = [sample(hostID: hosts[3].id, seconds: 25), sample(hostID: hosts[3].id, seconds: 30)]
        let cachedRows = [
            PingScopeIOSHostRowSnapshot(host: hosts[0], health: nil, samples: cachedFirstSamples, isCached: true, sampleLimit: 60),
            PingScopeIOSHostRowSnapshot(host: hosts[3], health: nil, samples: cachedFourthSamples, isCached: true, sampleLimit: 60),
            PingScopeIOSHostRowSnapshot(host: hosts[4], health: nil, samples: [], isCached: false, sampleLimit: 60),
            PingScopeIOSHostRowSnapshot(host: hosts[5], health: nil, samples: [], isCached: false, sampleLimit: 60),
        ]

        let widgetSnapshot = PingScopeIOSWidgetSnapshotBuilder.make(
            savedHosts: hosts,
            liveSnapshots: [monitorSnapshot(host: selected, samples: selectedSamples)],
            cachedRows: cachedRows,
            cachedSeries: [
                PingScopeIOSHostGraphSeries(host: hosts[0], samples: cachedFirstSamples),
                PingScopeIOSHostGraphSeries(host: hosts[3], samples: cachedFourthSamples),
            ],
            rememberedPrimaryHostID: selected.id,
            scope: .focused,
            generatedAt: Date(timeIntervalSince1970: 100),
            isMonitoringActive: true
        )

        let expectedHosts = [hosts[0], hosts[2], hosts[3], hosts[4], hosts[5]]
        XCTAssertEqual(widgetSnapshot.hosts.map(\.id), expectedHosts.map(\.id))
        XCTAssertEqual(widgetSnapshot.primaryHostID, selected.id)
        XCTAssertEqual(widgetSnapshot.monitoring, WidgetMonitoringContext(isActive: true, scope: .focused))
        XCTAssertEqual(widgetSnapshot.health.map(\.hostID), expectedHosts.map(\.id))
        XCTAssertEqual(widgetSnapshot.health.first { $0.hostID == selected.id }?.status, .healthy)
        XCTAssertEqual(widgetSnapshot.health.first { $0.hostID == selected.id }?.latencyMilliseconds, 55)
        XCTAssertEqual(widgetSnapshot.health.first { $0.hostID == hosts[0].id }?.status, .noData)
        XCTAssertEqual(widgetSnapshot.health.first { $0.hostID == hosts[0].id }?.latencyMilliseconds, 20)
        XCTAssertNil(widgetSnapshot.health.first { $0.hostID == hosts[4].id }?.latencyMilliseconds)
        XCTAssertEqual(Set(widgetSnapshot.recentSamples.map(\.hostID)), Set([hosts[0].id, selected.id, hosts[3].id]))
        XCTAssertTrue(widgetSnapshot.recentSamples.allSatisfy { sample in
            sample.hostID == selected.id || sample.hostID == hosts[0].id || sample.hostID == hosts[3].id
        })
    }

    func testIOSWidgetBuilderFairlyCapsMixedCadenceAllHostSamplesAtSixty() {
        let hosts = (0..<6).map { index in
            HostConfig(id: UUID(), displayName: "Host \(index + 1)", address: "host-\(index + 1).example")
        }
        let samplesByHost: [[PingResult]] = [
            (0..<100).map { sample(hostID: hosts[0].id, seconds: TimeInterval(1_000 + $0)) },
            [sample(hostID: hosts[1].id, seconds: 1)],
            (0..<3).map { sample(hostID: hosts[2].id, seconds: TimeInterval(10 + $0)) },
            (0..<80).map { sample(hostID: hosts[3].id, seconds: TimeInterval(2_000 + $0)) },
            [],
            (0..<2).map { sample(hostID: hosts[5].id, seconds: TimeInterval(30 + $0)) },
        ]

        let widgetSnapshot = PingScopeIOSWidgetSnapshotBuilder.make(
            savedHosts: hosts,
            liveSnapshots: zip(hosts, samplesByHost).map { monitorSnapshot(host: $0.0, samples: $0.1) },
            rememberedPrimaryHostID: hosts[0].id,
            scope: .allHosts,
            generatedAt: Date(timeIntervalSince1970: 3_000),
            isMonitoringActive: true
        )

        XCTAssertEqual(widgetSnapshot.hosts.map(\.id), hosts.map(\.id), "the transport retains all six saved hosts")
        XCTAssertEqual(Array(widgetSnapshot.hosts.prefix(5)).map(\.id), Array(hosts.prefix(5)).map(\.id))
        XCTAssertEqual(widgetSnapshot.recentSamples.count, PingScopeIOSWidgetSnapshotBuilder.transportSampleLimit)
        XCTAssertEqual(
            Set(widgetSnapshot.recentSamples.map(\.hostID)),
            Set([hosts[0].id, hosts[1].id, hosts[2].id, hosts[3].id, hosts[5].id]),
            "every host with usable data must survive fair allocation"
        )
        XCTAssertTrue(widgetSnapshot.recentSamples.allSatisfy { sample in
            samplesByHost.flatMap { $0 }.contains { $0.id == sample.id && $0.hostID == sample.hostID }
        })
    }

    func testIOSWidgetBuilderFiltersDisabledRememberedSelectionForTwoThroughSixHosts() {
        for count in 2...6 {
            var hosts = (0..<count).map { index in
                HostConfig(id: UUID(), displayName: "Host \(index + 1)", address: "host-\(index + 1).example")
            }
            hosts[count - 1].isEnabled = false
            let snapshots = hosts.map { monitorSnapshot(host: $0, samples: [sample(hostID: $0.id, seconds: TimeInterval(count))]) }

            let widgetSnapshot = PingScopeIOSWidgetSnapshotBuilder.make(
                savedHosts: hosts,
                liveSnapshots: snapshots,
                rememberedPrimaryHostID: hosts[count - 1].id,
                scope: .focused,
                generatedAt: Date(timeIntervalSince1970: 100),
                isMonitoringActive: true
            )

            XCTAssertEqual(widgetSnapshot.hosts.map(\.id), hosts.dropLast().map(\.id), "count \(count)")
            XCTAssertEqual(widgetSnapshot.primaryHostID, hosts[0].id, "count \(count)")
            XCTAssertFalse(widgetSnapshot.recentSamples.contains { $0.hostID == hosts[count - 1].id }, "count \(count)")
        }
    }

    func testIOSWidgetPublisherSupplementallyWiresBothScopesThroughPureBuilder() throws {
        let appSource = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        let publisherStart = try XCTUnwrap(appSource.range(of: "private func publishWidgetSnapshot("))
        let publisherEnd = try XCTUnwrap(
            appSource.range(
                of: "private func beginBackgroundRuntimeIfNeeded(",
                range: publisherStart.upperBound..<appSource.endIndex
            )
        )
        let publisher = appSource[publisherStart.lowerBound..<publisherEnd.lowerBound]

        XCTAssertTrue(publisher.contains("liveSnapshots = await multiHostCoordinator.orderedSnapshots()"))
        XCTAssertTrue(publisher.contains("liveSnapshots = [snapshot]"))
        XCTAssertTrue(publisher.contains("PingScopeIOSWidgetSnapshotBuilder.make("))
        XCTAssertTrue(publisher.contains("savedHosts: hosts"))
        XCTAssertTrue(publisher.contains("cachedRows: isFocused ? allHostRows : []"))
        XCTAssertTrue(publisher.contains("cachedSeries: isFocused ? allHostGraphSeries : []"))
    }

    func testLatestSampleSelectionPreservesTrueMaxForOutOfOrderSeries() throws {
        let hostA = UUID()
        let hostB = UUID()
        let hostC = UUID()
        let series = [
            PingScopeIOSHostGraphSeries(
                hostID: hostA,
                samples: [sample(hostID: hostA, seconds: 100), sample(hostID: hostA, seconds: 5)]
            ),
            PingScopeIOSHostGraphSeries(
                hostID: hostB,
                samples: [sample(hostID: hostB, seconds: 2), sample(hostID: hostB, seconds: 9)]
            ),
            PingScopeIOSHostGraphSeries(
                hostID: hostC,
                samples: [sample(hostID: hostC, seconds: 3), sample(hostID: hostC, seconds: 7)]
            ),
            PingScopeIOSHostGraphSeries(hostID: UUID(), samples: []),
        ]

        let latest = try XCTUnwrap(PingScopeIOSResourceEfficiency.latestResult(in: series))

        XCTAssertEqual(latest.hostID, hostA)
        XCTAssertEqual(latest.timestamp, Date(timeIntervalSince1970: 100))
    }

    func testLatestSampleSelectionMatchesFlattenedMaxAcrossEdgeCases() {
        let hostA = UUID()
        let hostB = UUID()
        let tiedTimestamp = Date(timeIntervalSince1970: 20)
        let tiedA = PingResult.success(hostID: hostA, latency: .milliseconds(1), timestamp: tiedTimestamp)
        let tiedB = PingResult.success(hostID: hostB, latency: .milliseconds(2), timestamp: tiedTimestamp)
        let older = sample(hostID: hostB, seconds: 10)
        let cases: [[PingScopeIOSHostGraphSeries]] = [
            [],
            [PingScopeIOSHostGraphSeries(hostID: hostA, samples: [])],
            [
                PingScopeIOSHostGraphSeries(hostID: hostA, samples: [tiedA]),
                PingScopeIOSHostGraphSeries(hostID: hostB, samples: [tiedB, older]),
            ],
            [
                PingScopeIOSHostGraphSeries(hostID: hostB, samples: [older]),
                PingScopeIOSHostGraphSeries(hostID: hostA, samples: [tiedA]),
            ],
        ]

        for series in cases {
            let flattened = series.flatMap(\.samples).max { $0.timestamp < $1.timestamp }
            XCTAssertEqual(PingScopeIOSResourceEfficiency.latestResult(in: series), flattened)
        }
    }

    func testWidgetCheapGateOnlySkipsWhenPolicyCannotSaveSampleChanges() {
        let hostID = UUID()
        let previous = widgetSnapshot(hostID: hostID, generatedAt: 1_000, samples: [])
        let candidate = widgetSnapshot(hostID: hostID, generatedAt: 1_010, samples: [])
        let changedSamples = widgetSnapshot(
            hostID: hostID,
            generatedAt: 1_010,
            samples: [WidgetSample(result: sample(hostID: hostID, seconds: 1_009))]
        )
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 600, timelineReloadInterval: 300)

        XCTAssertTrue(PingScopeIOSWidgetCheapPublishGate.canSkipSampleConstruction(
            candidateWithoutSamples: candidate,
            previousSnapshot: previous,
            lastTimelineReloadAt: Date(timeIntervalSince1970: 1_000),
            policy: policy
        ))
        XCTAssertFalse(policy.decision(
            for: changedSamples,
            previousSnapshot: previous,
            lastTimelineReloadAt: Date(timeIntervalSince1970: 1_000)
        ).shouldSave)

        let timelineDue = widgetSnapshot(hostID: hostID, generatedAt: 1_301, samples: [])
        XCTAssertFalse(PingScopeIOSWidgetCheapPublishGate.canSkipSampleConstruction(
            candidateWithoutSamples: timelineDue,
            previousSnapshot: previous,
            lastTimelineReloadAt: Date(timeIntervalSince1970: 1_000),
            policy: policy
        ))
    }

    func testWidgetCheapGateMatchesPublishPolicyAcrossStateHeartbeatFeedAndTimelineMatrix() {
        let hostID = UUID()
        let previous = widgetSnapshot(hostID: hostID, generatedAt: 1_000, samples: [])
        let changedFeed = [WidgetSample(result: sample(hostID: hostID, seconds: 1_009))]
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 600, timelineReloadInterval: 300)

        struct Case {
            let name: String
            let previous: WidgetSnapshot?
            let generatedAt: TimeInterval
            let stateChanged: Bool
            let feed: [WidgetSample]
            let lastReloadAt: TimeInterval
            let expectedGate: Bool
            let expectedSave: Bool
        }
        let cases = [
            Case(name: "previous nil", previous: nil, generatedAt: 1_010, stateChanged: false, feed: [], lastReloadAt: 1_000, expectedGate: false, expectedSave: true),
            Case(name: "state changed", previous: previous, generatedAt: 1_010, stateChanged: true, feed: [], lastReloadAt: 1_000, expectedGate: false, expectedSave: true),
            Case(name: "heartbeat due", previous: previous, generatedAt: 1_600, stateChanged: false, feed: [], lastReloadAt: 1_550, expectedGate: false, expectedSave: true),
            Case(name: "changed feed timeline due", previous: previous, generatedAt: 1_301, stateChanged: false, feed: changedFeed, lastReloadAt: 1_000, expectedGate: false, expectedSave: true),
            Case(name: "changed feed timeline pending", previous: previous, generatedAt: 1_010, stateChanged: false, feed: changedFeed, lastReloadAt: 1_000, expectedGate: true, expectedSave: false),
            Case(name: "unchanged feed timeline due", previous: previous, generatedAt: 1_301, stateChanged: false, feed: [], lastReloadAt: 1_000, expectedGate: false, expectedSave: false),
            Case(name: "unchanged feed timeline pending", previous: previous, generatedAt: 1_010, stateChanged: false, feed: [], lastReloadAt: 1_000, expectedGate: true, expectedSave: false),
        ]

        for testCase in cases {
            var cheapCandidate = widgetSnapshot(hostID: hostID, generatedAt: testCase.generatedAt, samples: [])
            var fullCandidate = cheapCandidate
            if testCase.stateChanged {
                cheapCandidate.monitoring = WidgetMonitoringContext(isActive: false, scope: .focused)
                fullCandidate.monitoring = cheapCandidate.monitoring
            }
            fullCandidate.recentSamples = testCase.feed
            let lastReloadAt = Date(timeIntervalSince1970: testCase.lastReloadAt)
            let gate = PingScopeIOSWidgetCheapPublishGate.canSkipSampleConstruction(
                candidateWithoutSamples: cheapCandidate,
                previousSnapshot: testCase.previous,
                lastTimelineReloadAt: lastReloadAt,
                policy: policy
            )
            let decision = policy.decision(
                for: fullCandidate,
                previousSnapshot: testCase.previous,
                lastTimelineReloadAt: lastReloadAt
            )

            XCTAssertEqual(gate, testCase.expectedGate, testCase.name)
            XCTAssertEqual(decision.shouldSave, testCase.expectedSave, testCase.name)
            if gate {
                XCTAssertFalse(decision.shouldSave, "gate must never hide a policy save: \(testCase.name)")
            }
        }
    }

    func testAllHostPresentationCacheReusesUnchangedHostAndPreservesInputOrder() {
        let hostA = HostConfig(id: UUID(), displayName: "A", address: "a.example")
        let hostB = HostConfig(id: UUID(), displayName: "B", address: "b.example")
        let sampleA = sample(hostID: hostA.id, seconds: 1)
        let sampleB1 = sample(hostID: hostB.id, seconds: 2)
        let sampleB2 = sample(hostID: hostB.id, seconds: 3)
        var cache = PingScopeIOSAllHostPresentationCache()

        let first = cache.resolve([
            monitorSnapshot(host: hostA, samples: [sampleA]),
            monitorSnapshot(host: hostB, samples: [sampleB1]),
        ])
        XCTAssertEqual(first.recomputedHostIDs, [hostA.id, hostB.id])

        let second = cache.resolve([
            monitorSnapshot(host: hostB, samples: [sampleB1, sampleB2]),
            monitorSnapshot(host: hostA, samples: [sampleA]),
        ])

        XCTAssertEqual(second.rows.map(\.hostID), [hostB.id, hostA.id])
        XCTAssertEqual(second.series.map(\.hostID), [hostB.id, hostA.id])
        XCTAssertEqual(second.recomputedHostIDs, [hostB.id])
        XCTAssertEqual(second.reusedHostIDs, [hostA.id])
        XCTAssertTrue(second.hasPresentationChanges)

        let third = cache.resolve([
            monitorSnapshot(host: hostB, samples: [sampleB1, sampleB2]),
            monitorSnapshot(host: hostA, samples: [sampleA]),
        ])
        XCTAssertFalse(third.hasPresentationChanges)
        XCTAssertEqual(third.reusedHostIDs, [hostB.id, hostA.id])
    }

    func testAllHostPresentationCachePreservesFlattenedMaxForOutOfOrderSamples() throws {
        let hostA = HostConfig(id: UUID(), displayName: "A", address: "a.example")
        let hostB = HostConfig(id: UUID(), displayName: "B", address: "b.example")
        var cache = PingScopeIOSAllHostPresentationCache()

        let result = cache.resolve([
            monitorSnapshot(host: hostA, samples: [
                sample(hostID: hostA.id, seconds: 100),
                sample(hostID: hostA.id, seconds: 5),
            ]),
            monitorSnapshot(host: hostB, samples: [sample(hostID: hostB.id, seconds: 9)]),
        ])

        let latest = try XCTUnwrap(result.latestResult)
        XCTAssertEqual(latest.hostID, hostA.id)
        XCTAssertEqual(latest.timestamp, Date(timeIntervalSince1970: 100))
    }

    func testIdenticalAllHostRefreshSkipsInsightsDiagnosisAndEndDateAdvance() throws {
        let host = HostConfig(id: UUID(), displayName: "A", address: "a.example")
        let snapshots = [monitorSnapshot(host: host, samples: [sample(hostID: host.id, seconds: 10)])]
        var cache = PingScopeIOSAllHostPresentationCache()
        var refreshBuildCount = 0
        var diagnosisCount = 0
        var clock = Date(timeIntervalSince1970: 100)

        let first = cache.resolve(snapshots).valueIfPresentationChanged {
            refreshBuildCount += 1
            return (
                PingScopeIOSMonitorInsightsPresentation(
                    snapshots: snapshots,
                    diagnose: { hosts, healthByHost, networkStatus, _ in
                        diagnosisCount += 1
                        return NetworkPerspectiveDiagnoser().diagnose(
                            hosts: hosts,
                            healthByHost: healthByHost,
                            networkStatus: networkStatus
                        )
                    }
                ),
                clock
            )
        }
        clock = Date(timeIntervalSince1970: 101)
        let second = cache.resolve(snapshots).valueIfPresentationChanged {
            refreshBuildCount += 1
            return (
                PingScopeIOSMonitorInsightsPresentation(
                    snapshots: snapshots,
                    diagnose: { hosts, healthByHost, networkStatus, _ in
                        diagnosisCount += 1
                        return NetworkPerspectiveDiagnoser().diagnose(
                            hosts: hosts,
                            healthByHost: healthByHost,
                            networkStatus: networkStatus
                        )
                    }
                ),
                clock
            )
        }

        XCTAssertEqual(refreshBuildCount, 1)
        XCTAssertEqual(diagnosisCount, 1)
        XCTAssertEqual(try XCTUnwrap(first).1, Date(timeIntervalSince1970: 100))
        XCTAssertNil(second)
    }

    func testRefreshCadenceUsesAbsoluteProbeDeadlineAndBoundsFiniteCountdownRefresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            PingScopeIOSRefreshCadence.interval(
                nextProbeDeadline: now.addingTimeInterval(30),
                duration: .continuous,
                now: now
            ),
            .seconds(30)
        )
        XCTAssertEqual(
            PingScopeIOSRefreshCadence.interval(
                nextProbeDeadline: now.addingTimeInterval(30),
                duration: .oneMinute,
                now: now
            ),
            .seconds(2)
        )
        XCTAssertEqual(
            PingScopeIOSRefreshCadence.interval(
                nextProbeDeadline: now.addingTimeInterval(-1),
                duration: .continuous,
                now: now
            ),
            .milliseconds(250)
        )
    }

    func testControllerExposesCurrentBackedOffProbeInterval() async throws {
        let host = HostConfig(
            id: UUID(),
            displayName: "Down",
            address: "down.example",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let probe = ResourceRecordingProbe(results: [
            .failure(hostID: host.id, reason: .timeout),
            .failure(hostID: host.id, reason: .timeout),
        ])
        let clock = ManualClock()
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: ResourceStaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(probeInterval: .milliseconds(100)),
            clock: clock,
            now: { clock.currentDate }
        )

        await controller.start(duration: .continuous, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        let firstSnapshot = await controller.snapshot()
        XCTAssertEqual(firstSnapshot.session?.policy.probeInterval, .milliseconds(100))
        let firstInterval = await controller.nextProbeInterval()
        XCTAssertEqual(firstInterval, .milliseconds(100))

        clock.advance(by: .milliseconds(100))
        try await clock.waitForSleepers(atLeast: 1)
        let secondInterval = await controller.nextProbeInterval()
        XCTAssertEqual(secondInterval, .milliseconds(200))
        let secondDeadline = await controller.nextProbeDeadline()
        XCTAssertEqual(secondDeadline, clock.currentDate.addingTimeInterval(0.2))
        await controller.stop()
    }

    @MainActor
    func testAbsoluteDeadlineLoopRefreshesPromptlyAfterSlowInFlightRecovery() async throws {
        let host = HostConfig(
            id: UUID(),
            displayName: "Recovering",
            address: "recovering.example",
            thresholds: LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        )
        let clock = ManualClock()
        let probe = ResourceGatedRecoveryProbe(hostID: host.id)
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: ResourceGatedRecoveryProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(probeInterval: .seconds(30)),
            clock: clock,
            now: { clock.currentDate }
        )
        var observedStatuses: [(date: Date, status: HealthStatus)] = []
        let driver = PingScopeIOSRefreshLoopDriver(sleeper: { duration in
            try await clock.sleep(for: duration)
        })

        await controller.start(duration: .continuous, at: clock.baseDate)
        try await clock.waitForSleepers(atLeast: 1)
        driver.start { @MainActor in
            let snapshot = await controller.snapshot()
            observedStatuses.append((clock.currentDate, snapshot.health.status))
            let deadline = await controller.nextProbeDeadline()
            return PingScopeIOSRefreshCadence.interval(
                nextProbeDeadline: deadline,
                duration: .continuous,
                now: clock.currentDate
            )
        }
        try await clock.waitForSleepers(atLeast: 2)

        clock.advance(by: .seconds(30))
        await probe.waitForRecoveryProbe()
        try await clock.waitForSleepers(atLeast: 1)
        await probe.releaseRecovery()
        try await clock.waitForSleepers(atLeast: 2)

        clock.advance(by: .milliseconds(249))
        XCTAssertFalse(observedStatuses.contains { $0.status == .healthy })
        clock.advance(by: .milliseconds(1))
        try await clock.waitForSleepers(atLeast: 2)

        let recoveryRefresh = try XCTUnwrap(observedStatuses.first { $0.status == .healthy })
        XCTAssertEqual(recoveryRefresh.date, clock.baseDate.addingTimeInterval(30.25))
        driver.cancel()
        await controller.stop()
    }

    @MainActor
    func testRefreshLoopDriverDoesNotRetainOwnerWhileSleepIsSuspended() async throws {
        let clock = ManualClock()
        var driver: PingScopeIOSRefreshLoopDriver? = PingScopeIOSRefreshLoopDriver(sleeper: { duration in
            try await clock.sleep(for: duration)
        })
        weak var weakDriver: PingScopeIOSRefreshLoopDriver?
        weakDriver = driver
        driver?.start { .seconds(30) }
        try await clock.waitForSleepers(atLeast: 1)

        driver = nil
        await Task.yield()

        XCTAssertNil(weakDriver)
    }

    func testAllHostRefreshCadenceUsesEarliestControllerDeadline() async {
        let hostA = HostConfig(id: UUID(), displayName: "A", address: "a.example")
        let hostB = HostConfig(id: UUID(), displayName: "B", address: "b.example")
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinator = PingScopeIOSMultiHostSessionCoordinator(
            controllerFactory: ResourceIntervalControllerFactory(deadlines: [
                hostA.id: now.addingTimeInterval(30),
                hostB.id: now.addingTimeInterval(5),
            ])
        )

        await coordinator.reconcile(hosts: [hostA, hostB])

        let deadline = await coordinator.nextProbeDeadline()
        XCTAssertEqual(deadline, now.addingTimeInterval(5))
    }

    func testRefreshLoopCapturesModelWeakly() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        XCTAssertTrue(source.contains("refreshLoopDriver.start { @MainActor [weak self] in"))
    }

    func testIOSAppUsesConservativeWidgetGateBeforeSampleConstruction() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        XCTAssertTrue(source.contains("PingScopeIOSWidgetCheapPublishGate.canSkipSampleConstruction"))
        XCTAssertTrue(source.contains("includeRecentSamples: false"))
    }

    func testIOSAppUsesPerHostPresentationDeltaCache() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        XCTAssertTrue(source.contains("allHostPresentationCache.resolve(snapshots)"))
        XCTAssertTrue(source.contains("presentationUpdate.valueIfPresentationChanged"))
    }

    func testIOSAppRefreshLoopReadsExposedProbeCadence() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        XCTAssertTrue(source.contains("await self.controller.nextProbeDeadline()"))
        XCTAssertTrue(source.contains("await self.multiHostCoordinator.nextProbeDeadline()"))
        XCTAssertTrue(source.contains("PingScopeIOSRefreshCadence.interval"))
    }

    func testFocusedHostSwitchBuildsControllerWithHostPolicyAndCurrentCadence() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        let switchStart = try XCTUnwrap(source.range(of: "private func switchToHostAsync("))
        let switchEnd = try XCTUnwrap(
            source.range(
                of: "private func switchToAllHostsAsync(",
                range: switchStart.upperBound..<source.endIndex
            )
        )
        let focusedSwitch = source[switchStart.lowerBound..<switchEnd.lowerBound]

        XCTAssertTrue(focusedSwitch.contains("policy: MonitorSessionPolicy(probeInterval: host.interval)"))
        XCTAssertTrue(focusedSwitch.contains("cadenceInputs: self.cadenceInputs"))
    }

    func testHistoryContentMemoKeepsFourSelections() {
        var memo = PingScopeIOSHistoryContentMemo<HistoryNetworkSelection, Int>()
        let selections: [HistoryNetworkSelection] = [
            .all,
            .network(HistoryNetworkKey(interface: "wifi", name: "Office")),
            .network(HistoryNetworkKey(interface: "wired", name: "Desk")),
            .network(HistoryNetworkKey(interface: "cellular", name: "Mobile")),
        ]
        var buildCount = 0

        for (index, selection) in selections.enumerated() {
            XCTAssertEqual(memo.resolve(selection) {
                buildCount += 1
                return index
            }, index)
        }
        XCTAssertEqual(memo.resolve(.all) {
            buildCount += 1
            return 99
        }, 0)
        XCTAssertEqual(buildCount, selections.count)
    }

    func testHistoryContentMemoHitsWhenReturningToAllNetworks() {
        var memo = PingScopeIOSHistoryContentMemo<HistoryNetworkSelection, Int>()
        let wifi = HistoryNetworkKey(interface: "wifi", name: "Office")
        var buildCount = 0

        let allFirst = memo.resolve(.all) {
            buildCount += 1
            return 1
        }
        let network = memo.resolve(.network(wifi)) {
            buildCount += 1
            return 2
        }
        let allAgain = memo.resolve(.all) {
            buildCount += 1
            return 3
        }

        XCTAssertEqual(allFirst, 1)
        XCTAssertEqual(network, 2)
        XCTAssertEqual(allAgain, 1)
        XCTAssertEqual(buildCount, 2)
    }

    func testHistoryAverageSegmentsSmoothOnceForFillAndStroke() throws {
        let source = try sourceFile("Sources/PingScopeiOS/PingScopeIOSHistoryChartView.swift")
        let graphCard = try XCTUnwrap(source.components(separatedBy: "private struct HistoryLatencyGraphCard").last)
            .components(separatedBy: "private struct HistorySessionCard")[0]
        XCTAssertEqual(graphCard.components(separatedBy: "LatencyCurve.smoothedPath").count - 1, 1)
    }

    func testAveragePathBuilderProducesSameCurveWithOneComputation() throws {
        let points = [CGPoint(x: 0, y: 8), CGPoint(x: 10, y: 2), CGPoint(x: 20, y: 6)]
        var computationCount = 0

        let paths = PingScopeIOSAveragePathBuilder.build(segments: [points, [CGPoint(x: 4, y: 4)], []]) { segment in
            computationCount += 1
            return LatencyCurve.smoothedPath(points: segment, closed: false)
        }

        XCTAssertEqual(computationCount, 1)
        XCTAssertEqual(paths.count, 2)
        let line = try XCTUnwrap(paths[0].line)
        let expected = LatencyCurve.smoothedPath(points: points, closed: false)
        XCTAssertEqual(pathElements(line), pathElements(expected))
        XCTAssertNil(paths[1].line)
        XCTAssertEqual(paths[1].first, CGPoint(x: 4, y: 4))
        XCTAssertEqual(paths[1].last, CGPoint(x: 4, y: 4))
    }

    func testLiveActivityLatestTimestampContainsNoFullSeriesFlattening() throws {
        let source = try sourceFile("Sources/PingScopeiOSApp/PingScopeIOSApp.swift")
        let function = try XCTUnwrap(source.components(separatedBy: "private func liveActivityContentState(").last)
            .components(separatedBy: "\n    }\n}")[0]
        XCTAssertFalse(function.contains("flatMap(\\.samples)"))
        XCTAssertTrue(function.contains("allHostLatestResult?.timestamp"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private extension IOSResourceEfficiencyTests {
    func sample(hostID: UUID, seconds: TimeInterval) -> PingResult {
        PingResult.success(
            hostID: hostID,
            latency: .milliseconds(seconds),
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    func monitorSnapshot(host: HostConfig, samples: [PingResult]) -> LiveMonitorSessionSnapshot {
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        var series = SampleSeries(hostID: host.id)
        for sample in samples {
            health.ingest(sample)
            series.append(sample)
        }
        return LiveMonitorSessionSnapshot(host: host, session: nil, health: health, series: series)
    }

    func widgetSnapshot(hostID: UUID, generatedAt: TimeInterval, samples: [WidgetSample]) -> WidgetSnapshot {
        WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [WidgetHost(
                id: hostID,
                displayName: "Host",
                address: "host.example",
                method: .icmp,
                port: nil,
                isPrimary: true
            )],
            health: [WidgetHostHealth(
                hostID: hostID,
                status: .healthy,
                latencyMilliseconds: 12,
                consecutiveFailureCount: 0,
                failureReason: nil,
                latestResultAt: Date(timeIntervalSince1970: generatedAt)
            )],
            recentSamples: samples,
            networkStatus: .connected,
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            monitoring: WidgetMonitoringContext(isActive: true, scope: .allHosts)
        )
    }

    func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func pathElements(_ path: CGPath) -> [String] {
        var result: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let pointCount = switch element.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            case .closeSubpath: 0
            @unknown default: 0
            }
            let points = (0..<pointCount).map { index in
                let point = element.points[index]
                return "\(point.x),\(point.y)"
            }.joined(separator: ";")
            result.append("\(element.type.rawValue):\(points)")
        }
        return result
    }
}

private actor ResourceRecordingProbe: PingProbe {
    private var results: [PingResult]

    init(results: [PingResult]) {
        self.results = results
    }

    func measure(_ host: HostConfig) async -> PingResult {
        guard !results.isEmpty else {
            return .failure(hostID: host.id, reason: .timeout)
        }
        return results.removeFirst()
    }
}

private struct ResourceStaticProbeFactory: ProbeFactory {
    let probe: ResourceRecordingProbe

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

private actor ResourceGatedRecoveryProbe: PingProbe {
    private let hostID: UUID
    private var measurementCount = 0
    private var recoveryStarted = false
    private var recoveryReleased = false
    private var recoveryStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var recoveryReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(hostID: UUID) {
        self.hostID = hostID
    }

    func measure(_ host: HostConfig) async -> PingResult {
        measurementCount += 1
        guard measurementCount > 1 else {
            return .failure(hostID: hostID, reason: .timeout)
        }
        recoveryStarted = true
        recoveryStartWaiters.forEach { $0.resume() }
        recoveryStartWaiters.removeAll()
        while !recoveryReleased {
            await withCheckedContinuation { continuation in
                recoveryReleaseWaiters.append(continuation)
            }
        }
        return .success(hostID: hostID, latency: .milliseconds(10))
    }

    func waitForRecoveryProbe() async {
        while !recoveryStarted {
            await withCheckedContinuation { continuation in
                recoveryStartWaiters.append(continuation)
            }
        }
    }

    func releaseRecovery() {
        recoveryReleased = true
        recoveryReleaseWaiters.forEach { $0.resume() }
        recoveryReleaseWaiters.removeAll()
    }
}

private struct ResourceGatedRecoveryProbeFactory: ProbeFactory {
    let probe: ResourceGatedRecoveryProbe

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

private struct ResourceIntervalControllerFactory: PingScopeIOSMultiHostSessionControllerFactory {
    let deadlines: [UUID: Date]

    func makeController(
        for host: HostConfig,
        historyStore: (any PingHistoryStore)?,
        historySampleEnricher: @escaping PingScopeIOSHistorySampleEnricher,
        measurementObserver: @escaping PingScopeIOSMeasurementObserver
    ) async -> any PingScopeIOSMultiHostSessionControlling {
        ResourceIntervalController(
            host: host,
            deadline: deadlines[host.id] ?? .distantFuture
        )
    }
}

private actor ResourceIntervalController: PingScopeIOSMultiHostSessionControlling {
    let host: HostConfig
    let deadline: Date

    init(host: HostConfig, deadline: Date) {
        self.host = host
        self.deadline = deadline
    }

    func start(duration: MonitorSessionDuration, at date: Date) async {}

    func stop(reason: MonitorSessionEndReason, at date: Date) async {}

    func restoreAfterSupersededReconciliation(from snapshot: LiveMonitorSessionSnapshot) async {}

    func snapshot() async -> LiveMonitorSessionSnapshot {
        LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
    }

    func nextProbeInterval() async -> Duration {
        MonitorSessionPolicy().probeInterval
    }

    func nextProbeDeadline() async -> Date {
        deadline
    }
}

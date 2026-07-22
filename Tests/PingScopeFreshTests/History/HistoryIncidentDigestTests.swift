import XCTest
@testable import PingScopeCore
@testable import PingScopeHistoryKit

final class HistoryIncidentDigestTests: XCTestCase {
    func testIncidentLogDerivesClosedOngoingBackToBackAndSingleSampleSpans() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            success(hostID, at: start, latency: 12),
            failure(hostID, at: start.addingTimeInterval(10)),
            failure(hostID, at: start.addingTimeInterval(20)),
            success(hostID, at: start.addingTimeInterval(30), latency: 25),
            failure(hostID, at: start.addingTimeInterval(40)),
            success(hostID, at: start.addingTimeInterval(50), latency: 18),
            failure(hostID, at: start.addingTimeInterval(60))
        ]

        let log = HistoryIncidentLog(samples: samples, endingAt: start.addingTimeInterval(90))

        XCTAssertEqual(log.incidents.count, 3)
        XCTAssertEqual(log.incidents[0].startDate, start.addingTimeInterval(10))
        XCTAssertEqual(log.incidents[0].endDate, start.addingTimeInterval(30))
        XCTAssertEqual(log.incidents[0].duration, 20)
        XCTAssertEqual(log.incidents[0].sampleCount, 2)
        XCTAssertEqual(log.incidents[1].duration, 10)
        XCTAssertEqual(log.incidents[1].sampleCount, 1)
        XCTAssertNil(log.incidents[2].endDate)
        XCTAssertEqual(log.incidents[2].duration, 30)
        XCTAssertEqual(log.incidents[2].sampleCount, 1)
    }

    func testIncidentLogIsStableForUnsortedInputAndCarriesOnsetDiagnosisAndWorstLatency() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 2_000)
        let onset = PingResult(
            hostID: hostID,
            timestamp: start,
            latency: .milliseconds(150),
            failureReason: .timeout
        )
        let later = failure(hostID, at: start.addingTimeInterval(5))
        let recovery = success(hostID, at: start.addingTimeInterval(10), latency: 20)
        let diagnosis = NetworkPerspectiveDiagnosis(
            scope: .upstream,
            title: "Internet path unavailable",
            detail: "Upstream targets failed.",
            faultTier: .upstream
        )

        let log = HistoryIncidentLog(
            samples: [recovery, later, onset],
            endingAt: recovery.timestamp,
            diagnosesBySampleID: [onset.id: diagnosis]
        )

        let incident = try XCTUnwrap(log.incidents.first)
        XCTAssertEqual(incident.startDate, start)
        XCTAssertEqual(incident.endDate, recovery.timestamp)
        XCTAssertEqual(incident.worstLatencyMilliseconds, 150)
        XCTAssertEqual(incident.onsetDiagnosisScope, .upstream)
        XCTAssertEqual(incident.onsetFaultTier, .upstream)
    }

    func testIncidentLogHandlesEmptyAndNoIncidentSamples() {
        let hostID = UUID()
        let now = Date(timeIntervalSince1970: 3_000)
        XCTAssertEqual(HistoryIncidentLog(samples: [], endingAt: now).incidents, [])
        XCTAssertEqual(
            HistoryIncidentLog(samples: [success(hostID, at: now, latency: 9)], endingAt: now).incidents,
            []
        )
    }

    func testIncidentLogReusesNetworkPerspectiveDiagnoserAtOnset() throws {
        let at = Date(timeIntervalSince1970: 4_000)
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let gateway = HostConfig(
            displayName: "Gateway",
            address: "192.168.1.1",
            tier: .localGateway,
            thresholds: thresholds
        )
        let internet = HostConfig(
            displayName: "Internet",
            address: "1.1.1.1",
            tier: .upstream,
            thresholds: thresholds
        )
        let gatewayFailure = failure(gateway.id, at: at)
        let internetFailure = failure(internet.id, at: at)

        let log = HistoryIncidentLog(
            samples: [gatewayFailure],
            host: gateway,
            allHosts: [gateway, internet],
            samplesByHost: [gateway.id: [gatewayFailure], internet.id: [internetFailure]],
            endingAt: at.addingTimeInterval(10)
        )

        XCTAssertEqual(try XCTUnwrap(log.incidents.first).onsetDiagnosisScope, .localNetwork)
    }

    func testIncidentOnsetUsesLatestInterleavedSamplesAcrossHosts() throws {
        let start = Date(timeIntervalSince1970: 4_500)
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 1)
        let gateway = HostConfig(
            displayName: "Gateway",
            address: "192.168.1.1",
            tier: .localGateway,
            thresholds: thresholds
        )
        let upstream = HostConfig(
            displayName: "Upstream",
            address: "1.1.1.1",
            tier: .upstream,
            thresholds: thresholds
        )
        let onsetCount = 16
        var gatewaySamples: [PingResult] = []
        var upstreamSamples: [PingResult] = []

        for index in 0..<onsetCount {
            let onset = start.addingTimeInterval(Double(index * 20 + 10))
            gatewaySamples.append(failure(gateway.id, at: onset))
            gatewaySamples.append(success(gateway.id, at: onset.addingTimeInterval(10), latency: 10))
            upstreamSamples.append(success(upstream.id, at: onset.addingTimeInterval(-5), latency: 20))
        }

        let lookupWorkCounter = IncidentOnsetLookupWorkCounter()
        let log = HistoryIncidentLog(
            samples: gatewaySamples.reversed(),
            host: gateway,
            allHosts: [gateway, upstream],
            samplesByHost: [
                gateway.id: gatewaySamples.reversed(),
                upstream.id: upstreamSamples.reversed()
            ],
            endingAt: start.addingTimeInterval(Double(onsetCount * 20 + 10)),
            lookupWorkCounter: lookupWorkCounter
        )

        let expectedOnsets = (0..<onsetCount).map {
            start.addingTimeInterval(Double($0 * 20 + 10))
        }
        XCTAssertEqual(log.incidents.map(\.startDate), expectedOnsets)
        XCTAssertEqual(log.incidents.map(\.endDate), expectedOnsets.map { $0.addingTimeInterval(10) })
        XCTAssertEqual(log.incidents.map(\.sampleCount), Array(repeating: 1, count: onsetCount))
        XCTAssertEqual(log.incidents.map(\.onsetDiagnosisScope), Array(repeating: .localNetwork, count: onsetCount))
        XCTAssertEqual(log.incidents.map(\.onsetFaultTier), Array(repeating: .localGateway, count: onsetCount))
        XCTAssertLessThanOrEqual(lookupWorkCounter.count, 47)
    }

    func testWeeklyDigestAggregatesSevenDayWindowAcrossHostsIncludingNoDataHosts() throws {
        let endingAt = Date(timeIntervalSince1970: 10_000)
        let first = HostConfig(id: UUID(), displayName: "First", address: "1.1.1.1")
        let second = HostConfig(id: UUID(), displayName: "Second", address: "8.8.8.8")
        let noData = HostConfig(id: UUID(), displayName: "No data", address: "9.9.9.9")
        let firstSamples = [
            success(first.id, at: endingAt.addingTimeInterval(-40), latency: 10, interface: "wifi"),
            failure(first.id, at: endingAt.addingTimeInterval(-30), interface: "wifi"),
            success(first.id, at: endingAt.addingTimeInterval(-20), latency: 30, interface: "wifi")
        ]
        let secondSamples = [
            success(second.id, at: endingAt.addingTimeInterval(-40), latency: 50, interface: "cellular"),
            failure(second.id, at: endingAt.addingTimeInterval(-20), interface: "cellular")
        ]

        let digest = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [first, second, noData],
            samplesByHost: [first.id: firstSamples, second.id: secondSamples],
            endingAt: endingAt
        ))

        XCTAssertEqual(digest.monitoredHostCount, 3)
        XCTAssertEqual(digest.hostsWithDataCount, 2)
        XCTAssertEqual(digest.sampleCount, 5)
        XCTAssertEqual(digest.uptimePercent, 60, accuracy: 0.001)
        XCTAssertEqual(digest.incidentCount, 2)
        XCTAssertEqual(digest.totalDowntime, 30, accuracy: 0.001)
        XCTAssertEqual(digest.worstHostID, second.id)
        XCTAssertEqual(digest.worstHostName, "Second")
        XCTAssertEqual(digest.averageMilliseconds, 30)
        XCTAssertEqual(digest.p95Milliseconds, 50)
        XCTAssertEqual(digest.busiestInterface, "wifi")
        XCTAssertEqual(digest.busiestInterfaceLabel, "Wi-Fi")
    }

    func testWeeklyDigestExcludesSamplesOutsideWindowAndIsStructurallyAbsentWithoutHistory() {
        let endingAt = Date(timeIntervalSince1970: 1_000_000)
        let host = HostConfig(id: UUID(), displayName: "Host", address: "example.com")
        let old = success(host.id, at: endingAt.addingTimeInterval(-(7 * 86_400) - 1), latency: 999)

        XCTAssertNil(HistoryWeeklyDigest.make(hosts: [host], samplesByHost: [:], endingAt: endingAt))
        XCTAssertNil(HistoryWeeklyDigest.make(hosts: [host], samplesByHost: [host.id: [old]], endingAt: endingAt))
    }

    func testWeeklyDigestIncludesSampleExactlyAtLowerBoundary() throws {
        let endingAt = Date(timeIntervalSince1970: 2_000_000)
        let host = HostConfig(id: UUID(), displayName: "Boundary", address: "example.com")
        let boundary = success(
            host.id,
            at: endingAt.addingTimeInterval(-HistoryWeeklyDigest.windowDuration),
            latency: 12
        )

        let digest = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [host], samplesByHost: [host.id: [boundary]], endingAt: endingAt
        ))

        XCTAssertEqual(digest.sampleCount, 1)
    }

    func testWeeklyDigestPreparedInputsPreserveExistingMetricAndIncidentMath() throws {
        let endingAt = Date(timeIntervalSince1970: 2_500_000)
        let first = HostConfig(id: UUID(), displayName: "First", address: "first.example.com")
        let second = HostConfig(id: UUID(), displayName: "Second", address: "second.example.com")
        var starlinkSuccess = success(
            first.id,
            at: endingAt.addingTimeInterval(-50),
            latency: 10,
            interface: "wifi"
        )
        starlinkSuccess.metadata = ProbeMetadata(
            starlink: StarlinkTelemetry(popPingDropRate: 0.25)
        )
        let samplesByHost = [
            first.id: [
                starlinkSuccess,
                failure(first.id, at: endingAt.addingTimeInterval(-40), interface: "wifi"),
                success(first.id, at: endingAt.addingTimeInterval(-20), latency: 30, interface: "wifi")
            ],
            second.id: [
                success(second.id, at: endingAt.addingTimeInterval(-45), latency: 50, interface: "cellular"),
                PingResult(
                    hostID: second.id,
                    timestamp: endingAt.addingTimeInterval(-10),
                    latency: .milliseconds(150),
                    failureReason: .timeout,
                    networkInterface: "cellular"
                )
            ]
        ]
        let legacy = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [first, second],
            samplesByHost: samplesByHost,
            endingAt: endingAt
        ))
        let prepared = samplesByHost.values.flatMap { $0 }.map(HistoryWeeklyDigestSample.init)

        let reduced = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: [first, second],
            samples: prepared,
            endingAt: endingAt
        ))

        XCTAssertEqual(reduced, legacy)
    }

    func testSQLiteWeeklyDigestStreamMatchesLegacyDigestAcrossHostChunks() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PingScope-weekly-stream-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let endingAt = Date(timeIntervalSince1970: 3_000_000)
        let hosts = (0..<7).map { index in
            HostConfig(
                id: UUID(),
                displayName: "Host \(index)",
                address: "host-\(index).example.com"
            )
        }
        var samplesByHost: [UUID: [PingResult]] = [:]
        for (index, host) in hosts.enumerated() {
            samplesByHost[host.id] = [
                success(
                    host.id,
                    at: endingAt.addingTimeInterval(-Double(100 + index)),
                    latency: Double(10 + index),
                    interface: index.isMultiple(of: 2) ? "wifi" : "cellular"
                ),
                failure(
                    host.id,
                    at: endingAt.addingTimeInterval(-Double(50 + index)),
                    interface: index.isMultiple(of: 2) ? "wifi" : "cellular"
                ),
            ]
        }
        let store = SQLiteHistoryStore(
            url: url,
            retention: .days(30),
            sqliteVariableNumberLimitForTesting: 5
        )
        try await store.appendAndWait(samplesByHost.values.flatMap { $0 }.reversed())
        let legacy = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: hosts,
            samplesByHost: samplesByHost,
            endingAt: endingAt
        ))

        var streamed: [HistoryWeeklyDigestSample] = []
        for await sample in store.weeklyDigestSampleStream(
            hostIDs: Array(hosts.map(\.id).reversed()),
            since: endingAt.addingTimeInterval(-HistoryWeeklyDigest.windowDuration),
            through: endingAt
        ) {
            streamed.append(sample)
        }
        let streamingDigest = try XCTUnwrap(HistoryWeeklyDigest.make(
            hosts: hosts,
            samples: streamed,
            endingAt: endingAt
        ))

        XCTAssertEqual(streamingDigest, legacy)
        XCTAssertEqual(streamed.count, samplesByHost.values.reduce(0) { $0 + $1.count })
        XCTAssertEqual(streamed.map(\.id), streamed.sorted(by: weeklySampleOrder).map(\.id))
    }

    func testNetworkBreakdownAccumulatorProducesExpectedMixedNetworkGroups() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 2_750_000)
        var officeFirst = PingResult.success(
            hostID: hostID,
            latency: .milliseconds(30),
            timestamp: start.addingTimeInterval(30),
            networkInterface: "Wi-Fi",
            networkName: " Office ",
            isVPN: true
        )
        officeFirst.metadata = ProbeMetadata(starlink: StarlinkTelemetry(popPingDropRate: 0.25))
        let officeFailure = PingResult.failure(
            hostID: hostID,
            reason: .timeout,
            timestamp: start.addingTimeInterval(10),
            networkInterface: "wifi",
            networkName: "Office"
        )
        let officeLast = PingResult.success(
            hostID: hostID,
            latency: .milliseconds(10),
            timestamp: start.addingTimeInterval(50),
            networkInterface: "wifi",
            networkName: "Office"
        )
        let cellularLast = success(hostID, at: start.addingTimeInterval(40), latency: 15, interface: "cellular")
        let unknown = failure(hostID, at: start.addingTimeInterval(20))
        let cellularFirst = success(hostID, at: start, latency: 5, interface: "cellular")

        let breakdown = HistoryNetworkBreakdown(accumulating: [
            officeFirst,
            cellularLast,
            unknown,
            officeFailure,
            cellularFirst,
            officeLast
        ])

        XCTAssertEqual(breakdown.groups.map(\.displayLabel), ["Unknown", "Office", "Cellular"])

        let unknownGroup = breakdown.groups[0]
        XCTAssertEqual(unknownGroup.key, .unknown)
        XCTAssertNil(unknownGroup.interface)
        XCTAssertEqual(unknownGroup.sampleCount, 1)
        XCTAssertEqual(unknownGroup.firstSeen, unknown.timestamp)
        XCTAssertEqual(unknownGroup.lastSeen, unknown.timestamp)
        XCTAssertEqual(unknownGroup.samples.map(\.id), [unknown.id])
        XCTAssertFalse(unknownGroup.hasVPN)
        XCTAssertNil(unknownGroup.metrics.averageMilliseconds)
        XCTAssertNil(unknownGroup.metrics.p95Milliseconds)
        XCTAssertEqual(unknownGroup.metrics.lossPercent, 100, accuracy: 0.001)
        XCTAssertEqual(unknownGroup.metrics.uptimePercent, 0, accuracy: 0.001)
        XCTAssertEqual(unknownGroup.metrics.outageCount, 1)

        let officeGroup = breakdown.groups[1]
        XCTAssertEqual(officeGroup.key, HistoryNetworkKey(interface: "wifi", name: "Office"))
        XCTAssertEqual(officeGroup.interface, "wifi")
        XCTAssertEqual(officeGroup.sampleCount, 3)
        XCTAssertEqual(officeGroup.firstSeen, officeFailure.timestamp)
        XCTAssertEqual(officeGroup.lastSeen, officeLast.timestamp)
        XCTAssertEqual(officeGroup.samples.map(\.id), [officeFirst.id, officeFailure.id, officeLast.id])
        XCTAssertTrue(officeGroup.hasVPN)
        XCTAssertEqual(try XCTUnwrap(officeGroup.metrics.averageMilliseconds), 20, accuracy: 0.001)
        XCTAssertEqual(officeGroup.metrics.p95Milliseconds, 30)
        XCTAssertEqual(officeGroup.metrics.minimumMilliseconds, 10)
        XCTAssertEqual(officeGroup.metrics.maximumMilliseconds, 30)
        XCTAssertEqual(officeGroup.metrics.lossPercent, 41.666, accuracy: 0.001)
        XCTAssertEqual(officeGroup.metrics.uptimePercent, 58.333, accuracy: 0.001)
        XCTAssertEqual(officeGroup.metrics.outageCount, 1)

        let cellularGroup = breakdown.groups[2]
        XCTAssertEqual(cellularGroup.key, HistoryNetworkKey(interface: "cellular", name: nil))
        XCTAssertEqual(cellularGroup.interface, "cellular")
        XCTAssertEqual(cellularGroup.sampleCount, 2)
        XCTAssertEqual(cellularGroup.firstSeen, cellularFirst.timestamp)
        XCTAssertEqual(cellularGroup.lastSeen, cellularLast.timestamp)
        XCTAssertEqual(cellularGroup.samples.map(\.id), [cellularLast.id, cellularFirst.id])
        XCTAssertFalse(cellularGroup.hasVPN)
        XCTAssertEqual(cellularGroup.metrics.averageMilliseconds, 10)
        XCTAssertEqual(cellularGroup.metrics.p95Milliseconds, 15)
        XCTAssertEqual(cellularGroup.metrics.lossPercent, 0, accuracy: 0.001)
        XCTAssertEqual(cellularGroup.metrics.uptimePercent, 100, accuracy: 0.001)
        XCTAssertEqual(cellularGroup.metrics.outageCount, 0)
    }

    func testWeeklyDigestLoaderQueriesUncoveredTailBeforePromotingCoverage() async throws {
        let firstEnd = Date(timeIntervalSince1970: 2_800_000)
        let secondEnd = firstEnd.addingTimeInterval(1)
        let host = HostConfig(id: UUID(), displayName: "Coverage", address: "coverage.example.com")
        let beforeFirstEnd = success(host.id, at: firstEnd.addingTimeInterval(-30), latency: 10)
        let betweenEnds = success(host.id, at: firstEnd.addingTimeInterval(0.5), latency: 20)
        let store = RangeFilteringWeeklyDigestStore(samples: [beforeFirstEnd, betweenEnds])
        let loader = HistoryWeeklyDigestLoader()

        let firstResult = await loader.load(store: store, hosts: [host], endingAt: firstEnd)
        let secondResult = await loader.load(store: store, hosts: [host], endingAt: secondEnd)
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)
        let queryCount = await store.queryCount

        XCTAssertEqual(first.sampleCount, 1)
        XCTAssertEqual(second.sampleCount, 2)
        XCTAssertEqual(second.endDate, secondEnd)
        XCTAssertEqual(queryCount, 2)
    }

    func testWeeklyDigestLoaderReusesCachedPrefixAfterAppendOnlyRevisionChange() async throws {
        let firstEnd = Date(timeIntervalSince1970: 2_850_000)
        let secondEnd = firstEnd.addingTimeInterval(1)
        let host = HostConfig(id: UUID(), displayName: "Append", address: "append.example.com")
        let beforeFirstEnd = success(host.id, at: firstEnd.addingTimeInterval(-30), latency: 10)
        let betweenEnds = success(host.id, at: firstEnd.addingTimeInterval(0.5), latency: 20)
        let store = AppendOnlyRevisionWeeklyDigestStore(samples: [beforeFirstEnd, betweenEnds])
        let loader = HistoryWeeklyDigestLoader()

        _ = await loader.load(store: store, hosts: [host], endingAt: firstEnd)
        await store.advanceRevision()
        let second = await loader.load(store: store, hosts: [host], endingAt: secondEnd)
        let queryRanges = await store.queryRanges

        XCTAssertEqual(second?.sampleCount, 2)
        XCTAssertEqual(queryRanges.count, 2)
        XCTAssertEqual(queryRanges[1].since, firstEnd)
        XCTAssertEqual(queryRanges[1].through, secondEnd)
    }

    func testWeeklyDigestLoaderCoalescesInflightQueryWhenOneWaiterIsCancelled() async throws {
        let endingAt = Date(timeIntervalSince1970: 2_900_000)
        let host = HostConfig(id: UUID(), displayName: "Shared", address: "shared.example.com")
        let sample = success(host.id, at: endingAt.addingTimeInterval(-10), latency: 12)
        let store = SuspendedWeeklyDigestStore(samples: [sample])
        let loader = HistoryWeeklyDigestLoader()

        let cancelled = Task {
            await loader.load(store: store, hosts: [host], endingAt: endingAt)
        }
        await store.waitUntilQueryCount(atLeast: 1)
        let remaining = Task {
            await loader.load(store: store, hosts: [host], endingAt: endingAt)
        }
        await store.waitUntilSecondRevisionIsSuspended()
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        await store.resumeSecondRevision()
        await waitUntilLoaderHasWaiter(loader)
        let queryCountBeforeCompletion = await store.queryCount
        await store.resumeAllQueries()
        let remainingResult = await remaining.value
        let queryCount = await store.queryCount

        XCTAssertNil(cancelledResult)
        XCTAssertEqual(remainingResult?.sampleCount, 1)
        XCTAssertEqual(queryCountBeforeCompletion, 1)
        XCTAssertEqual(queryCount, 1)
    }

    func testWeeklyDigestLoaderReleasesCancelledRevisionReservationAndAdvancesCapacity() async throws {
        let endingAt = Date(timeIntervalSince1970: 2_925_000)
        let host = HostConfig(id: UUID(), displayName: "Reservation", address: "reservation.example.com")
        let sample = success(host.id, at: endingAt.addingTimeInterval(-10), latency: 18)
        let store = RevisionSuspendedWeeklyDigestStore(samples: [sample])
        let loader = HistoryWeeklyDigestLoader(capacity: 1)

        let first = Task {
            await loader.load(store: store, hosts: [host], endingAt: endingAt)
        }
        await store.waitUntilQueryCount(atLeast: 1)
        let suspendedPreparer = Task {
            await loader.load(store: store, hosts: [host], endingAt: endingAt)
        }
        await store.waitUntilSecondRevisionIsSuspended()
        let laterWindow = Task {
            await loader.load(store: store, hosts: [host], endingAt: endingAt.addingTimeInterval(1))
        }
        await waitUntilLoaderHasWaiter(loader, minimum: 2)

        let capacityAdvanced = expectation(description: "cancelled reservation releases active-flight capacity")
        let capacityObserver = Task {
            await store.waitUntilQueryCount(atLeast: 2)
            capacityAdvanced.fulfill()
        }
        suspendedPreparer.cancel()
        first.cancel()
        await fulfillment(of: [capacityAdvanced], timeout: 0.2)
        let beforeRevisionResume = await store.snapshot()

        await store.resumeSecondRevision()
        await capacityObserver.value
        let firstResult = await first.value
        let preparerResult = await suspendedPreparer.value
        let laterResult = await laterWindow.value

        XCTAssertEqual(beforeRevisionResume.queryCount, 2)
        XCTAssertEqual(beforeRevisionResume.cancelledQueryCount, 1)
        XCTAssertNil(firstResult)
        XCTAssertNil(preparerResult)
        XCTAssertEqual(laterResult?.sampleCount, 1)
    }

    func testWeeklyDigestLoaderBoundsDistinctCancelledFlights() async {
        let endingAt = Date(timeIntervalSince1970: 2_950_000)
        let host = HostConfig(id: UUID(), displayName: "Bounded", address: "bounded.example.com")
        let store = ManySuspendedWeeklyDigestStore()
        let loader = HistoryWeeklyDigestLoader(capacity: 2)
        let callersReleased = expectation(description: "cancelled weekly digest callers released")
        callersReleased.expectedFulfillmentCount = 24
        let callers = (0..<24).map { offset in
            Task {
                let result = await loader.load(
                    store: store,
                    hosts: [host],
                    endingAt: endingAt.addingTimeInterval(Double(offset))
                )
                callersReleased.fulfill()
                return result
            }
        }

        await store.waitUntilQueryCount(atLeast: 2)
        for _ in 0..<20 { await Task.yield() }
        callers.forEach { $0.cancel() }
        await fulfillment(of: [callersReleased], timeout: 1)
        let suspendedSnapshot = await store.snapshot()
        await store.resumeAll()
        await store.waitUntilActiveQueryCount(0)
        let results = await callers.asyncMap { await $0.value }
        let finalSnapshot = await store.snapshot()

        XCTAssertLessThanOrEqual(suspendedSnapshot.queryCount, 2)
        XCTAssertLessThanOrEqual(suspendedSnapshot.activeQueryCount, 2)
        XCTAssertLessThanOrEqual(suspendedSnapshot.maxActiveQueryCount, 2)
        XCTAssertLessThanOrEqual(finalSnapshot.queryCount, 2)
        XCTAssertEqual(finalSnapshot.activeQueryCount, 0)
        XCTAssertEqual(finalSnapshot.cancelledQueryCount, suspendedSnapshot.activeQueryCount)
        XCTAssertTrue(results.allSatisfy { $0 == nil })
    }

    func testIncidentLogAllFailingSamplesRemainOngoing() throws {
        let hostID = UUID()
        let start = Date(timeIntervalSince1970: 3_000_000)
        let samples = (0..<4).map { failure(hostID, at: start.addingTimeInterval(Double($0) * 10)) }

        let incident = try XCTUnwrap(HistoryIncidentLog(samples: samples, endingAt: start.addingTimeInterval(60)).incidents.single)

        XCTAssertNil(incident.endDate)
        XCTAssertEqual(incident.sampleCount, samples.count)
    }

    private func success(
        _ hostID: UUID,
        at date: Date,
        latency: Double,
        interface: String? = nil
    ) -> PingResult {
        .success(hostID: hostID, latency: .milliseconds(latency), timestamp: date, networkInterface: interface)
    }

    private func failure(_ hostID: UUID, at date: Date, interface: String? = nil) -> PingResult {
        .failure(hostID: hostID, reason: .timeout, timestamp: date, networkInterface: interface)
    }

    private func waitUntilLoaderHasWaiter(
        _ loader: HistoryWeeklyDigestLoader,
        minimum: Int = 1
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if await loader.activeWaiterCount() >= minimum { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for the identical request to register with the loader")
    }
}

private extension Collection where Element == HistoryIncident {
    var single: Element? { count == 1 ? first : nil }
}

private actor SuspendedWeeklyDigestStore: PingHistoryStore {
    private let inputs: [HistoryWeeklyDigestSample]
    private var revisionCallCount = 0
    private var secondRevisionContinuation: CheckedContinuation<Void, Never>?
    private var secondRevisionWaiters: [CheckedContinuation<Void, Never>] = []
    private var queryContinuations: [CheckedContinuation<Void, Never>] = []
    private var queryCountWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var queryCount = 0

    init(samples: [PingResult]) {
        inputs = samples.map(HistoryWeeklyDigestSample.init)
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        queryCount += 1
        let readyWaiters = queryCountWaiters.filter { queryCount >= $0.minimum }
        queryCountWaiters.removeAll { queryCount >= $0.minimum }
        readyWaiters.forEach { $0.continuation.resume() }
        await withCheckedContinuation { queryContinuations.append($0) }
        return inputs
    }
    func historyRevision() async -> UInt64 {
        revisionCallCount += 1
        if revisionCallCount == 2 {
            await withCheckedContinuation { continuation in
                secondRevisionContinuation = continuation
                secondRevisionWaiters.forEach { $0.resume() }
                secondRevisionWaiters.removeAll()
            }
        }
        return 1
    }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func waitUntilQueryCount(atLeast minimum: Int) async {
        if queryCount >= minimum { return }
        await withCheckedContinuation { queryCountWaiters.append((minimum, $0)) }
    }

    func waitUntilSecondRevisionIsSuspended() async {
        if secondRevisionContinuation != nil { return }
        await withCheckedContinuation { secondRevisionWaiters.append($0) }
    }

    func resumeSecondRevision() {
        secondRevisionContinuation?.resume()
        secondRevisionContinuation = nil
    }

    func resumeAllQueries() {
        queryContinuations.forEach { $0.resume() }
        queryContinuations.removeAll()
    }
}

private actor RangeFilteringWeeklyDigestStore: PingHistoryStore {
    private let inputs: [HistoryWeeklyDigestSample]
    private(set) var queryCount = 0

    init(samples: [PingResult]) {
        inputs = samples.map(HistoryWeeklyDigestSample.init)
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        queryCount += 1
        let includedHosts = Set(hostIDs)
        return inputs.filter {
            includedHosts.contains($0.hostID) && $0.timestamp >= since && $0.timestamp <= through
        }
    }
    func historyRevision() async -> UInt64 { 1 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}
}

private actor AppendOnlyRevisionWeeklyDigestStore: PingHistoryStore {
    struct QueryRange: Sendable {
        let since: Date
        let through: Date
    }

    private let inputs: [HistoryWeeklyDigestSample]
    private var revision: UInt64 = 1
    private(set) var queryRanges: [QueryRange] = []

    init(samples: [PingResult]) {
        inputs = samples.map(HistoryWeeklyDigestSample.init)
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        queryRanges.append(QueryRange(since: since, through: through))
        let includedHosts = Set(hostIDs)
        return inputs.filter {
            includedHosts.contains($0.hostID) && $0.timestamp >= since && $0.timestamp <= through
        }
    }
    func historyRevision() async -> UInt64 { revision }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func advanceRevision() {
        revision &+= 1
    }
}

private actor RevisionSuspendedWeeklyDigestStore: PingHistoryStore {
    struct Snapshot: Sendable {
        let queryCount: Int
        let cancelledQueryCount: Int
    }

    private let inputs: [HistoryWeeklyDigestSample]
    private var revisionCallCount = 0
    private var secondRevisionContinuation: CheckedContinuation<Void, Never>?
    private var secondRevisionWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstQueryContinuation: CheckedContinuation<Void, Never>?
    private var queryCountWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var queryCount = 0
    private var cancelledQueryCount = 0

    init(samples: [PingResult]) {
        inputs = samples.map(HistoryWeeklyDigestSample.init)
    }

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        queryCount += 1
        let readyWaiters = queryCountWaiters.filter { queryCount >= $0.minimum }
        queryCountWaiters.removeAll { queryCount >= $0.minimum }
        readyWaiters.forEach { $0.continuation.resume() }
        if queryCount == 1 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { firstQueryContinuation = $0 }
            } onCancel: {
                Task { await self.cancelFirstQuery() }
            }
        }
        return inputs
    }
    func historyRevision() async -> UInt64 {
        revisionCallCount += 1
        if revisionCallCount == 2 {
            await withCheckedContinuation { continuation in
                secondRevisionContinuation = continuation
                secondRevisionWaiters.forEach { $0.resume() }
                secondRevisionWaiters.removeAll()
            }
        }
        return 1
    }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func waitUntilQueryCount(atLeast minimum: Int) async {
        if queryCount >= minimum { return }
        await withCheckedContinuation { queryCountWaiters.append((minimum, $0)) }
    }

    func waitUntilSecondRevisionIsSuspended() async {
        if secondRevisionContinuation != nil { return }
        await withCheckedContinuation { secondRevisionWaiters.append($0) }
    }

    func resumeSecondRevision() {
        secondRevisionContinuation?.resume()
        secondRevisionContinuation = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(queryCount: queryCount, cancelledQueryCount: cancelledQueryCount)
    }

    private func cancelFirstQuery() {
        guard let continuation = firstQueryContinuation else { return }
        firstQueryContinuation = nil
        cancelledQueryCount += 1
        continuation.resume()
    }
}

private actor ManySuspendedWeeklyDigestStore: PingHistoryStore {
    struct Snapshot: Sendable {
        let queryCount: Int
        let activeQueryCount: Int
        let maxActiveQueryCount: Int
        let cancelledQueryCount: Int
    }

    private var queryCount = 0
    private var activeQueryCount = 0
    private var maxActiveQueryCount = 0
    private var cancelledQueryCount = 0
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var activeCountWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ result: PingResult) async {}
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample] {
        queryCount += 1
        activeQueryCount += 1
        maxActiveQueryCount = max(maxActiveQueryCount, activeQueryCount)
        let readyWaiters = countWaiters.filter { queryCount >= $0.minimum }
        countWaiters.removeAll { queryCount >= $0.minimum }
        readyWaiters.forEach { $0.continuation.resume() }
        if !released {
            await withCheckedContinuation { continuations.append($0) }
        }
        if Task.isCancelled {
            cancelledQueryCount += 1
        }
        activeQueryCount -= 1
        let readyActiveWaiters = activeCountWaiters.filter { activeQueryCount == $0.expected }
        activeCountWaiters.removeAll { activeQueryCount == $0.expected }
        readyActiveWaiters.forEach { $0.continuation.resume() }
        return []
    }
    func historyRevision() async -> UInt64 { 1 }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func waitUntilQueryCount(atLeast minimum: Int) async {
        if queryCount >= minimum { return }
        await withCheckedContinuation { countWaiters.append((minimum, $0)) }
    }

    func resumeAll() {
        released = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func waitUntilActiveQueryCount(_ expected: Int) async {
        if activeQueryCount == expected { return }
        await withCheckedContinuation { activeCountWaiters.append((expected, $0)) }
    }

    func snapshot() -> Snapshot {
        Snapshot(
            queryCount: queryCount,
            activeQueryCount: activeQueryCount,
            maxActiveQueryCount: maxActiveQueryCount,
            cancelledQueryCount: cancelledQueryCount
        )
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}

private func weeklySampleOrder(
    _ lhs: HistoryWeeklyDigestSample,
    _ rhs: HistoryWeeklyDigestSample
) -> Bool {
    if lhs.hostID != rhs.hostID { return lhs.hostID.uuidString < rhs.hostID.uuidString }
    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
    return lhs.id.uuidString < rhs.id.uuidString
}

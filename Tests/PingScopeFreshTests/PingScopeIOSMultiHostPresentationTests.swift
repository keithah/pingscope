import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeIOSMultiHostPresentationTests: XCTestCase {
    func testHostsTabKeepsNavigationControlsVisibleForReorderAndEditing() {
        XCTAssertFalse(PingScopeIOSRootTab.hosts.hidesNavigationBar)
        XCTAssertTrue(PingScopeIOSRootTab.monitor.hidesNavigationBar)
        XCTAssertTrue(PingScopeIOSRootTab.history.hidesNavigationBar)
    }

    func testReducerReturnsNoSamplesForEmptyInput() {
        XCTAssertEqual(PingScopeIOSLatencySampleReducer.reduce([], limit: 12), [])
    }

    func testReducerKeepsOneUsableSample() {
        let result = PingResult.success(hostID: UUID(), latency: .milliseconds(7))

        XCTAssertEqual(PingScopeIOSLatencySampleReducer.reduce([result], limit: 12), [result])
    }

    func testReducerKeepsFewerThanTwelveUsableSamplesInOrderAndExcludesFailures() {
        let hostID = UUID()
        let results = [
            PingResult.success(hostID: hostID, latency: .milliseconds(1)),
            PingResult.failure(hostID: hostID, reason: .timeout),
            PingResult.success(hostID: hostID, latency: .milliseconds(3)),
            PingResult.success(hostID: hostID, latency: .milliseconds(4))
        ]

        XCTAssertEqual(
            PingScopeIOSLatencySampleReducer.reduce(results, limit: 12).compactMap { $0.latency?.milliseconds },
            [1, 3, 4]
        )
    }

    func testReducerKeepsExactlyTwelveUsableSamples() {
        let results = makeSuccessfulResults(count: 12)

        XCTAssertEqual(PingScopeIOSLatencySampleReducer.reduce(results, limit: 12), results)
    }

    func testReducerKeepsEndpointsAndEvenlyRoundedInterior() {
        let results = makeSuccessfulResults(count: 25)
        let reduced = PingScopeIOSLatencySampleReducer.reduce(results, limit: 12)

        XCTAssertEqual(reduced.first?.latency?.milliseconds, 0)
        XCTAssertEqual(reduced.last?.latency?.milliseconds, 24)
        XCTAssertEqual(reduced.count, 12)
        XCTAssertEqual(reduced.map { Int($0.latency!.milliseconds) }, [0, 2, 4, 7, 9, 11, 13, 15, 17, 20, 22, 24])
    }

    func testEnabledHostsKeepSavedOrderAndActivityRowsCapAtThree() {
        let hosts = (0..<5).map { index in
            HostConfig(id: UUID(), displayName: "Host \(index)", address: "host-\(index).example", isEnabled: index != 1)
        }

        XCTAssertEqual(
            PingScopeIOSHostScopePresentation.enabledHosts(from: hosts).map(\.displayName),
            ["Host 0", "Host 2", "Host 3", "Host 4"]
        )
        XCTAssertEqual(
            PingScopeIOSHostScopePresentation.activityRows(from: hosts).map(\.hostID),
            [hosts[0].id, hosts[2].id, hosts[3].id]
        )
    }

    func testActivityRowsReduceSamplesOnPrebuiltRows() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1")
        let row = PingScopeIOSHostRowSnapshot(
            host: host,
            health: nil,
            samples: makeSuccessfulResults(count: 25, hostID: host.id),
            sampleLimit: 25
        )

        let activityRows = PingScopeIOSHostScopePresentation.activityRows(from: [row])

        XCTAssertEqual(activityRows.count, 1)
        XCTAssertEqual(activityRows[0].samples.count, 12)
        XCTAssertEqual(
            activityRows[0].samples.map { Int($0.latency!.milliseconds) },
            [0, 2, 4, 7, 9, 11, 13, 15, 17, 20, 22, 24]
        )
    }

    func testHostRowSnapshotMapsHealthSamplesAndStaleState() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1", method: .tcp)
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        let latest = PingResult.success(hostID: host.id, latency: .milliseconds(42.4))
        health.ingest(latest)
        let samples = makeSuccessfulResults(count: 13, hostID: host.id)

        let row = PingScopeIOSHostRowSnapshot(host: host, health: health, samples: samples, isStale: true)

        XCTAssertEqual(row.hostID, host.id)
        XCTAssertEqual(row.displayName, "Router")
        XCTAssertEqual(row.endpointCaption, "TCP 192.168.1.1")
        XCTAssertEqual(row.status, .healthy)
        XCTAssertEqual(row.latestLatencyMilliseconds ?? 0, 42.4, accuracy: 0.001)
        XCTAssertEqual(row.latencyText, "42ms")
        XCTAssertEqual(row.samples.count, 12)
        XCTAssertTrue(row.isStale)
    }

    func testHostRowSnapshotFormatsMissingLatencyAsPlaceholder() {
        let host = HostConfig(displayName: "No Data", address: "example.com")

        let row = PingScopeIOSHostRowSnapshot(host: host, health: nil)

        XCTAssertEqual(row.status, .noData)
        XCTAssertNil(row.latestLatencyMilliseconds)
        XCTAssertEqual(row.latencyText, "--ms")
        XCTAssertFalse(row.isStale)
    }

    func testActivityAggregateIgnoresStaleDownWhenFreshHostIsHealthy() {
        let rows = [
            makeStatusRow(status: .down, isStale: true),
            makeStatusRow(status: .healthy, isStale: false)
        ]

        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: rows), .healthy)
    }

    func testActivityAggregateIsNeutralWhenEveryHostIsStale() {
        let rows = [
            makeStatusRow(status: .down, isStale: true),
            makeStatusRow(status: .degraded, isStale: true)
        ]

        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: rows), .noData)
    }

    func testActivityAggregatePreservesFreshDegradedAndDownPriority() {
        XCTAssertEqual(
            PingScopeIOSHostScopePresentation.aggregateStatus(from: [
                makeStatusRow(status: .healthy, isStale: false),
                makeStatusRow(status: .degraded, isStale: false)
            ]),
            .degraded
        )
        XCTAssertEqual(
            PingScopeIOSHostScopePresentation.aggregateStatus(from: [
                makeStatusRow(status: .degraded, isStale: false),
                makeStatusRow(status: .down, isStale: false)
            ]),
            .down
        )
    }

    func testDisplayModeAlwaysUsesSignalForAllHosts() {
        XCTAssertEqual(PingScopeIOSDisplayMode.signal.resolvedForHostScope(showsAllHosts: false), .signal)
        XCTAssertEqual(PingScopeIOSDisplayMode.ring.resolvedForHostScope(showsAllHosts: false), .ring)
        XCTAssertEqual(PingScopeIOSDisplayMode.signal.resolvedForHostScope(showsAllHosts: true), .signal)
        XCTAssertEqual(PingScopeIOSDisplayMode.ring.resolvedForHostScope(showsAllHosts: true), .signal)
    }

    func testAllHostsMonitorPresentationKeepsSuppliedRowsAndSeriesInOrder() {
        let hosts = [
            HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1"),
            HostConfig(id: UUID(), displayName: "DNS", address: "1.1.1.1")
        ]
        let rows = hosts.map { PingScopeIOSHostRowSnapshot(host: $0, health: nil) }
        let series = hosts.map { host in
            PingScopeIOSHostGraphSeries(hostID: host.id, samples: [])
        }

        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rows(hostScope: .allHosts, allHostRows: rows).map(\.hostID),
            hosts.map(\.id)
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.graphSeries(hostScope: .allHosts, allHostGraphSeries: series).map(\.hostID),
            hosts.map(\.id)
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.displayMode(.ring, hostScope: .allHosts),
            .signal
        )
    }

    func testStablePaletteIndexStaysWithinBoundsForAdversarialAndRandomUUIDs() {
        let adversarialIDs = [
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            UUID(uuid: (127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127)),
            UUID(uuid: (255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255))
        ]
        let hostIDs = adversarialIDs + (0..<512).map { _ in UUID() }

        for paletteCount in [1, 2, 5, 6, 97] {
            for hostID in hostIDs {
                let index = PingScopeIOSAllHostsMonitorPresentation.stableColorIndex(
                    for: hostID,
                    paletteCount: paletteCount
                )
                XCTAssertGreaterThanOrEqual(index, 0)
                XCTAssertLessThan(index, paletteCount)
            }
        }
    }

    func testFocusedMonitorPresentationHidesAllHostContentAndKeepsSelectedDisplayMode() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1")
        let rows = [PingScopeIOSHostRowSnapshot(host: host, health: nil)]
        let series = [PingScopeIOSHostGraphSeries(hostID: host.id, samples: [])]

        XCTAssertTrue(
            PingScopeIOSAllHostsMonitorPresentation.rows(hostScope: .focused, allHostRows: rows).isEmpty
        )
        XCTAssertTrue(
            PingScopeIOSAllHostsMonitorPresentation.graphSeries(hostScope: .focused, allHostGraphSeries: series).isEmpty
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.displayMode(.ring, hostScope: .focused),
            .ring
        )
    }

    func testAllHostsMonitorPresentationUsesFullSeriesForCompactRowGraphs() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1")
        let fullSeries = makeSuccessfulResults(count: 3, hostID: host.id)
        let row = PingScopeIOSHostRowSnapshot(
            host: host,
            health: nil,
            samples: fullSeries,
            sampleLimit: 1
        )
        let graphSeries = [PingScopeIOSHostGraphSeries(hostID: host.id, samples: fullSeries)]

        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.graphSamples(for: row, allHostGraphSeries: graphSeries),
            fullSeries
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.graphSamples(for: row, allHostGraphSeries: []),
            row.samples
        )
    }

    func testAllHostsGraphRenderSeriesUseRefreshedEndDate() {
        let hostID = UUID()
        let refreshedEndDate = Date(timeIntervalSince1970: 1_000)
        let series = [PingScopeIOSHostGraphSeries(
            hostID: hostID,
            samples: [
                PingResult.success(hostID: hostID, latency: .milliseconds(20), timestamp: Date(timeIntervalSince1970: 939)),
                PingResult.success(hostID: hostID, latency: .milliseconds(30), timestamp: Date(timeIntervalSince1970: 940)),
                PingResult.success(hostID: hostID, latency: .milliseconds(40), timestamp: Date(timeIntervalSince1970: 1_000)),
                PingResult.success(hostID: hostID, latency: .milliseconds(50), timestamp: Date(timeIntervalSince1970: 1_001))
            ]
        )]

        let renderSeries = PingScopeIOSAllHostsMonitorPresentation.graphRenderSeries(
            from: series,
            range: .oneMinute,
            endDate: refreshedEndDate
        )

        XCTAssertEqual(renderSeries.count, 1)
        XCTAssertEqual(renderSeries[0].startDate, Date(timeIntervalSince1970: 940))
        XCTAssertEqual(renderSeries[0].endDate, refreshedEndDate)
        XCTAssertEqual(renderSeries[0].samples.map { $0.latency?.milliseconds }, [30, 40])
    }

    func testAllHostsStatisticsUseSharedSelectedRangeWindow() {
        let hostID = UUID()
        let endDate = Date(timeIntervalSince1970: 1_000)
        let series = [PingScopeIOSHostGraphSeries(
            hostID: hostID,
            samples: [
                PingResult.success(hostID: hostID, latency: .milliseconds(100), timestamp: Date(timeIntervalSince1970: 900)),
                PingResult.success(hostID: hostID, latency: .milliseconds(10), timestamp: Date(timeIntervalSince1970: 970)),
                PingResult.failure(hostID: hostID, reason: .timeout, timestamp: Date(timeIntervalSince1970: 980)),
                PingResult.success(hostID: hostID, latency: .milliseconds(1), timestamp: Date(timeIntervalSince1970: 1_001))
            ]
        )]

        let stats = PingScopeIOSAllHostsMonitorPresentation.statistics(
            for: series,
            range: .oneMinute,
            endDate: endDate
        )

        XCTAssertEqual(stats.transmitted, 2)
        XCTAssertEqual(stats.received, 1)
        XCTAssertEqual(stats.lossPercent, 50, accuracy: 0.001)
        XCTAssertEqual(stats.minimumMilliseconds, 10)
        XCTAssertEqual(stats.averageMilliseconds, 10)
        XCTAssertEqual(stats.maximumMilliseconds, 10)
    }

    func testAllHostsCombinedLatencyAveragesLatestUsableRowsIncludingGateway() {
        let dnsA = makeLatencyRow(milliseconds: 20)
        let dnsB = makeLatencyRow(milliseconds: 40)
        let gateway = makeLatencyRow(milliseconds: 3, tier: .localGateway)
        let stale = makeLatencyRow(milliseconds: 1_000, isStale: true)

        let combined = PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(
            from: [dnsA, dnsB, gateway, stale]
        )

        XCTAssertEqual(combined ?? 0, 21, accuracy: 0.001)
        XCTAssertTrue(gateway.isDefaultGateway)
        XCTAssertNil(PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(from: [stale]))
    }

    func testStaleRowPresentationShowsUnavailableWithoutDroppingGraphSamples() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1", method: .tcp)
        let samples = makeSuccessfulResults(count: 3, hostID: host.id)
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(samples[2])
        let row = PingScopeIOSHostRowSnapshot(host: host, health: health, samples: samples, isStale: true)
        let graphSeries = [PingScopeIOSHostGraphSeries(hostID: host.id, samples: samples)]

        let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row)

        XCTAssertEqual(presentation.displayStatus, .noData)
        XCTAssertEqual(presentation.latencyText, "--ms")
        XCTAssertEqual(presentation.accessibilityLabel, "Router, TCP 192.168.1.1, Stale, unavailable")
        XCTAssertEqual(presentation.focusAccessibilityHint, "Double-tap to focus Router.")
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.graphSamples(for: row, allHostGraphSeries: graphSeries),
            samples
        )
    }

    private func makeSuccessfulResults(count: Int, hostID: UUID = UUID()) -> [PingResult] {
        (0..<count).map { index in
            PingResult.success(
                hostID: hostID,
                latency: .milliseconds(Double(index)),
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
    }

    private func makeStatusRow(
        status: HealthStatus,
        isStale: Bool
    ) -> PingScopeIOSHostRowSnapshot {
        let host = HostConfig(displayName: "Host", address: "host.example")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.status = status
        return PingScopeIOSHostRowSnapshot(host: host, health: health, isStale: isStale)
    }

    private func makeLatencyRow(
        milliseconds: Double,
        tier: NetworkTier? = nil,
        isStale: Bool = false
    ) -> PingScopeIOSHostRowSnapshot {
        let host = HostConfig(displayName: "Host", address: "host.example", tier: tier)
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(milliseconds)))
        return PingScopeIOSHostRowSnapshot(host: host, health: health, isStale: isStale)
    }
}

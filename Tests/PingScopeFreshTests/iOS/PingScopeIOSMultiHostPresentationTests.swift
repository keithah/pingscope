import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeIOSMultiHostPresentationTests: XCTestCase {
    @MainActor
    func testGraphMemoInvalidatesWhenOnlyResolvedColorChanges() {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let firstColor = HostDisplayColor(red: 0.9, green: 0.1, blue: 0.2)
        let secondColor = HostDisplayColor(red: 0.1, green: 0.7, blue: 0.8)
        let firstHost = HostConfig(
            id: hostID,
            displayName: "Color edit",
            address: "192.0.2.51",
            displayColor: firstColor
        )
        let secondHost = HostConfig(
            id: hostID,
            displayName: "Color edit",
            address: "192.0.2.51",
            displayColor: secondColor
        )
        let memo = PingScopeIOSAllHostsGraphPresentationMemo()
        let endDate = Date(timeIntervalSince1970: 1_000)

        let first = memo.resolve(
            series: [PingScopeIOSHostGraphSeries(host: firstHost, samples: [])],
            range: .oneMinute,
            endDate: endDate
        )
        let second = memo.resolve(
            series: [PingScopeIOSHostGraphSeries(host: secondHost, samples: [])],
            range: .oneMinute,
            endDate: endDate
        )

        XCTAssertEqual(first.series[0].resolvedColor, .custom(firstColor))
        XCTAssertEqual(second.series[0].resolvedColor, .custom(secondColor))
    }

    @MainActor
    func testRingMemoInvalidatesWhenOnlyResolvedColorChanges() {
        let hostID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let firstColor = HostDisplayColor(red: 0.8, green: 0.2, blue: 0.3)
        let secondColor = HostDisplayColor(red: 0.2, green: 0.6, blue: 0.9)
        let firstHost = HostConfig(
            id: hostID,
            displayName: "Color edit",
            address: "192.0.2.52",
            displayColor: firstColor
        )
        let secondHost = HostConfig(
            id: hostID,
            displayName: "Color edit",
            address: "192.0.2.52",
            displayColor: secondColor
        )
        let memo = PingScopeIOSAllHostsConcentricRingContentMemo()

        let first = memo.resolve([PingScopeIOSHostRowSnapshot(host: firstHost, health: nil)])
        let second = memo.resolve([PingScopeIOSHostRowSnapshot(host: secondHost, health: nil)])

        XCTAssertEqual(first.rings[0].resolvedColor, .custom(firstColor))
        XCTAssertEqual(second.rings[0].resolvedColor, .custom(secondColor))
        XCTAssertEqual(second.legendRows[0].resolvedColor, .custom(secondColor))
    }

    func testCustomAndAutomaticIdentityColorsReachGraphRingAndRowPresentations() throws {
        let custom = HostDisplayColor(red: 0.95, green: 0.2, blue: 0.55)
        let customHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
            displayName: "Custom",
            displayColor: custom
        )
        let invalidHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            displayName: "Invalid",
            displayColor: HostDisplayColor(red: 1.2, green: 0.3, blue: 0.4)
        )
        let automaticHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000043")!,
            displayName: "Automatic",
            displayColor: nil
        )
        let hosts = [customHost, invalidHost, automaticHost]
        let focused = PingScopeIOSFocusedPeerPresentation(
            hosts: hosts,
            selectedHostID: customHost.id,
            selectedHealth: nil,
            samplesByHost: [:]
        )
        let graph = PingScopeIOSAllHostsMonitorPresentation.graphPresentation(
            from: focused.graphSeries,
            range: .oneMinute,
            endDate: Date(timeIntervalSince1970: 1_000)
        )
        let rings = PingScopeIOSAllHostsRingGridPresentation.cells(from: focused.rows)
        let rows = focused.rows.map {
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: $0)
        }

        XCTAssertEqual(graph.series[0].resolvedColor, .custom(custom))
        XCTAssertEqual(rings[0].resolvedColor, .custom(custom))
        XCTAssertEqual(rows[0].resolvedColor, .custom(custom))

        XCTAssertEqual(graph.series[1].resolvedColor, .automatic(.seaGreen))
        XCTAssertEqual(rings[1].resolvedColor, .automatic(.seaGreen))
        XCTAssertEqual(rows[1].resolvedColor, .automatic(.seaGreen))
        XCTAssertEqual(graph.series[2].resolvedColor, .automatic(.purple))
        XCTAssertEqual(rings[2].resolvedColor, .automatic(.purple))
        XCTAssertEqual(rows[2].resolvedColor, .automatic(.purple))
    }

    @MainActor
    func testPathMemoCacheHitSkipsProjectionBuild() {
        let memo = PingScopeIOSPathProjectionMemo<String, Int>()
        var projectionCount = 0

        let first = memo.resolve("router") {
            projectionCount += 1
            return 42
        }
        let second = memo.resolve("router") {
            projectionCount += 1
            return 99
        }

        XCTAssertEqual(first, 42)
        XCTAssertEqual(second, 42)
        XCTAssertEqual(projectionCount, 1)
    }

    @MainActor
    func testPathMemoKeepsNineHostPathsResident() {
        let memo = PingScopeIOSPathProjectionMemo<Int, Int>()
        var projectionCount = 0
        memo.prepare(forSeriesCount: 9)

        for hostIndex in 0..<9 {
            _ = memo.resolve(hostIndex) {
                projectionCount += 1
                return hostIndex
            }
        }
        for hostIndex in 0..<9 {
            XCTAssertEqual(
                memo.resolve(hostIndex) {
                    projectionCount += 1
                    return -1
                },
                hostIndex
            )
        }

        XCTAssertEqual(projectionCount, 9)
    }

    @MainActor
    func testPathMemoContractsAfterSeriesCountDrops() {
        let memo = PingScopeIOSPathProjectionMemo<Int, Int>()
        memo.prepare(forSeriesCount: 12)
        for index in 0..<12 {
            _ = memo.resolve(index) { index }
        }
        XCTAssertEqual(memo.count, 12)

        memo.prepare(forSeriesCount: 1)

        XCTAssertEqual(memo.count, 8)
    }

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

    func testAllHostsRingCellsPreserveEnabledHostOrderAndMapLatencyStatusAndProgress() {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 3)
        let router = HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1", thresholds: thresholds)
        let dns = HostConfig(id: UUID(), displayName: "DNS", address: "1.1.1.1", thresholds: thresholds)
        var routerHealth = HostHealth(hostID: router.id, thresholds: thresholds)
        routerHealth.ingest(.success(hostID: router.id, latency: .milliseconds(25.4)))
        var dnsHealth = HostHealth(hostID: dns.id, thresholds: thresholds)
        dnsHealth.ingest(.failure(hostID: dns.id, reason: .timeout))
        dnsHealth.ingest(.failure(hostID: dns.id, reason: .timeout))
        dnsHealth.ingest(.failure(hostID: dns.id, reason: .timeout))
        let rows = [
            PingScopeIOSHostRowSnapshot(host: router, health: routerHealth),
            PingScopeIOSHostRowSnapshot(host: dns, health: dnsHealth)
        ]

        let cells = PingScopeIOSAllHostsRingGridPresentation.cells(from: rows)

        XCTAssertEqual(cells.map(\.hostID), [router.id, dns.id])
        XCTAssertEqual(cells.map(\.displayName), ["Router", "DNS"])
        XCTAssertEqual(cells.map(\.latencyText), ["25ms", "--ms"])
        XCTAssertEqual(cells.map(\.status), [.healthy, .down])
        XCTAssertEqual(cells[0].ringProgress, 0.254, accuracy: 0.001)
        XCTAssertEqual(cells[1].ringProgress, 0)
    }

    func testAllHostsRingCellsMatchRowPresentationRules() {
        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 3)
        let unnamed = HostConfig(id: UUID(), displayName: "", address: "router.local", thresholds: thresholds)
        var health = HostHealth(hostID: unnamed.id, thresholds: thresholds)
        health.ingest(.success(hostID: unnamed.id, latency: .milliseconds(25.4)))
        let freshRow = PingScopeIOSHostRowSnapshot(host: unnamed, health: health)
        let staleRow = PingScopeIOSHostRowSnapshot(host: unnamed, health: health, isStale: true)

        let cells = PingScopeIOSAllHostsRingGridPresentation.cells(from: [freshRow, staleRow])
        let rowPresentations = [freshRow, staleRow].map {
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: $0)
        }

        XCTAssertEqual(cells.map(\.displayName), rowPresentations.map(\.displayName))
        XCTAssertEqual(cells.map(\.latencyText), rowPresentations.map(\.latencyText))
        XCTAssertEqual(cells.map(\.status), rowPresentations.map(\.displayStatus))
        XCTAssertEqual(cells.map(\.ringProgress), [0.254, 0])
    }

    func testAllHostsRingCellsAreEmptyWithoutEnabledRows() {
        XCTAssertEqual(PingScopeIOSAllHostsRingGridPresentation.cells(from: []), [])
    }

    func testAllHostsConcentricRingPresentationCapsSavedOrderAndBuildsColorKey() {
        let hosts = (0..<6).map { index in
            HostConfig(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", index + 1))!,
                displayName: "Host \(index + 1)",
                address: "192.0.2.\(index + 1)"
            )
        }
        let rows = hosts.enumerated().map { index, host in
            var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
            health.ingest(.success(hostID: host.id, latency: .milliseconds((index + 1) * 10)))
            return PingScopeIOSHostRowSnapshot(host: host, health: health)
        }

        let presentation = PingScopeIOSAllHostsConcentricRingPresentation(rows: rows)

        XCTAssertEqual(presentation.rings.map(\.hostID), Array(hosts.prefix(4).map(\.id)))
        XCTAssertEqual(presentation.legendRows.map(\.displayName), ["Host 1", "Host 2", "Host 3", "Host 4"])
        XCTAssertEqual(presentation.overflowCount, 2)
        XCTAssertEqual(presentation.overflowLabel, "+2 more")
        XCTAssertEqual(presentation.overflowAccessibilityLabel, "Show 2 more hosts")
        XCTAssertEqual(presentation.firstOverflowHostID, hosts[4].id)
        XCTAssertEqual(presentation.rings.map(\.resolvedColor), hosts.prefix(4).map {
            ResolvedHostDisplayColor(hostID: $0.id, displayColor: nil)
        })
        XCTAssertEqual(presentation.rings.map(\.ringIndex), [0, 1, 2, 3])
        XCTAssertEqual(presentation.legendRows.map(\.status), [.healthy, .healthy, .healthy, .healthy])
        XCTAssertEqual(presentation.legendRows.map(\.latencyText), ["10ms", "20ms", "30ms", "40ms"])
    }

    func testRingIdentityMatchesProductionGraphPreparedSeries() throws {
        let host = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            displayName: "Shared color",
            address: "1.1.1.1"
        )
        let rings = PingScopeIOSAllHostsConcentricRingPresentation(rows: [
            PingScopeIOSHostRowSnapshot(host: host, health: nil)
        ])
        let graph = PingScopeIOSAllHostsMonitorPresentation.graphPresentation(
            from: [PingScopeIOSHostGraphSeries(hostID: host.id, samples: [])],
            range: .oneMinute,
            endDate: Date(timeIntervalSince1970: 1_000)
        )
        let preparedSeries = try XCTUnwrap(graph.series.first)

        XCTAssertEqual(
            PingScopeIOSAllHostsConcentricRingPresentation.paletteCount,
            PingScopeIOSHostIdentityPalette.count
        )
        XCTAssertEqual(rings.rings[0].resolvedColor, preparedSeries.resolvedColor)
    }

    func testHostIdentityPaletteNormalizesAllIntegerIndexes() {
        let count = PingScopeIOSHostIdentityPalette.count

        XCTAssertEqual(PingScopeIOSHostIdentityPalette.color(at: -1), .bronze)
        XCTAssertEqual(PingScopeIOSHostIdentityPalette.color(at: count), .cobalt)
        XCTAssertEqual(PingScopeIOSHostIdentityPalette.color(at: count + 2), .teal)
        XCTAssertEqual(PingScopeIOSHostIdentityPalette.color(at: Int.min), .gold)
        XCTAssertEqual(PingScopeIOSHostIdentityPalette.color(at: Int.max), .purple)
    }

    func testHostIdentityPaletteUsesExactBoldUtilityComponents() {
        typealias RGB = PingScopeIOSHostIdentityPalette.RGB
        let expected: [(PingScopeIOSHostIdentityPalette.ColorToken, RGB, RGB)] = [
            (.cobalt, RGB(red: 0x00, green: 0x68, blue: 0xD9), RGB(red: 0x27, green: 0x8D, blue: 0xFF)),
            (.magenta, RGB(red: 0xD9, green: 0x1D, blue: 0x5B), RGB(red: 0xFF, green: 0x3D, blue: 0x7F)),
            (.teal, RGB(red: 0x00, green: 0x8C, blue: 0x78), RGB(red: 0x00, green: 0xD1, blue: 0xB2)),
            (.violet, RGB(red: 0x6D, green: 0x28, blue: 0xD9), RGB(red: 0x9B, green: 0x6C, blue: 0xFF)),
            (.gold, RGB(red: 0xB7, green: 0x79, blue: 0x00), RGB(red: 0xFF, green: 0xC4, blue: 0x00)),
            (.orange, RGB(red: 0xD9, green: 0x5F, blue: 0x00), RGB(red: 0xFF, green: 0x8A, blue: 0x00)),
            (.seaGreen, RGB(red: 0x00, green: 0x83, blue: 0x5D), RGB(red: 0x00, green: 0xC8, blue: 0x96)),
            (.purple, RGB(red: 0x8C, green: 0x22, blue: 0xC7), RGB(red: 0xC5, green: 0x4C, blue: 0xFF)),
            (.azure, RGB(red: 0x00, green: 0x77, blue: 0xB6), RGB(red: 0x00, green: 0xB8, blue: 0xF5)),
            (.crimson, RGB(red: 0xC9, green: 0x1E, blue: 0x3A), RGB(red: 0xFF, green: 0x45, blue: 0x60)),
            (.olive, RGB(red: 0x56, green: 0x8A, blue: 0x00), RGB(red: 0x8F, green: 0xD4, blue: 0x00)),
            (.bronze, RGB(red: 0xA8, green: 0x5D, blue: 0x00), RGB(red: 0xEF, green: 0xA3, blue: 0x3A))
        ]

        XCTAssertEqual(PingScopeIOSHostIdentityPalette.ColorToken.allCases, expected.map(\.0))
        XCTAssertEqual(expected.map { $0.0.lightRGB }, expected.map(\.1))
        XCTAssertEqual(expected.map { $0.0.darkRGB }, expected.map(\.2))
    }

    func testSharedHostIdentityPaletteUsesTwelveDeterministicBuckets() {
        let hostIDs = (1...256).compactMap { value in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", value))
        }

        let firstPass = hostIDs.map(PingScopeIOSHostIdentityPalette.color(for:))
        let secondPass = hostIDs.map(PingScopeIOSHostIdentityPalette.color(for:))

        XCTAssertEqual(PingScopeIOSHostIdentityPalette.count, 12)
        XCTAssertEqual(firstPass, secondPass)
        XCTAssertTrue(firstPass.contains { $0.rawValue >= 6 })
    }

    func testEveryHostIdentityTokenHasUniqueLightAndDarkComponents() {
        let tokens = PingScopeIOSHostIdentityPalette.ColorToken.allCases

        XCTAssertEqual(Set(tokens.map(\.lightRGB)).count, 12)
        XCTAssertEqual(Set(tokens.map(\.darkRGB)).count, 12)
        XCTAssertTrue(tokens.allSatisfy { $0.lightRGB != $0.darkRGB })
    }

    func testExpandedRingCellsStillMatchSharedGraphIdentityTokens() {
        let hosts = (1...12).compactMap { value -> HostConfig? in
            guard let id = UUID(
                uuidString: String(format: "10000000-0000-0000-0000-%012X", value)
            ) else { return nil }
            return HostConfig(id: id, displayName: "Host \(value)", address: "192.0.2.\(value)")
        }
        let rows = hosts.map { PingScopeIOSHostRowSnapshot(host: $0, health: nil) }
        let cells = PingScopeIOSAllHostsRingGridPresentation.cells(from: rows)

        XCTAssertEqual(
            cells.map(\.resolvedColor),
            hosts.map { ResolvedHostDisplayColor(hostID: $0.id, displayColor: nil) }
        )
    }

    func testAllHostsConcentricRingPresentationClampsProgressAndHandlesEmptyAndSingleHost() {
        XCTAssertEqual(PingScopeIOSAllHostsConcentricRingPresentation(rows: []).rings, [])
        XCTAssertEqual(PingScopeIOSAllHostsConcentricRingPresentation(rows: []).legendRows, [])
        XCTAssertEqual(PingScopeIOSAllHostsConcentricRingPresentation(rows: []).overflowCount, 0)

        let thresholds = LatencyThresholds(degradedMilliseconds: 100, downAfterFailures: 3)
        let host = HostConfig(displayName: "Only", address: "1.1.1.1", thresholds: thresholds)
        var highHealth = HostHealth(hostID: host.id, thresholds: thresholds)
        highHealth.ingest(.success(hostID: host.id, latency: .milliseconds(500)))
        let high = PingScopeIOSAllHostsConcentricRingPresentation(rows: [
            PingScopeIOSHostRowSnapshot(host: host, health: highHealth)
        ])
        XCTAssertEqual(high.rings.count, 1)
        XCTAssertEqual(high.rings[0].ringProgress, 1)

        let unavailable = PingScopeIOSAllHostsConcentricRingPresentation(rows: [
            PingScopeIOSHostRowSnapshot(host: host, health: nil)
        ])
        XCTAssertEqual(unavailable.rings[0].ringProgress, 0)
        XCTAssertEqual(unavailable.legendRows[0].status, .noData)
    }

    @MainActor
    func testAllHostsConcentricRingMemoBuildsIdenticalRowsOnlyOnce() {
        let host = HostConfig(id: UUID(), displayName: "Router", address: "192.168.1.1")
        let rows = [PingScopeIOSHostRowSnapshot(host: host, health: nil)]
        let memo = PingScopeIOSAllHostsConcentricRingContentMemo()
        var buildCount = 0

        let first = memo.resolve(rows) {
            buildCount += 1
            return PingScopeIOSAllHostsConcentricRingPresentation(rows: $0)
        }
        let second = memo.resolve(rows) {
            buildCount += 1
            return PingScopeIOSAllHostsConcentricRingPresentation(rows: $0)
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rings.map(\.hostID), [host.id])
        XCTAssertEqual(buildCount, 1)
    }

    func testAllHostsRingLatencyTextRejectsNonFiniteAndOversizedValues() {
        XCTAssertEqual(PingScopeIOSAllHostsRingGridPresentation.latencyText(for: .nan), "--ms")
        XCTAssertEqual(PingScopeIOSAllHostsRingGridPresentation.latencyText(for: .infinity), "--ms")
        XCTAssertEqual(PingScopeIOSAllHostsRingGridPresentation.latencyText(for: -.infinity), "--ms")
        XCTAssertEqual(PingScopeIOSAllHostsRingGridPresentation.latencyText(for: .greatestFiniteMagnitude), "--ms")
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

    func testFocusedMonitorPresentationKeepsOtherHostLatencyAndGraphSnapshotsAvailable() {
        let host = HostConfig(displayName: "Router", address: "192.168.1.1")
        let samples = makeSuccessfulResults(count: 3, hostID: host.id)
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(18)))
        let rows = [PingScopeIOSHostRowSnapshot(host: host, health: health, samples: samples)]
        let series = [PingScopeIOSHostGraphSeries(hostID: host.id, samples: samples)]

        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rows(hostScope: .focused, allHostRows: rows),
            rows
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.graphSeries(hostScope: .focused, allHostGraphSeries: series),
            series
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: rows[0]).latencyText,
            "18ms"
        )
    }

    func testRecentHistoryBuildsLatencyAndGraphRowsForEveryEnabledHost() {
        let hosts = [
            HostConfig(displayName: "Cloudflare", address: "1.1.1.1"),
            HostConfig(displayName: "Google", address: "8.8.8.8"),
            HostConfig(displayName: "Gateway", address: "192.168.1.1")
        ]
        var healthByHost: [UUID: HostHealth] = [:]
        var samplesByHost: [UUID: [PingResult]] = [:]

        for (index, host) in hosts.enumerated() {
            let result = PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double((index + 1) * 10))
            )
            var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
            health.ingest(result)
            healthByHost[host.id] = health
            samplesByHost[host.id] = [result]
        }

        let rows = PingScopeIOSHostScopePresentation.rows(
            from: hosts,
            healthByHost: healthByHost,
            samplesByHost: samplesByHost
        )

        XCTAssertEqual(rows.map(\.hostID), hosts.map(\.id))
        XCTAssertEqual(rows.map(\.latencyText), ["10ms", "20ms", "30ms"])
        XCTAssertEqual(rows.map(\.samples.count), [1, 1, 1])
    }

    func testRecentHistoricalPeerIsCachedButSelectedHostStaysLiveAndPeerKeepsLastKnownLatencyGraph() throws {
        let selectedHost = HostConfig(displayName: "Selected", address: "1.1.1.1")
        let peerHost = HostConfig(displayName: "Peer", address: "8.8.8.8", method: .tcp)
        let selectedResult = PingResult.success(
            hostID: selectedHost.id,
            latency: .milliseconds(12),
            timestamp: Date(timeIntervalSince1970: 10_000)
        )
        let peerSamples = [
            PingResult.success(
                hostID: peerHost.id,
                latency: .milliseconds(31),
                timestamp: Date(timeIntervalSince1970: 9_980)
            ),
            PingResult.success(
                hostID: peerHost.id,
                latency: .milliseconds(34),
                timestamp: Date(timeIntervalSince1970: 9_990)
            ),
            PingResult.failure(hostID: peerHost.id, reason: .timeout, timestamp: Date(timeIntervalSince1970: 9_995)),
            PingResult.failure(hostID: peerHost.id, reason: .timeout, timestamp: Date(timeIntervalSince1970: 9_996)),
            PingResult.failure(hostID: peerHost.id, reason: .timeout, timestamp: Date(timeIntervalSince1970: 9_997))
        ]
        var selectedHealth = HostHealth(hostID: selectedHost.id, thresholds: selectedHost.thresholds)
        selectedHealth.ingest(selectedResult)
        var peerHistoricalHealth = HostHealth(hostID: peerHost.id, thresholds: peerHost.thresholds)
        peerSamples.forEach { peerHistoricalHealth.ingest($0) }

        let focusedPresentation = PingScopeIOSFocusedPeerPresentation(
            hosts: [selectedHost, peerHost],
            selectedHostID: selectedHost.id,
            selectedHealth: selectedHealth,
            samplesByHost: [selectedHost.id: [selectedResult], peerHost.id: peerSamples]
        )
        let rows = focusedPresentation.rows
        let selectedRow = try XCTUnwrap(rows.first { $0.hostID == selectedHost.id })
        let peerRow = try XCTUnwrap(rows.first { $0.hostID == peerHost.id })
        let peerPresentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: peerRow)
        let graphSamples = PingScopeIOSAllHostsMonitorPresentation.graphSamples(
            for: peerRow,
            allHostGraphSeries: focusedPresentation.graphSeries
        )

        XCTAssertFalse(selectedRow.isCached)
        XCTAssertFalse(selectedRow.isStale)
        XCTAssertTrue(peerRow.isCached)
        XCTAssertFalse(peerRow.isStale)
        XCTAssertEqual(peerHistoricalHealth.status, .down)
        XCTAssertEqual(peerRow.status, .noData)
        XCTAssertEqual(peerPresentation.displayStatus, .noData)
        XCTAssertEqual(peerPresentation.latencyText, "34ms")
        XCTAssertEqual(peerPresentation.cacheLabel, "Cached")
        XCTAssertEqual(
            peerPresentation.accessibilityLabel,
            "Peer, TCP 8.8.8.8, Cached data, 34 milliseconds"
        )
        XCTAssertEqual(graphSamples.compactMap { $0.latency?.milliseconds }, [31, 34])
        XCTAssertGreaterThan(peerRow.samples.count, 1, "The cached mini-graph must remain visible.")
        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: rows), .healthy)
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(from: rows),
            12
        )
    }

    func testFocusedPeerPresentationKeepsSavedOrderAndLiveCachedUnavailableTelemetry() throws {
        let selectedHost = HostConfig(
            displayName: "Zulu",
            address: "selected.example",
            displayColor: HostDisplayColor(red: 0.9, green: 0.2, blue: 0.1)
        )
        let cachedPeer = HostConfig(
            displayName: "Alpha",
            address: "cached.example",
            displayColor: HostDisplayColor(red: 0.1, green: 0.7, blue: 0.8)
        )
        let emptyPeer = HostConfig(displayName: "Middle", address: "empty.example")
        let selectedSample = PingResult.success(
            hostID: selectedHost.id,
            latency: .milliseconds(12),
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let cachedSamples = [
            PingResult.success(
                hostID: cachedPeer.id,
                latency: .milliseconds(31),
                timestamp: Date(timeIntervalSince1970: 990)
            ),
            PingResult.success(
                hostID: cachedPeer.id,
                latency: .milliseconds(34),
                timestamp: Date(timeIntervalSince1970: 995)
            )
        ]
        var selectedHealth = HostHealth(hostID: selectedHost.id, thresholds: selectedHost.thresholds)
        selectedHealth.ingest(selectedSample)

        let focusedPresentation = PingScopeIOSFocusedPeerPresentation(
            hosts: [selectedHost, cachedPeer, emptyPeer],
            selectedHostID: selectedHost.id,
            selectedHealth: selectedHealth,
            samplesByHost: [
                selectedHost.id: [selectedSample],
                cachedPeer.id: cachedSamples,
                emptyPeer.id: []
            ]
        )
        let rowPresentations = focusedPresentation.rows.map {
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: $0, action: .focus)
        }
        let graph = PingScopeIOSAllHostsMonitorPresentation.graphPresentation(
            from: focusedPresentation.graphSeries,
            range: .oneMinute,
            endDate: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(focusedPresentation.rows.map(\.hostID), [selectedHost.id, cachedPeer.id, emptyPeer.id])
        XCTAssertEqual(rowPresentations.map(\.latencyText), ["12ms", "34ms", "--ms"])
        XCTAssertEqual(rowPresentations.map(\.cacheLabel), [nil, "Cached", nil])
        XCTAssertEqual(
            rowPresentations.map(\.resolvedColor),
            [
                .custom(HostDisplayColor(red: 0.9, green: 0.2, blue: 0.1)),
                .custom(HostDisplayColor(red: 0.1, green: 0.7, blue: 0.8)),
                ResolvedHostDisplayColor(hostID: emptyPeer.id, displayColor: nil)
            ]
        )
        XCTAssertEqual(graph.series.map(\.hostID), [selectedHost.id, cachedPeer.id, emptyPeer.id])
        XCTAssertEqual(
            graph.graphData(for: cachedPeer.id)?.points.map(\.latencyMilliseconds),
            [31, 34]
        )
        XCTAssertTrue(graph.graphData(for: emptyPeer.id)?.points.isEmpty ?? false)
    }

    func testSwitchHostPresentationDrivesAllHostsAndSavedConcreteTelemetryRows() throws {
        let selectedHost = HostConfig(
            displayName: "Zulu",
            address: "selected.example",
            displayColor: HostDisplayColor(red: 0.9, green: 0.2, blue: 0.1)
        )
        let cachedPeer = HostConfig(displayName: "Alpha", address: "cached.example")
        let emptyPeer = HostConfig(
            displayName: "Middle",
            address: "empty.example",
            displayColor: HostDisplayColor(red: 0.1, green: 0.7, blue: 0.8)
        )
        let selectedSample = PingResult.success(
            hostID: selectedHost.id,
            latency: .milliseconds(12),
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let cachedSamples = [
            PingResult.success(
                hostID: cachedPeer.id,
                latency: .milliseconds(31),
                timestamp: Date(timeIntervalSince1970: 990)
            ),
            PingResult.success(
                hostID: cachedPeer.id,
                latency: .milliseconds(34),
                timestamp: Date(timeIntervalSince1970: 995)
            )
        ]
        var selectedHealth = HostHealth(hostID: selectedHost.id, thresholds: selectedHost.thresholds)
        selectedHealth.ingest(selectedSample)
        let peerPresentation = PingScopeIOSFocusedPeerPresentation(
            hosts: [selectedHost, cachedPeer, emptyPeer],
            selectedHostID: selectedHost.id,
            selectedHealth: selectedHealth,
            samplesByHost: [
                selectedHost.id: [selectedSample],
                cachedPeer.id: cachedSamples,
                emptyPeer.id: []
            ]
        )

        let switcher = PingScopeIOSSwitchHostPresentation(
            hosts: [selectedHost, cachedPeer, emptyPeer],
            hostScope: .focused,
            selectedHostID: selectedHost.id,
            selectedHealth: selectedHealth,
            selectedSamples: [selectedSample],
            allHostRows: peerPresentation.rows,
            allHostGraphSeries: peerPresentation.graphSeries
        )
        let concreteItems = switcher.items.compactMap { item -> PingScopeIOSSwitchHostConcreteItem? in
            guard case .host(let concreteItem) = item else { return nil }
            return concreteItem
        }

        guard case .allHosts(let allHostsSelected) = switcher.items.first else {
            return XCTFail("All Hosts must be first.")
        }
        XCTAssertFalse(allHostsSelected)
        XCTAssertEqual(concreteItems.map(\.hostID), [selectedHost.id, cachedPeer.id, emptyPeer.id])
        XCTAssertEqual(concreteItems.filter(\.isSelected).map(\.hostID), [selectedHost.id])
        XCTAssertEqual(concreteItems.map(\.action), [.focus, .focus, .focus])
        XCTAssertEqual(concreteItems.map(\.rowPresentation.latencyText), ["12ms", "34ms", "--ms"])
        XCTAssertEqual(concreteItems.map(\.rowPresentation.cacheLabel), [nil, "Cached", nil])
        XCTAssertEqual(
            concreteItems.map(\.resolvedColor),
            [
                .custom(HostDisplayColor(red: 0.9, green: 0.2, blue: 0.1)),
                ResolvedHostDisplayColor(hostID: cachedPeer.id, displayColor: nil),
                .custom(HostDisplayColor(red: 0.1, green: 0.7, blue: 0.8))
            ]
        )
        XCTAssertEqual(concreteItems.map { $0.graphSamples.compactMap { $0.latency?.milliseconds } }, [[12], [31, 34], []])
        XCTAssertTrue(concreteItems.allSatisfy { item in
            item.graphSamples.allSatisfy { $0.hostID == item.hostID }
        })
    }

    func testFocusedPeerTransitionNeutralizesNewSelectionAndCachesOnlyPeersWithRetainedSamples() throws {
        let hostA = HostConfig(displayName: "Host A", address: "a.example")
        let hostB = HostConfig(displayName: "Host B", address: "b.example")
        let emptyPeer = HostConfig(displayName: "Empty", address: "empty.example")
        let hostASamples = [
            PingResult.success(hostID: hostA.id, latency: .milliseconds(14), timestamp: Date(timeIntervalSince1970: 1)),
            PingResult.success(hostID: hostA.id, latency: .milliseconds(18), timestamp: Date(timeIntervalSince1970: 2))
        ]
        let latestOutgoingSample = PingResult.success(
            hostID: hostA.id,
            latency: .milliseconds(31),
            timestamp: Date(timeIntervalSince1970: 3)
        )
        let staleSelectedSamples = [
            PingResult.success(hostID: hostB.id, latency: .milliseconds(99), timestamp: Date(timeIntervalSince1970: 1))
        ]

        let presentation = PingScopeIOSFocusedPeerPresentation.transitioning(
            to: hostB.id,
            from: [hostA, hostB, emptyPeer],
            outgoingHostID: hostA.id,
            outgoingSamples: [hostASamples[1], latestOutgoingSample],
            previousGraphSeries: [
                PingScopeIOSHostGraphSeries(hostID: hostA.id, samples: hostASamples),
                PingScopeIOSHostGraphSeries(hostID: hostB.id, samples: staleSelectedSamples)
            ]
        )
        let rowA = try XCTUnwrap(presentation.rows.first { $0.hostID == hostA.id })
        let rowB = try XCTUnwrap(presentation.rows.first { $0.hostID == hostB.id })
        let emptyRow = try XCTUnwrap(presentation.rows.first { $0.hostID == emptyPeer.id })

        XCTAssertTrue(rowA.isCached)
        XCTAssertEqual(rowA.latencyText, "31ms")
        XCTAssertEqual(rowA.samples.map(\.id), [hostASamples[0].id, hostASamples[1].id, latestOutgoingSample.id])
        XCTAssertFalse(rowB.isCached)
        XCTAssertEqual(rowB.latencyText, "--ms")
        XCTAssertTrue(rowB.samples.isEmpty)
        XCTAssertFalse(emptyRow.isCached)
        XCTAssertNil(PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: emptyRow).cacheLabel)
        XCTAssertEqual(
            presentation.graphSeries.first { $0.hostID == hostB.id }?.samples,
            []
        )
        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: presentation.rows), .noData)
        XCTAssertNil(PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(from: presentation.rows))
    }

    func testFocusedPeerTransitionAndNilStoreRebuildRetainOutgoingLiveSamplesWhenGraphIsEmpty() throws {
        let hostA = HostConfig(displayName: "Host A", address: "a.example")
        let hostB = HostConfig(displayName: "Host B", address: "b.example")
        let outgoingSamples = [
            PingResult.success(hostID: hostA.id, latency: .milliseconds(23), timestamp: Date(timeIntervalSince1970: 1)),
            PingResult.success(hostID: hostA.id, latency: .milliseconds(37), timestamp: Date(timeIntervalSince1970: 2))
        ]

        let transitioned = PingScopeIOSFocusedPeerPresentation.transitioning(
            to: hostB.id,
            from: [hostA, hostB],
            outgoingHostID: hostA.id,
            outgoingSamples: outgoingSamples,
            previousGraphSeries: []
        )
        var nilStoreSamplesByHost = Dictionary(uniqueKeysWithValues: transitioned.graphSeries.map {
            ($0.hostID, $0.samples)
        })
        nilStoreSamplesByHost[hostB.id] = []
        let rebuilt = PingScopeIOSFocusedPeerPresentation(
            hosts: [hostA, hostB],
            selectedHostID: hostB.id,
            selectedHealth: nil,
            samplesByHost: nilStoreSamplesByHost
        )
        let outgoingRow = try XCTUnwrap(rebuilt.rows.first { $0.hostID == hostA.id })
        let incomingRow = try XCTUnwrap(rebuilt.rows.first { $0.hostID == hostB.id })

        XCTAssertTrue(outgoingRow.isCached)
        XCTAssertEqual(outgoingRow.latencyText, "37ms")
        XCTAssertEqual(outgoingRow.samples.map(\.id), outgoingSamples.map(\.id))
        XCTAssertEqual(
            rebuilt.graphSeries.first { $0.hostID == hostA.id }?.samples.map(\.id),
            outgoingSamples.map(\.id)
        )
        XCTAssertFalse(incomingRow.isCached)
        XCTAssertEqual(incomingRow.latencyText, "--ms")
        XCTAssertTrue(incomingRow.samples.isEmpty)
    }

    func testFocusedPeerPresentationWithoutHistoryKeepsSelectedLiveAndEmptyPeerNeutral() throws {
        let selectedHost = HostConfig(displayName: "Selected", address: "selected.example")
        let emptyPeer = HostConfig(displayName: "No history", address: "empty.example")
        let selectedSample = PingResult.success(hostID: selectedHost.id, latency: .milliseconds(27))
        var selectedHealth = HostHealth(hostID: selectedHost.id, thresholds: selectedHost.thresholds)
        selectedHealth.ingest(selectedSample)

        let presentation = PingScopeIOSFocusedPeerPresentation(
            hosts: [selectedHost, emptyPeer],
            selectedHostID: selectedHost.id,
            selectedHealth: selectedHealth,
            samplesByHost: [selectedHost.id: [selectedSample], emptyPeer.id: []]
        )
        let selectedRow = try XCTUnwrap(presentation.rows.first { $0.hostID == selectedHost.id })
        let emptyRow = try XCTUnwrap(presentation.rows.first { $0.hostID == emptyPeer.id })

        XCTAssertFalse(selectedRow.isCached)
        XCTAssertEqual(selectedRow.latencyText, "27ms")
        XCTAssertFalse(emptyRow.isCached)
        XCTAssertEqual(emptyRow.latencyText, "--ms")
        XCTAssertNil(PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: emptyRow).cacheLabel)
        XCTAssertEqual(
            presentation.graphSeries.first { $0.hostID == emptyPeer.id }?.samples,
            []
        )
    }

    func testHostRowActionAccessibilityHintMatchesFocusAndEditBehavior() {
        let host = HostConfig(displayName: "Router", address: "router.example")
        let row = PingScopeIOSHostRowSnapshot(host: host, health: nil)

        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row, action: .focus).actionAccessibilityHint,
            "Double-tap to focus Router."
        )
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row, action: .edit).actionAccessibilityHint,
            "Double-tap to edit Router."
        )
    }

    func testFocusedHistoricalFailureIsCachedUnavailableAndDoesNotBecomeLiveHealth() throws {
        let selectedHost = HostConfig(displayName: "Selected", address: "selected.example")
        let peerHost = HostConfig(displayName: "Failed peer", address: "203.0.113.8")
        let failures = (0..<3).map { index in
            PingResult.failure(
                hostID: peerHost.id,
                reason: .timeout,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }
        var peerHistoricalHealth = HostHealth(hostID: peerHost.id, thresholds: peerHost.thresholds)
        failures.forEach { peerHistoricalHealth.ingest($0) }

        let focusedPresentation = PingScopeIOSFocusedPeerPresentation(
            hosts: [selectedHost, peerHost],
            selectedHostID: selectedHost.id,
            selectedHealth: nil,
            samplesByHost: [peerHost.id: failures]
        )
        let row = try XCTUnwrap(focusedPresentation.rows.first { $0.hostID == peerHost.id })
        let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row)

        XCTAssertTrue(row.isCached)
        XCTAssertFalse(row.isStale)
        XCTAssertEqual(peerHistoricalHealth.status, .down)
        XCTAssertEqual(row.status, .noData)
        XCTAssertEqual(presentation.displayStatus, .noData)
        XCTAssertEqual(presentation.latencyText, "--ms")
        XCTAssertEqual(presentation.cacheLabel, "Cached")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Failed peer, TCP 203.0.113.8, Cached data, unavailable"
        )
        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: [row]), .noData)
        XCTAssertNil(PingScopeIOSAllHostsMonitorPresentation.combinedLatencyMilliseconds(from: [row]))
    }

    func testActiveAllHostsRowsRemainLiveWhenCacheStateIsNotRequested() {
        let host = HostConfig(displayName: "Live host", address: "192.0.2.10")
        var health = HostHealth(hostID: host.id, thresholds: host.thresholds)
        health.ingest(.success(hostID: host.id, latency: .milliseconds(22)))

        let rows = PingScopeIOSHostScopePresentation.rows(
            from: [host],
            healthByHost: [host.id: health]
        )

        XCTAssertEqual(rows.map(\.isCached), [false])
        XCTAssertEqual(PingScopeIOSHostScopePresentation.aggregateStatus(from: rows), .healthy)
        XCTAssertEqual(
            PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: rows[0]).cacheLabel,
            nil
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

    func testAllHostsGraphPresentationPreparesPerHostDataAndStatisticsForSharedWindow() throws {
        let firstHostID = UUID()
        let secondHostID = UUID()
        let endDate = Date(timeIntervalSince1970: 1_000)
        let series = [
            PingScopeIOSHostGraphSeries(hostID: firstHostID, samples: [
                PingResult.success(hostID: firstHostID, latency: .milliseconds(99), timestamp: Date(timeIntervalSince1970: 939)),
                PingResult.success(hostID: firstHostID, latency: .milliseconds(10), timestamp: Date(timeIntervalSince1970: 940)),
            ]),
            PingScopeIOSHostGraphSeries(hostID: secondHostID, samples: [
                PingResult.failure(hostID: secondHostID, reason: .timeout, timestamp: Date(timeIntervalSince1970: 980)),
                PingResult.success(hostID: secondHostID, latency: .milliseconds(30), timestamp: endDate),
            ]),
        ]

        let presentation = PingScopeIOSAllHostsMonitorPresentation.graphPresentation(
            from: series,
            range: .oneMinute,
            endDate: endDate
        )

        XCTAssertEqual(presentation.series.map(\.hostID), [firstHostID, secondHostID])
        XCTAssertEqual(
            try XCTUnwrap(presentation.graphData(for: firstHostID)).points.map(\.latencyMilliseconds),
            [10]
        )
        XCTAssertEqual(
            try XCTUnwrap(presentation.graphData(for: secondHostID)).points.map(\.latencyMilliseconds),
            [30]
        )
        XCTAssertEqual(presentation.statistics.transmitted, 3)
        XCTAssertEqual(presentation.statistics.received, 2)
        XCTAssertEqual(presentation.statistics.lossPercent, 100.0 / 3.0, accuracy: 0.001)
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
        XCTAssertEqual(presentation.actionAccessibilityHint, "Double-tap to focus Router.")
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

    private func decodedHost(
        id: UUID,
        displayName: String,
        displayColor: HostDisplayColor?
    ) throws -> HostConfig {
        let encoded = try JSONEncoder().encode(HostConfig(
            id: id,
            displayName: displayName,
            address: "192.0.2.1",
            displayColor: displayColor
        ))
        return try JSONDecoder().decode(HostConfig.self, from: encoded)
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

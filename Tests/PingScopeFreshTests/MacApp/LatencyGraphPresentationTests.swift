import XCTest
@testable import PingScope
@testable import PingScopeCore

final class LatencyGraphPresentationTests: XCTestCase {
    func testFocusedMacGraphAndRingUseCustomAndAutomaticIdentityColorsInBothAppearances() {
        let hosts = [
            HostConfig(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
                displayName: "Custom",
                address: "custom.example",
                displayColor: HostDisplayColor(red: 0.21, green: 0.43, blue: 0.76)
            ),
            HostConfig(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
                displayName: "Automatic",
                address: "automatic.example"
            ),
        ]

        for host in hosts {
            let presentation = PingScopeDisplayPresentation(
                snapshot: RuntimeSnapshot(hosts: [host], primaryHostID: host.id, healthByHost: [:], samplesByHost: [:]),
                selectedRange: .oneMinute,
                visibleHistorySamples: [],
                includesAllHosts: false,
                presenter: DisplayStatePresenter(),
                now: Date(timeIntervalSince1970: 1_000)
            )
            let expected = ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)

            XCTAssertEqual(presentation.focusedIdentityColor, expected)
            XCTAssertEqual(presentation.focusedGraphColor, expected)
            XCTAssertEqual(presentation.focusedRingColor, expected)
            for appearance in [HostDisplayColorAppearance.light, .dark] {
                XCTAssertEqual(presentation.focusedGraphColor?.components(for: appearance), expected.components(for: appearance))
                XCTAssertEqual(presentation.focusedRingColor?.components(for: appearance), expected.components(for: appearance))
            }
        }
    }

    func testGraphCardSurfaceColorsMatchLegacyDarkAppearanceAndAreDistinctInLight() {
        // Dark values must match the previous hardcoded literals (Color.black and
        // #111827) so dark mode is visually unchanged by the light-mode fix.
        let darkTop = PingScopeSurfaceColors.graphCardTop.components(for: .dark)
        XCTAssertEqual(darkTop.red, 0, accuracy: 0.001)
        XCTAssertEqual(darkTop.green, 0, accuracy: 0.001)
        XCTAssertEqual(darkTop.blue, 0, accuracy: 0.001)

        let darkBottom = PingScopeSurfaceColors.graphCardBottom.components(for: .dark)
        XCTAssertEqual(darkBottom.red, 17.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(darkBottom.green, 24.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(darkBottom.blue, 39.0 / 255.0, accuracy: 0.01)

        // Light values must actually be light (not another dark shade), so the
        // card reads as a light surface under the system light appearance.
        let lightTop = PingScopeSurfaceColors.graphCardTop.components(for: .light)
        let lightBottom = PingScopeSurfaceColors.graphCardBottom.components(for: .light)
        for component in [lightTop.red, lightTop.green, lightTop.blue, lightBottom.red, lightBottom.green, lightBottom.blue] {
            XCTAssertGreaterThan(component, 0.85)
        }

        XCTAssertNotEqual(darkTop, lightTop)
        XCTAssertNotEqual(darkBottom, lightBottom)
    }

    @MainActor
    func testDisabledCustomColorReachesAllHostStatusRowWithoutGraphSeries() {
        let custom = HostDisplayColor(red: 0.75, green: 0.15, blue: 0.65)
        let host = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            displayName: "Disabled custom",
            address: "192.0.2.61",
            isEnabled: false,
            displayColor: custom
        )
        let snapshot = RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [:],
            samplesByHost: [:]
        )
        let presentation = PingScopeDisplayPresentation(
            snapshot: snapshot,
            selectedRange: .oneMinute,
            visibleHistorySamples: [],
            includesAllHosts: true,
            presenter: DisplayStatePresenter(),
            now: Date(timeIntervalSince1970: 1_000)
        )
        let summary = presentation.hostStatusSummaries[0]
        let row = AllHostStatusRow(summary: summary, graphSeries: nil)

        XCTAssertTrue(presentation.allHostGraphSeries.isEmpty)
        XCTAssertEqual(summary.resolvedColor, .custom(custom))
        XCTAssertEqual(row.resolvedColor, .custom(custom))
    }

    func testAllHostGraphSeriesResolveDecodedCustomAndAutomaticColors() throws {
        let custom = HostDisplayColor(red: 0.95, green: 0.2, blue: 0.55)
        let customHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!,
            displayName: "Custom",
            displayColor: custom
        )
        let invalidHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!,
            displayName: "Invalid",
            displayColor: HostDisplayColor(red: -0.1, green: 0.3, blue: 0.4)
        )
        let automaticHost = try decodedHost(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000043")!,
            displayName: "Automatic",
            displayColor: nil
        )
        let hosts = [customHost, invalidHost, automaticHost]
        let snapshot = RuntimeSnapshot(
            hosts: hosts,
            primaryHostID: customHost.id,
            healthByHost: [:],
            samplesByHost: [:]
        )

        let preparation = PingScopeDisplayPreparation(
            snapshot: snapshot,
            selectedRange: .oneMinute,
            visibleHistorySamples: [],
            includesAllHosts: true,
            presenter: DisplayStatePresenter(),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(preparation.allHostGraphSeries[0].resolvedColor, .custom(custom))
        XCTAssertEqual(preparation.allHostGraphSeries[1].resolvedColor, .automatic(.seaGreen))
        XCTAssertEqual(preparation.allHostGraphSeries[2].resolvedColor, .automatic(.purple))
    }

    func testLatencyGraphDataCachesRenderPointsByPixelWidth() {
        let data = LatencyGraphData(samples: makeSamples(count: 200))

        _ = data.renderPoints(pixelWidth: 30)
        XCTAssertEqual(data.renderPointCacheEntryCount, 1)

        _ = data.renderPoints(pixelWidth: 30)
        XCTAssertEqual(data.renderPointCacheEntryCount, 1)

        _ = data.renderPoints(pixelWidth: 31)
        XCTAssertEqual(data.renderPointCacheEntryCount, 2)
    }

    func testLatencyGraphDataEvictsOldRenderPointWidths() {
        let data = LatencyGraphData(samples: makeSamples(count: 200))

        for width in [20, 21, 22, 23, 24, 25] {
            _ = data.renderPoints(pixelWidth: CGFloat(width))
        }

        XCTAssertEqual(data.renderPointCacheEntryCount, 4)
        XCTAssertEqual(data.renderPointCacheKeys, [22, 23, 24, 25])
    }

    func testLatencyGraphDataEvictsLeastRecentlyUsedRenderPointWidth() {
        let data = LatencyGraphData(samples: makeSamples(count: 200))

        for width in [20, 21, 22, 23] {
            _ = data.renderPoints(pixelWidth: CGFloat(width))
        }
        _ = data.renderPoints(pixelWidth: 20)
        _ = data.renderPoints(pixelWidth: 24)

        XCTAssertEqual(data.renderPointCacheKeys, [20, 22, 23, 24])
    }

    func testDrawableHostSeriesCachesRenderPointsByPixelWidth() throws {
        let host = HostConfig(displayName: "Gateway", address: "192.168.1.1")
        let source = HostLatencyGraphSeries(host: host, samples: makeSamples(count: 200), isPrimary: true)
        let graphData = MultiHostLatencyGraphData(series: [source])
        let series = try XCTUnwrap(graphData.drawableSeries.first)

        _ = series.renderPoints(pixelWidth: 24)
        XCTAssertEqual(series.renderPointCacheEntryCount, 1)

        _ = series.renderPoints(pixelWidth: 24)
        XCTAssertEqual(series.renderPointCacheEntryCount, 1)
    }

    private func makeSamples(count: Int) -> [PingResult] {
        (0..<count).map { index in
            PingResult.success(
                hostID: UUID(),
                latency: .milliseconds(Double(index % 80) + 1),
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
}

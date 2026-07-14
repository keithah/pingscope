import XCTest
@testable import PingScopeCore
@testable import PingScopeHistoryKit

final class HistoryNetworkPresentationTests: XCTestCase {
    func testCardsExposeMetricsGlyphVPNStatusAndStableText() throws {
        let samples = [
            sample(at: 1, latency: 10, interface: "wifi", name: "Home", isVPN: true),
            sample(at: 2, latency: 30, interface: "wifi", name: "Home"),
            sample(at: 3, latency: nil, interface: "wifi", name: "Home"),
        ]

        let card = try XCTUnwrap(HistoryNetworkPresentation(samples: samples).cards.first)

        XCTAssertEqual(card.label, "Home")
        XCTAssertEqual(card.interfaceLabel, "Wi-Fi")
        XCTAssertEqual(card.systemImage, "wifi")
        XCTAssertEqual(card.sampleCountText, "3 samples")
        XCTAssertEqual(card.averageText, "20 ms")
        XCTAssertEqual(card.p95Text, "30 ms")
        XCTAssertEqual(card.lossText, "33.3%")
        XCTAssertEqual(card.uptimeText, "66.7%")
        XCTAssertEqual(card.status, .down)
        XCTAssertTrue(card.hasVPN)
        XCTAssertEqual(card.sparklineSamples.map(\.id), samples.map(\.id))
    }

    func testSelectionFiltersSamplesToExactNetworkKeyAndAllRestoresThem() throws {
        let home = sample(at: 1, latency: 10, interface: "wifi", name: "Home")
        let office = sample(at: 2, latency: 20, interface: "wifi", name: "Office")
        let cellular = sample(at: 3, latency: 30, interface: "cellular", name: "Cellular · 5G")
        let samples = [home, office, cellular]
        let homeKey = HistoryNetworkKey(interface: "wifi", name: "Home")

        let selected = HistoryNetworkPresentation(
            samples: samples,
            selection: .network(homeKey)
        )

        XCTAssertEqual(selected.selectedSamples.map(\.id), [home.id])
        XCTAssertEqual(selected.selectedLabel, "Home")
        XCTAssertEqual(
            HistoryNetworkPresentation(samples: samples, selection: .all).selectedSamples.map(\.id),
            samples.map(\.id)
        )
    }

    func testFilteredHistoryPresentationRecomputesGraphStatisticsAndSessions() throws {
        let home = sample(at: 10, latency: 10, interface: "wifi", name: "Home")
        let office = sample(at: 20, latency: 90, interface: "wifi", name: "Office")
        let result = PingScopeIOSHistoryLoadResult(
            hostID: Self.hostID,
            range: .h1,
            cutoff: date(0),
            endingAt: date(3_600),
            samples: [home, office],
            chartReduction: HistoryChartReduction(samples: [home, office]),
            isCollecting: false
        )
        let presentation = PingScopeIOSHistoryPresentation(loadResult: result)

        let filtered = presentation.applyingNetworkSelection(
            .network(HistoryNetworkKey(interface: "wifi", name: "Office"))
        )

        XCTAssertEqual(filtered.sourceSamples.map(\.id), [office.id])
        XCTAssertEqual(filtered.statistics.map(\.value), ["90 ms", "90 ms", "0%", "0"])
        XCTAssertEqual(filtered.graphData.points.map(\.latencyMilliseconds), [90])
        XCTAssertEqual(filtered.sessions.flatMap(\.session.samples).map(\.id), [office.id])
        XCTAssertEqual(filtered.graphData.startDate, date(0))
        XCTAssertEqual(filtered.graphData.endDate, date(3_600))
    }

    private static let hostID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    private func sample(
        at seconds: TimeInterval,
        latency: Double?,
        interface: String?,
        name: String?,
        isVPN: Bool = false
    ) -> PingResult {
        var result: PingResult
        if let latency {
            result = .success(hostID: Self.hostID, latency: .milliseconds(latency), timestamp: date(seconds))
        } else {
            result = .failure(hostID: Self.hostID, reason: .timeout, timestamp: date(seconds))
        }
        result.networkInterface = interface
        result.networkName = name
        result.isVPN = isVPN
        return result
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

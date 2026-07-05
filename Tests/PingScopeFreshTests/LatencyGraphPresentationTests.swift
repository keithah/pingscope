import XCTest
@testable import PingScope
@testable import PingScopeCore

final class LatencyGraphPresentationTests: XCTestCase {
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
        let source = HostLatencyGraphSeries(host: host, samples: makeSamples(count: 200), color: .blue, isPrimary: true)
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
}

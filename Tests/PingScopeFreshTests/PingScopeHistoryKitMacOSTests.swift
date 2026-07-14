#if os(macOS)
import XCTest
import PingScopeCore
@testable import PingScopeHistoryKit
@testable import PingScope

final class PingScopeHistoryKitMacOSTests: XCTestCase {
    func testHistoryMetricsLinkAndRunOnMacOS() {
        let hostID = UUID()
        let samples = [
            PingResult.success(hostID: hostID, latency: .milliseconds(10)),
            PingResult.success(hostID: hostID, latency: .milliseconds(30)),
        ]

        let metrics = HistoryMetrics(samples: samples)

        XCTAssertEqual(metrics.averageMilliseconds, 20)
        XCTAssertEqual(metrics.minimumMilliseconds, 10)
        XCTAssertEqual(metrics.maximumMilliseconds, 30)
    }

    func testMacNetworkTablePresentationRendersSharedReducerRows() {
        let hostID = UUID()
        var wifi = PingResult.success(hostID: hostID, latency: .milliseconds(10))
        wifi.networkInterface = "wifi"
        wifi.networkName = "Home Wi-Fi"
        var cellular = PingResult.failure(hostID: hostID, reason: .timeout)
        cellular.networkInterface = "cellular"
        cellular.networkName = "Cellular · 5G"

        let presentation = MacHistoryNetworkTablePresentation(samples: [wifi, cellular])

        XCTAssertEqual(presentation.rows.map(\.label), ["Cellular · 5G", "Home Wi-Fi"])
        XCTAssertEqual(presentation.rows.map(\.interfaceLabel), ["Cellular", "Wi-Fi"])
        XCTAssertEqual(presentation.rows.map(\.sampleCount), [1, 1])
        XCTAssertEqual(presentation.rows.map(\.lossText), ["100%", "0%"])
    }
}
#endif

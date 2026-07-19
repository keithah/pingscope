import XCTest
@testable import PingScopeCore
@testable import PingScopeHistoryKit

final class HistoryNetworkBreakdownTests: XCTestCase {
    func testEmptyInputProducesNoGroups() {
        XCTAssertEqual(HistoryNetworkBreakdown(samples: []).groups, [])
    }

    func testSingleNetworkCarriesIdentityBoundsSamplesVPNAndMetrics() throws {
        let samples = [
            sample(at: 10, latency: 10, interface: " Wi-Fi ", name: "Home Wi-Fi"),
            sample(at: 20, latency: 30, interface: "wlan", name: "Home Wi-Fi", isVPN: true),
        ]

        let group = try XCTUnwrap(HistoryNetworkBreakdown(samples: samples).groups.first)

        XCTAssertEqual(group.key, HistoryNetworkKey(interface: "wifi", name: "Home Wi-Fi"))
        XCTAssertEqual(group.displayLabel, "Home Wi-Fi")
        XCTAssertEqual(group.interface, "wifi")
        XCTAssertEqual(group.sampleCount, 2)
        XCTAssertEqual(group.firstSeen, date(10))
        XCTAssertEqual(group.lastSeen, date(20))
        XCTAssertTrue(group.hasVPN)
        XCTAssertEqual(group.samples.map(\.id), samples.map(\.id))
        XCTAssertEqual(group.metrics.averageMilliseconds, 20)
        XCTAssertEqual(group.metrics.p95Milliseconds, 30)
        XCTAssertEqual(group.metrics.lossPercent, 0)
        XCTAssertEqual(group.metrics.uptimePercent, 100)
        XCTAssertEqual(group.metrics.outageCount, 0)
    }

    func testMultipleNetworksIncludeOneUnknownBucket() {
        let breakdown = HistoryNetworkBreakdown(samples: [
            sample(at: 1, latency: 10, interface: nil, name: nil),
            sample(at: 2, latency: nil, interface: nil, name: nil),
            sample(at: 3, latency: 30, interface: "cell", name: "Cellular · LTE"),
            sample(at: 4, latency: 40, interface: "ethernet", name: nil),
        ])

        let unknown = breakdown.groups.first { $0.key == .unknown }
        XCTAssertEqual(unknown?.displayLabel, "Unknown")
        XCTAssertNil(unknown?.interface)
        XCTAssertEqual(unknown?.sampleCount, 2)
        XCTAssertEqual(breakdown.groups.map(\.displayLabel).sorted(), ["Cellular · LTE", "Unknown", "Wired"])
    }

    func testDistinctNamesOnSameInterfaceProduceDistinctGroups() {
        let breakdown = HistoryNetworkBreakdown(samples: [
            sample(at: 1, latency: 10, interface: "wifi", name: "Home Wi-Fi"),
            sample(at: 2, latency: 20, interface: "wifi", name: "Office Wi-Fi"),
            sample(at: 3, latency: 30, interface: "wi-fi", name: "Home Wi-Fi"),
        ])

        XCTAssertEqual(breakdown.groups.count, 2)
        XCTAssertEqual(breakdown.groups.first { $0.displayLabel == "Home Wi-Fi" }?.sampleCount, 2)
        XCTAssertEqual(breakdown.groups.first { $0.displayLabel == "Office Wi-Fi" }?.sampleCount, 1)
    }

    func testGroupMetricsMatchHistoryMetricsIncludingOutageRuns() throws {
        let samples = [
            sample(at: 1, latency: 10, interface: "wifi", name: "Home"),
            sample(at: 2, latency: nil, interface: "wifi", name: "Home"),
            sample(at: 3, latency: nil, interface: "wifi", name: "Home"),
            sample(at: 4, latency: 30, interface: "wifi", name: "Home"),
            sample(at: 5, latency: nil, interface: "wifi", name: "Home"),
        ]

        let metrics = try XCTUnwrap(HistoryNetworkBreakdown(samples: samples).groups.first).metrics

        XCTAssertEqual(metrics.averageMilliseconds, 20)
        XCTAssertEqual(metrics.p95Milliseconds, 30)
        XCTAssertEqual(metrics.lossPercent, 60)
        XCTAssertEqual(metrics.uptimePercent, 40)
        XCTAssertEqual(metrics.outageCount, 2)
    }

    func testOrderingUsesWorstUptimeThenMostSamplesThenLabel() {
        let breakdown = HistoryNetworkBreakdown(samples: [
            sample(at: 1, latency: nil, interface: "wifi", name: "Worst"),
            sample(at: 2, latency: 10, interface: "cellular", name: "Zulu"),
            sample(at: 3, latency: 10, interface: "wired", name: "Alpha"),
            sample(at: 4, latency: 20, interface: "other", name: "More samples"),
            sample(at: 5, latency: 30, interface: "other", name: "More samples"),
        ])

        XCTAssertEqual(breakdown.groups.map(\.displayLabel), ["Worst", "More samples", "Alpha", "Zulu"])
    }

    private static let hostID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

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

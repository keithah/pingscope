import XCTest
@testable import PingScopeCore
@testable import PingScopeiOS

final class PingScopeIOSMultiHostPresentationTests: XCTestCase {
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

    func testDisplayModeAlwaysUsesSignalForAllHosts() {
        XCTAssertEqual(PingScopeIOSDisplayMode.signal.resolvedForHostScope(showsAllHosts: false), .signal)
        XCTAssertEqual(PingScopeIOSDisplayMode.ring.resolvedForHostScope(showsAllHosts: false), .ring)
        XCTAssertEqual(PingScopeIOSDisplayMode.signal.resolvedForHostScope(showsAllHosts: true), .signal)
        XCTAssertEqual(PingScopeIOSDisplayMode.ring.resolvedForHostScope(showsAllHosts: true), .signal)
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
}

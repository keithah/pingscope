import XCTest
@testable import PingScopeCore

final class ProbeBehaviorTests: XCTestCase {
    func testAppStoreFlavorHidesICMPAndReturnsUnavailableProbe() async {
        XCTAssertEqual(BuildFlavor.appStore.availableMethods, [.tcp, .udp, .starlink])
        XCTAssertEqual(BuildFlavor.developerID.availableMethods, [.tcp, .udp, .icmp, .starlink])

        let host = HostConfig(displayName: "Raw ICMP", address: "1.1.1.1", method: .icmp, port: nil)
        let probe = await DefaultProbeFactory(flavor: .appStore).makeProbe(for: .icmp)
        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .icmpUnavailable)
        XCTAssertEqual(result.method, .icmp)
    }

    func testStarlinkProbeMapsConnectedStatusToLatencyResult() async throws {
        let host = HostConfig.defaultStarlinkDish
        let probe = StarlinkProbe(statusClient: FakeStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: 42.5,
            telemetry: StarlinkTelemetry(
                state: "CONNECTED",
                popPingDropRate: 0.1,
                downlinkThroughputBps: 120_000_000,
                uplinkThroughputBps: 18_000_000,
                fractionObstructed: 0.02,
                activeAlerts: ["roaming"]
            )
        )))

        let result = await probe.measure(host)

        XCTAssertEqual(result.method, .starlink)
        XCTAssertEqual(result.port, 9200)
        XCTAssertEqual(try XCTUnwrap(result.latency).milliseconds, 42.5, accuracy: 0.01)
        XCTAssertEqual(result.metadata.starlink?.state, "CONNECTED")
        XCTAssertEqual(result.metadata.starlink?.popPingDropRate, 0.1)
        XCTAssertEqual(result.metadata.note, "state=CONNECTED drop=10% obstructed=2% alerts=roaming")
    }

    func testStarlinkProbeMapsDisconnectedStatusToFailureWithTelemetry() async {
        let host = HostConfig.defaultStarlinkDish
        let probe = StarlinkProbe(statusClient: FakeStarlinkStatusClient(status: StarlinkStatus(
            popPingLatencyMilliseconds: nil,
            telemetry: StarlinkTelemetry(state: "SEARCHING", popPingDropRate: 1)
        )))

        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .networkUnavailable)
        XCTAssertEqual(result.metadata.starlink?.state, "SEARCHING")
        XCTAssertEqual(result.metadata.starlink?.popPingDropRate, 1)
    }

    func testTimeoutProbeCancelsLateProbeAndReturnsTimeout() async {
        let host = HostConfig(displayName: "Slow", address: "example.com", timeout: .milliseconds(10))
        let slowProbe = CancellableSlowProbe()
        let probe = TimeoutProbe(wrapping: slowProbe)

        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .timeout)
        let wasCancelled = await slowProbe.wasCancelled
        XCTAssertTrue(wasCancelled)
    }
}

private actor CancellableSlowProbe: PingProbe {
    private(set) var wasCancelled = false

    func measure(_ host: HostConfig) async -> PingResult {
        do {
            try await Task.sleep(for: .seconds(60))
            return .success(hostID: host.id, latency: .seconds(60)).withHostMetadata(from: host)
        } catch {
            wasCancelled = true
            return .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
        }
    }
}

private struct FakeStarlinkStatusClient: StarlinkStatusFetching {
    let status: StarlinkStatus

    func fetchStatus(host: HostConfig) async throws -> StarlinkStatus {
        status
    }
}

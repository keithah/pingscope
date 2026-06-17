import XCTest
@testable import PingScopeCore

final class ProbeBehaviorTests: XCTestCase {
    func testAppStoreFlavorHidesICMPAndReturnsUnavailableProbe() async {
        XCTAssertEqual(BuildFlavor.appStore.availableMethods, [.tcp, .udp])
        XCTAssertEqual(BuildFlavor.developerID.availableMethods, [.tcp, .udp, .icmp])

        let host = HostConfig(displayName: "Raw ICMP", address: "1.1.1.1", method: .icmp, port: nil)
        let probe = await DefaultProbeFactory(flavor: .appStore).makeProbe(for: .icmp)
        let result = await probe.measure(host)

        XCTAssertEqual(result.failureReason, .icmpUnavailable)
        XCTAssertEqual(result.method, .icmp)
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

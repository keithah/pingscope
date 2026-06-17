import XCTest
import PingScopeCore
import PingScopeiOS

final class LiveMonitorSessionControllerTests: XCTestCase {
    func testControllerStartsFiniteSessionAndPublishesProbeResult() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10))
        )

        await controller.start(duration: .thirtySeconds)
        try await Task.sleep(for: .milliseconds(40))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.duration, .thirtySeconds)
        XCTAssertEqual(snapshot.session?.phase(), .live)
        XCTAssertEqual(snapshot.health.status, HealthStatus.healthy)
        XCTAssertEqual(snapshot.health.latestResult?.latency?.milliseconds.rounded(), 18)
        let measurementCount = await probe.measurementCount
        XCTAssertGreaterThanOrEqual(measurementCount, 1)
    }

    func testControllerStopsWithUserStoppedReasonAndCancelsFurtherMeasurements() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18)),
            .success(hostID: host.id, latency: .milliseconds(19)),
            .success(hostID: host.id, latency: .milliseconds(20))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10))
        )

        await controller.start(duration: .oneMinute)
        try await Task.sleep(for: .milliseconds(25))
        await controller.stop(reason: .userStopped)
        let countAfterStop = await probe.measurementCount
        try await Task.sleep(for: .milliseconds(40))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.phase(), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .userStopped)
        let finalCount = await probe.measurementCount
        XCTAssertEqual(finalCount, countAfterStop)
    }

    func testControllerEndsWhenBackgroundRuntimeExpiresBeforeSelectedDuration() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1")
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(18))
        ])
        let controller = LiveMonitorSessionController(
            host: host,
            probeFactory: StaticProbeFactory(probe: probe),
            policy: MonitorSessionPolicy(liveFreshness: .milliseconds(50), staleAfter: .milliseconds(100), probeInterval: .milliseconds(10)),
            backgroundRuntimeLimit: .milliseconds(35)
        )

        await controller.start(duration: .oneMinute)
        try await Task.sleep(for: .milliseconds(80))

        let snapshot = await controller.snapshot()
        XCTAssertEqual(snapshot.session?.phase(), .ended)
        XCTAssertEqual(snapshot.session?.endReason, .backgroundRuntimeExpired)
        let measurementCount = await probe.measurementCount
        XCTAssertGreaterThanOrEqual(measurementCount, 1)
    }
}

private actor RecordingProbe: PingProbe {
    private var results: [PingResult]
    private(set) var measurementCount = 0

    init(results: [PingResult]) {
        self.results = results
    }

    func measure(_ host: HostConfig) async -> PingResult {
        measurementCount += 1
        let index = min(measurementCount - 1, results.count - 1)
        return results[index].withHostMetadata(from: host)
    }
}

private struct StaticProbeFactory: ProbeFactory {
    let probe: RecordingProbe

    func makeProbe(for method: PingMethod) async -> any PingProbe {
        probe
    }
}

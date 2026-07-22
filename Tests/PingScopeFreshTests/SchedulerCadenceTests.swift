import XCTest
@testable import PingScopeCore

final class SchedulerCadenceTests: XCTestCase {
    func testBatteryDoublesInterProbeWait() async throws {
        let host = HostConfig(id: UUID(), displayName: "Cloudflare", address: "1.1.1.1", interval: .seconds(5), timeout: .seconds(1))
        let probe = RecordingProbe(results: [
            .success(hostID: host.id, latency: .milliseconds(10))
        ])
        let clock = ManualClock()
        let scheduler = MeasurementScheduler(
            probeFactory: StaticProbeFactory(probe: probe),
            clock: clock
        )
        // battery => 2x => 10s between probes for a 5s base.
        await scheduler.setCadenceInputs(CadenceInputs(visibility: .activeUI, powerSource: .battery, isLowPowerMode: false, thermalTier: .nominal))

        let stream = await scheduler.start(hosts: [host])
        var iterator = stream.makeAsyncIterator()

        // First probe fires immediately (no startup stagger).
        let first = await iterator.next()
        XCTAssertNotNil(first)
        try await clock.waitForSleepers(atLeast: 1)

        // Advancing 5s (the raw base) is NOT enough — battery scaled it to 10s.
        clock.advance(by: .seconds(5))
        let measurementsAfter5s = await probe.measurementCount
        XCTAssertEqual(measurementsAfter5s, 1)

        // Advancing the rest (total 10s) releases the second probe.
        clock.advance(by: .seconds(5))
        let second = await iterator.next()
        XCTAssertNotNil(second)

        await scheduler.stop()
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

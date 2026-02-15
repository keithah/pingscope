import Foundation
import XCTest
@testable import PingScope

final class PingSchedulerTests: XCTestCase {
    func testShorterIntervalHostProducesMoreResultsOverSameWindow() async {
        let fastHost = PingScope.Host(name: "Fast", address: "fast.local", intervalOverride: .milliseconds(120))
        let slowHost = PingScope.Host(name: "Slow", address: "slow.local", intervalOverride: .milliseconds(320))

        let counts = await runScheduler(
            hosts: [fastHost, slowHost],
            fallbackInterval: Duration.seconds(1),
            window: Duration.milliseconds(900)
        )

        let fastCount = counts[fastHost.address, default: 0]
        let slowCount = counts[slowHost.address, default: 0]

        XCTAssertGreaterThan(
            fastCount,
            slowCount,
            "Host with shorter interval should be pinged more often"
        )
    }

    func testNilIntervalOverrideUsesProvidedGlobalFallback() async {
        let host = PingScope.Host(name: "Fallback", address: "fallback.local", intervalOverride: nil)

        let fastFallbackCounts = await runScheduler(
            hosts: [host],
            fallbackInterval: Duration.milliseconds(120),
            window: Duration.milliseconds(700)
        )
        let slowFallbackCounts = await runScheduler(
            hosts: [host],
            fallbackInterval: Duration.milliseconds(320),
            window: Duration.milliseconds(700)
        )

        let fastCount = fastFallbackCounts[host.address, default: 0]
        let slowCount = slowFallbackCounts[host.address, default: 0]

        XCTAssertGreaterThan(
            fastCount,
            slowCount,
            "Host without override should follow provided global fallback interval"
        )
    }

    private func runScheduler(
        hosts: [PingScope.Host],
        fallbackInterval: Duration,
        window: Duration
    ) async -> [String: Int] {
        let collector = ResultCollector()
        let scheduler = PingScheduler(
            pingOperation: { host in
                PingResult.success(host: host.address, port: host.port, latency: .milliseconds(10))
            },
            healthRecorder: { _ in true }
        )

        await scheduler.setResultHandler { result, _ in
            Task {
                await collector.record(host: result.host)
            }
        }

        await scheduler.start(hosts: hosts, intervalFallback: fallbackInterval)
        try? await Task.sleep(for: window)
        await scheduler.stop()

        try? await Task.sleep(for: .milliseconds(50))
        return await collector.snapshot()
    }
}

private actor ResultCollector {
    private var counts: [String: Int] = [:]

    func record(host: String) {
        counts[host, default: 0] += 1
    }

    func snapshot() -> [String: Int] {
        counts
    }
}

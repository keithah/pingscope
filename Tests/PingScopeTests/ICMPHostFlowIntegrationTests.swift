import Foundation
import XCTest
@testable import PingScope

final class ICMPHostFlowIntegrationTests: XCTestCase {
    func testPersistedICMPHostIsScheduledAfterReloadFromHostStore() async {
        let suiteName = "ICMPHostFlowIntegrationTests-persisted-icmp-\(UUID().uuidString)"
        let defaults = makeIsolatedUserDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let persistedHost = Host(
            name: "Persisted ICMP",
            address: "persisted-icmp.local",
            port: 0,
            pingMethod: .icmp,
            intervalOverride: .milliseconds(120)
        )

        let writerStore = HostStore(defaults: defaults)
        await writerStore.add(persistedHost)

        let readerStore = HostStore(defaults: defaults)
        let hostsFromPersistence = await readerStore.allHosts
        XCTAssertTrue(
            hostsFromPersistence.contains(where: { $0.id == persistedHost.id }),
            "Persisted ICMP host should be available from HostStore.allHosts before scheduling"
        )

        let collector = ScheduledHostCollector()
        let scheduler = PingScheduler(
            pingOperation: { host in
                await collector.recordExecution(host: host)
                return PingResult.success(host: host.address, port: host.port, latency: .milliseconds(8))
            },
            healthRecorder: { _ in true }
        )

        await scheduler.setResultHandler { result, _ in
            Task {
                await collector.recordResult(host: result.host)
            }
        }

        await scheduler.start(hosts: hostsFromPersistence, intervalFallback: Duration.seconds(1))
        try? await Task.sleep(for: Duration.milliseconds(350))
        await scheduler.stop()
        try? await Task.sleep(for: Duration.milliseconds(50))

        let executionCount = await collector.executionCount(forHostID: persistedHost.id)
        let resultCount = await collector.resultCount(forAddress: persistedHost.address)

        XCTAssertGreaterThan(
            executionCount,
            0,
            "Persisted ICMP host should be executed by scheduler"
        )
        XCTAssertGreaterThan(
            resultCount,
            0,
            "Persisted ICMP host should emit scheduler results"
        )
    }

    private func makeIsolatedUserDefaults(suiteName: String) -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            fatalError("UserDefaults suite creation failed")
        }
        return defaults
    }
}

private actor ScheduledHostCollector {
    private var executionCountsByID: [UUID: Int] = [:]
    private var resultCountsByAddress: [String: Int] = [:]

    func recordExecution(host: PingScope.Host) {
        executionCountsByID[host.id, default: 0] += 1
    }

    func recordResult(host: String) {
        resultCountsByAddress[host, default: 0] += 1
    }

    func executionCount(forHostID hostID: UUID) -> Int {
        executionCountsByID[hostID, default: 0]
    }

    func resultCount(forAddress address: String) -> Int {
        resultCountsByAddress[address, default: 0]
    }
}

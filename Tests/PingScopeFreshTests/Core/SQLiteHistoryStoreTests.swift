import XCTest
@testable import PingScopeCore

final class SQLiteHistoryStoreTests: XCTestCase {
    func testConcurrentMultiHostAppends() async throws {
        let url = temporaryHistoryURL()
        let store = SQLiteHistoryStore(url: url)
        let hosts = (0..<8).map { index in
            HostConfig(id: UUID(), displayName: "Host \(index)", address: "host-\(index).example")
        }
        let samplesPerHost = 16
        let base = Date(timeIntervalSince1970: 30_000)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (hostIndex, host) in hosts.enumerated() {
                group.addTask {
                    let results = (0..<samplesPerHost).map { sampleIndex in
                        PingResult.success(
                            hostID: host.id,
                            latency: .milliseconds(Double(sampleIndex)),
                            timestamp: base.addingTimeInterval(Double(hostIndex * samplesPerHost + sampleIndex))
                        ).withHostMetadata(from: host)
                    }
                    try await store.appendAndWait(results)
                }
            }
            try await group.waitForAll()
        }

        for host in hosts {
            let results = await store.samples(hostID: host.id, since: base, limit: samplesPerHost + 1)
            XCTAssertEqual(results.count, samplesPerHost)
            XCTAssertEqual(results.map(\.hostID), Array(repeating: host.id, count: samplesPerHost))
            XCTAssertEqual(Set(results.map(\.id)).count, samplesPerHost)
            XCTAssertEqual(results.map { Int($0.latency?.milliseconds ?? -1) }, Array(0..<samplesPerHost))
        }
    }

    private func temporaryHistoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-concurrent-history-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("History.sqlite")
    }
}

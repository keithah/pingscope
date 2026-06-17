import XCTest
@testable import PingScopeCore

final class HistoryStoreTests: XCTestCase {
    func testSQLiteHistoryStorePersistsSuccessAndFailureSamples() async throws {
        let url = temporaryHistoryURL()
        let hostID = UUID()
        let base = Date(timeIntervalSince1970: 1_000)
        let store = SQLiteHistoryStore(url: url)
        await store.append(.success(
            hostID: hostID,
            latency: .milliseconds(17),
            timestamp: base,
            metadata: ProbeMetadata(note: "ok")
        ).withHostMetadata(from: HostConfig(id: hostID, displayName: "Example", address: "example.com")))
        await store.append(.failure(
            hostID: hostID,
            reason: .timeout,
            timestamp: base.addingTimeInterval(1),
            metadata: ProbeMetadata(note: "late")
        ).withHostMetadata(from: HostConfig(id: hostID, displayName: "Example", address: "example.com")))

        let reloaded = SQLiteHistoryStore(url: url)
        let samples = await reloaded.samples(hostID: hostID, since: base.addingTimeInterval(-1), limit: 10)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(try XCTUnwrap(samples[0].latency).milliseconds, 17, accuracy: 0.01)
        XCTAssertEqual(samples[0].metadata.note, "ok")
        XCTAssertEqual(samples[1].failureReason, .timeout)
        XCTAssertEqual(samples[1].metadata.note, "late")
    }

    func testSQLiteHistoryStorePrunesByRetention() async throws {
        let url = temporaryHistoryURL()
        let hostID = UUID()
        let host = HostConfig(id: hostID, displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 2_000)
        let store = SQLiteHistoryStore(url: url, retention: .seconds(60))

        await store.append(.success(hostID: hostID, latency: .milliseconds(10), timestamp: base).withHostMetadata(from: host))
        await store.append(.success(hostID: hostID, latency: .milliseconds(20), timestamp: base.addingTimeInterval(120)).withHostMetadata(from: host))

        let samples = await store.samples(hostID: hostID, since: base.addingTimeInterval(-10), limit: 10)

        XCTAssertEqual(samples.map { Int($0.latency?.milliseconds ?? 0) }, [20])
    }

    func testRuntimeWritesIngestedResultsToHistoryStore() async throws {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let history = RecordingHistoryStore()
        let runtime = PingRuntime(
            hostStore: HostStore(defaultHosts: [host]),
            scheduler: MeasurementScheduler(probeFactory: NoopProbeFactory()),
            historyStore: history
        )

        await runtime.ingest(.success(hostID: host.id, latency: .milliseconds(19)).withHostMetadata(from: host))

        let recorded = await history.waitForSamples(count: 1)
        XCTAssertEqual(recorded.first?.hostID, host.id)
        XCTAssertEqual(try XCTUnwrap(recorded.first?.latency).milliseconds, 19, accuracy: 0.01)
    }

    func testHistoryExporterFormatsCSVJSONAndText() throws {
        let host = HostConfig(displayName: "Comma, Host", address: "example.com")
        let samples = [
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(18.4),
                timestamp: Date(timeIntervalSince1970: 1_000),
                metadata: ProbeMetadata(note: "fresh")
            ).withHostMetadata(from: host),
            PingResult.failure(
                hostID: host.id,
                reason: .timeout,
                timestamp: Date(timeIntervalSince1970: 1_001),
                metadata: ProbeMetadata(note: "late")
            ).withHostMetadata(from: host)
        ]

        let csv = HistoryExporter.csv(samples: samples, host: host)
        XCTAssertTrue(csv.contains("\"Comma, Host\""))
        XCTAssertTrue(csv.contains(",OK,18,,fresh"))
        XCTAssertTrue(csv.contains(",Failed,,timeout,late"))

        let jsonData = try HistoryExporter.data(samples: samples, host: host, format: .json)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        XCTAssertTrue(json.contains("\"displayName\" : \"Comma, Host\""))
        XCTAssertTrue(json.contains("\"failureReason\" : \"timeout\""))

        let text = HistoryExporter.text(samples: samples, host: host)
        XCTAssertTrue(text.contains("PingScope History"))
        XCTAssertTrue(text.contains("18ms  OK"))
        XCTAssertTrue(text.contains("Timed out  Failed"))
    }

    func testWidgetSnapshotSummarizesRuntimeState() {
        let primary = HostConfig(displayName: "Cloudflare", address: "1.1.1.1")
        let secondary = HostConfig(displayName: "Gateway", address: "192.168.1.1")
        let primaryResult = PingResult.success(
            hostID: primary.id,
            latency: .milliseconds(16),
            timestamp: Date(timeIntervalSince1970: 5_000)
        ).withHostMetadata(from: primary)
        let secondaryResult = PingResult.failure(
            hostID: secondary.id,
            reason: .timeout,
            timestamp: Date(timeIntervalSince1970: 5_001)
        ).withHostMetadata(from: secondary)
        var primaryHealth = HostHealth(hostID: primary.id)
        primaryHealth.ingest(primaryResult)
        var secondaryHealth = HostHealth(hostID: secondary.id, thresholds: LatencyThresholds(downAfterFailures: 1))
        secondaryHealth.ingest(secondaryResult)
        var primarySeries = SampleSeries(hostID: primary.id)
        primarySeries.append(primaryResult)
        var secondarySeries = SampleSeries(hostID: secondary.id)
        secondarySeries.append(secondaryResult)
        let runtimeSnapshot = RuntimeSnapshot(
            hosts: [primary, secondary],
            primaryHostID: primary.id,
            healthByHost: [
                primary.id: primaryHealth,
                secondary.id: secondaryHealth
            ],
            samplesByHost: [
                primary.id: primarySeries,
                secondary.id: secondarySeries
            ]
        )

        let widgetSnapshot = WidgetSnapshot.make(
            from: runtimeSnapshot,
            networkStatus: .noInternet,
            generatedAt: Date(timeIntervalSince1970: 5_002)
        )

        XCTAssertEqual(widgetSnapshot.primaryHostID, primary.id)
        XCTAssertEqual(widgetSnapshot.hosts.count, 2)
        XCTAssertEqual(widgetSnapshot.hosts.first?.isPrimary, true)
        XCTAssertEqual(
            try XCTUnwrap(widgetSnapshot.health.first { $0.hostID == primary.id }?.latencyMilliseconds),
            16,
            accuracy: 0.01
        )
        XCTAssertEqual(widgetSnapshot.health.first { $0.hostID == secondary.id }?.status, .down)
        XCTAssertEqual(widgetSnapshot.recentSamples.map(\.hostID), [primary.id, secondary.id])
        XCTAssertEqual(widgetSnapshot.networkStatus, .noInternet)
    }

    func testWidgetSnapshotStorePersistsEncodedSnapshot() async throws {
        let suiteName = "pingscope-widget-tests-\(UUID().uuidString)"
        let store = WidgetSnapshotStore(suiteName: suiteName, key: "snapshot")
        let inspectionDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let hostID = UUID()
        let snapshot = WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [
                WidgetHost(id: hostID, displayName: "Cloudflare", address: "1.1.1.1", method: .tcp, port: 443, isPrimary: true)
            ],
            health: [
                WidgetHostHealth(
                    hostID: hostID,
                    status: .healthy,
                    latencyMilliseconds: 14,
                    consecutiveFailureCount: 0,
                    failureReason: nil,
                    latestResultAt: Date(timeIntervalSince1970: 6_000)
                )
            ],
            recentSamples: [],
            networkStatus: .connected,
            generatedAt: Date(timeIntervalSince1970: 6_001)
        )

        await store.save(snapshot)
        let loaded = await store.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertNotNil(inspectionDefaults.data(forKey: WidgetSnapshotStore.legacyKey))
        await store.delete()
        let deleted = await store.load()
        XCTAssertNil(deleted)
        XCTAssertNil(inspectionDefaults.data(forKey: WidgetSnapshotStore.legacyKey))
    }

    private func temporaryHistoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-history-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("History.sqlite")
    }
}

private struct NoopProbeFactory: ProbeFactory {
    func makeProbe(for method: PingMethod) async -> any PingProbe {
        NoopProbe()
    }
}

private struct NoopProbe: PingProbe {
    func measure(_ host: HostConfig) async -> PingResult {
        .failure(hostID: host.id, reason: .cancelled).withHostMetadata(from: host)
    }
}

private actor RecordingHistoryStore: PingHistoryStore {
    private var stored: [PingResult] = []

    func append(_ result: PingResult) async {
        stored.append(result)
    }

    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(stored.filter { $0.hostID == hostID && $0.timestamp >= since }.prefix(limit))
    }

    func prune(olderThan cutoff: Date) async {
        stored.removeAll { $0.timestamp < cutoff }
    }

    func deleteAll() async {
        stored.removeAll()
    }

    func waitForSamples(count: Int) async -> [PingResult] {
        for _ in 0..<20 {
            if stored.count >= count {
                return stored
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return stored
    }
}

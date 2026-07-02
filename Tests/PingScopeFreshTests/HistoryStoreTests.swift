import XCTest
import SQLite3
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

    func testSQLiteHistoryStorePersistsStarlinkMetadata() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig.defaultStarlinkDish
        let base = Date(timeIntervalSince1970: 1_500)
        let store = SQLiteHistoryStore(url: url)
        await store.append(.success(
            hostID: host.id,
            latency: .milliseconds(38),
            timestamp: base,
            metadata: ProbeMetadata(
                note: "state=CONNECTED",
                starlink: StarlinkTelemetry(
                    state: "CONNECTED",
                    popPingDropRate: 0.2,
                    downlinkThroughputBps: 99_000_000,
                    activeAlerts: ["obstructed"]
                )
            )
        ).withHostMetadata(from: host))

        let reloaded = SQLiteHistoryStore(url: url)
        let samples = await reloaded.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].metadata.note, "state=CONNECTED")
        XCTAssertEqual(samples[0].metadata.starlink?.state, "CONNECTED")
        XCTAssertEqual(samples[0].metadata.starlink?.popPingDropRate, 0.2)
        XCTAssertEqual(samples[0].metadata.starlink?.activeAlerts, ["obstructed"])
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

    func testSQLiteHistoryStoreCreatesTimestampPruneIndex() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let store = SQLiteHistoryStore(url: url)

        await store.append(.success(hostID: host.id, latency: .milliseconds(10)).withHostMetadata(from: host))

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA index_list('ping_samples');", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        var indexes: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                indexes.insert(String(cString: name))
            }
        }

        XCTAssertTrue(indexes.contains("ping_samples_timestamp"))
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

        let starlinkCSV = HistoryExporter.csv(
            samples: [
                PingResult.success(
                    hostID: host.id,
                    latency: .milliseconds(41),
                    timestamp: Date(timeIntervalSince1970: 1_002),
                    metadata: ProbeMetadata(
                        note: "state=CONNECTED",
                        starlink: StarlinkTelemetry(state: "CONNECTED", popPingDropRate: 0.12, downlinkThroughputBps: 80_000_000)
                    )
                ).withHostMetadata(from: host)
            ],
            host: host
        )
        XCTAssertTrue(starlinkCSV.contains("starlink_state,starlink_drop_rate"))
        XCTAssertTrue(starlinkCSV.contains(",state=CONNECTED,CONNECTED,0.12,80000000.0"))

        let jsonData = try HistoryExporter.data(samples: samples, host: host, format: .json)
        let json = try XCTUnwrap(String(data: jsonData, encoding: .utf8))
        XCTAssertTrue(json.contains("\"displayName\" : \"Comma, Host\""))
        XCTAssertTrue(json.contains("\"failureReason\" : \"timeout\""))

        let text = HistoryExporter.text(samples: samples, host: host)
        XCTAssertTrue(text.contains("PingScope History"))
        XCTAssertTrue(text.contains("18ms  OK"))
        XCTAssertTrue(text.contains("Timed out  Failed"))
    }

    func testHistoryExporterWriteMatchesInMemoryFormats() throws {
        let host = HostConfig(displayName: "Export Host", address: "example.com")
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for format in [HistoryExportFormat.csv, .text] {
            let url = directory.appendingPathComponent("history.\(format.fileExtension)")
            try HistoryExporter.write(samples: samples, host: host, format: format, to: url)
            let written = try Data(contentsOf: url)

            XCTAssertEqual(written, try HistoryExporter.data(samples: samples, host: host, format: format))
        }

        let jsonURL = directory.appendingPathComponent("history.json")
        try HistoryExporter.write(samples: samples, host: host, format: .json, to: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let writtenJSON = try decoder.decode(HistoryExportDocumentProbe.self, from: Data(contentsOf: jsonURL))
        let memoryJSON = try decoder.decode(
            HistoryExportDocumentProbe.self,
            from: HistoryExporter.data(samples: samples, host: host, format: .json)
        )

        XCTAssertEqual(writtenJSON.host, memoryJSON.host)
        XCTAssertEqual(writtenJSON.samples, memoryJSON.samples)
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

    func testWidgetSnapshotUsesDefaultHealthForHostWithoutRecordedHealth() {
        let host = HostConfig(displayName: "Edge", address: "9.9.9.9")
        let runtimeSnapshot = RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [:],
            samplesByHost: [:]
        )

        let widgetSnapshot = WidgetSnapshot.make(
            from: runtimeSnapshot,
            generatedAt: Date(timeIntervalSince1970: 10)
        )

        let health = widgetSnapshot.health.first { $0.hostID == host.id }
        XCTAssertEqual(health?.status, .noData)
        XCTAssertNil(health?.latencyMilliseconds)
        XCTAssertEqual(health?.consecutiveFailureCount, 0)
        XCTAssertNil(health?.latestResultAt)
    }

    func testWidgetSnapshotLimitsSamplesPerHostAndSortsByTimestamp() {
        let host = HostConfig(displayName: "Edge", address: "9.9.9.9")
        var series = SampleSeries(hostID: host.id, capacity: 500)
        for index in 0..<5 {
            series.append(.success(
                hostID: host.id,
                latency: .milliseconds(Double(index + 1)),
                timestamp: Date(timeIntervalSince1970: Double(index))
            ))
        }

        let runtimeSnapshot = RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [:],
            samplesByHost: [host.id: series]
        )

        let widgetSnapshot = WidgetSnapshot.make(
            from: runtimeSnapshot,
            sampleLimitPerHost: 3,
            generatedAt: Date(timeIntervalSince1970: 100)
        )

        // Keeps the 3 newest samples per host (timestamps 2, 3, 4), sorted ascending.
        XCTAssertEqual(
            widgetSnapshot.recentSamples.map { $0.timestamp.timeIntervalSince1970 },
            [2, 3, 4]
        )
    }

    func testWidgetSnapshotContentComparisonIgnoresGeneratedAt() {
        let host = HostConfig(displayName: "Edge", address: "9.9.9.9")
        let runtimeSnapshot = RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [:],
            samplesByHost: [:]
        )

        let first = WidgetSnapshot.make(
            from: runtimeSnapshot,
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = WidgetSnapshot.make(
            from: runtimeSnapshot,
            generatedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasSameContent(as: second))
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

    /// The legacy `widgetData` blob is written with an ISO-8601 date encoder, so
    /// its only reader (the widget's fallback path) must decode with `.iso8601`.
    /// The default strategy always throws on the Date fields, which silently
    /// killed the widget's legacy fallback branch.
    func testLegacyWidgetBlobRoundTripsWithISO8601Decoder() async throws {
        let suiteName = "pingscope-widget-legacy-tests-\(UUID().uuidString)"
        let store = WidgetSnapshotStore(suiteName: suiteName, key: "snapshot")
        let inspectionDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { inspectionDefaults.removePersistentDomain(forName: suiteName) }
        let hostID = UUID()
        await store.save(WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [WidgetHost(id: hostID, displayName: "H", address: "1.1.1.1", method: .https, port: 443, isPrimary: true)],
            health: [WidgetHostHealth(hostID: hostID, status: .healthy, latencyMilliseconds: 7, consecutiveFailureCount: 0, failureReason: nil, latestResultAt: Date(timeIntervalSince1970: 6_000))],
            recentSamples: [],
            networkStatus: .connected,
            generatedAt: Date(timeIntervalSince1970: 6_001)
        ))

        let raw = try XCTUnwrap(inspectionDefaults.data(forKey: WidgetSnapshotStore.legacyKey))
        // Mirrors the widget target's WidgetData / Provider.loadLegacyData decoder.
        struct LegacyMirror: Decodable {
            struct Result: Decodable {
                var hostID: UUID
                var latencyMS: Double?
                var isSuccess: Bool
                var timestamp: Date
            }
            var results: [Result]
            var lastUpdate: Date
        }
        let widgetDecoder = JSONDecoder()
        widgetDecoder.dateDecodingStrategy = .iso8601

        let decoded = try widgetDecoder.decode(LegacyMirror.self, from: raw)
        XCTAssertEqual(decoded.lastUpdate, Date(timeIntervalSince1970: 6_001))
        XCTAssertEqual(decoded.results.map(\.hostID), [hostID])
        XCTAssertThrowsError(
            try JSONDecoder().decode(LegacyMirror.self, from: raw),
            "a default-strategy decoder must not silently pass; the widget must use .iso8601"
        )
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
        for _ in 0..<80 {
            if stored.count >= count {
                return stored
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return stored
    }
}

private struct HistoryExportDocumentProbe: Decodable {
    var host: HostConfig
    var samples: [PingResult]
}

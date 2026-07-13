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

    func testSQLiteHistoryStoreRejectsCorruptStoredLatenciesWithoutTrapping() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let store = SQLiteHistoryStore(url: url)
        let base = Date()
        await store.append(.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: base
        ).withHostMetadata(from: host))

        try insertRawLatencies(
            [-1, 3_600_001, .infinity],
            host: host,
            startingAt: base.addingTimeInterval(1),
            url: url
        )

        let samples = await store.samples(hostID: host.id, since: base, limit: 10)

        XCTAssertEqual(samples.count, 4)
        XCTAssertNotNil(samples[0].latency)
        XCTAssertTrue(samples.dropFirst().allSatisfy { $0.latency == nil })
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

    func testSQLiteHistoryStoreStoresJSONOnlyForStructuredMetadata() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let starlinkHost = HostConfig.defaultStarlinkDish
        let store = SQLiteHistoryStore(url: url)
        await store.append(.success(
            hostID: host.id,
            latency: .milliseconds(17),
            timestamp: Date(timeIntervalSince1970: 1_600),
            metadata: ProbeMetadata(note: "note-only")
        ).withHostMetadata(from: host))
        await store.append(.success(
            hostID: starlinkHost.id,
            latency: .milliseconds(38),
            timestamp: Date(timeIntervalSince1970: 1_601),
            metadata: ProbeMetadata(
                note: "state=CONNECTED",
                starlink: StarlinkTelemetry(state: "CONNECTED")
            )
        ).withHostMetadata(from: starlinkHost))

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        let noteOnlyJSON = try metadataJSON(hostID: host.id, db: db)
        let starlinkJSON = try metadataJSON(hostID: starlinkHost.id, db: db)

        XCTAssertNil(noteOnlyJSON)
        XCTAssertNotNil(starlinkJSON)
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

    func testSQLiteHistoryStoreFutureTimestampDoesNotPruneOtherHostsRecentHistory() async throws {
        let url = temporaryHistoryURL()
        let recentHost = HostConfig(displayName: "Recent", address: "recent.example.com")
        let futureHost = HostConfig(displayName: "Future", address: "future.example.com")
        let now = Date()
        let store = SQLiteHistoryStore(url: url, retention: .seconds(60))

        await store.append(.success(
            hostID: recentHost.id,
            latency: .milliseconds(10),
            timestamp: now.addingTimeInterval(-30)
        ).withHostMetadata(from: recentHost))
        await store.append(.success(
            hostID: futureHost.id,
            latency: .milliseconds(20),
            timestamp: now.addingTimeInterval(86_400)
        ).withHostMetadata(from: futureHost))

        let recentSamples = await store.samples(
            hostID: recentHost.id,
            since: now.addingTimeInterval(-60),
            limit: 10
        )

        XCTAssertEqual(recentSamples.count, 1)
        XCTAssertEqual(recentSamples.first?.latency?.milliseconds, 10)
    }

    func testSQLiteHistoryStoreReturnsLatestSamplesDescending() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let other = HostConfig(displayName: "Other", address: "other.example.com")
        let base = Date(timeIntervalSince1970: 10_000)
        let store = SQLiteHistoryStore(url: url)

        for index in 0..<5 {
            await store.append(.success(
                hostID: host.id,
                latency: .milliseconds(Double(index)),
                timestamp: base.addingTimeInterval(Double(index))
            ).withHostMetadata(from: host))
        }
        await store.append(.success(
            hostID: other.id,
            latency: .milliseconds(99),
            timestamp: base.addingTimeInterval(99)
        ).withHostMetadata(from: other))

        let latest = await store.latestSamples(hostID: host.id, since: base, limit: 3)

        XCTAssertEqual(latest.map { Int($0.timestamp.timeIntervalSince1970) }, [10_004, 10_003, 10_002])
        XCTAssertEqual(latest.map(\.hostID), Array(repeating: host.id, count: 3))
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

    func testHistoryWriteBufferFlushNowReturnsAfterPersistentFailure() async {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let history = FailingHistoryStore()
        let buffer = HistoryWriteBuffer(
            store: history,
            maxBatchSize: 10,
            flushDelay: .seconds(60)
        )
        await buffer.append(.success(hostID: host.id, latency: .milliseconds(19)).withHostMetadata(from: host))

        let flushed = expectation(description: "Forced history flush returned")
        Task {
            await buffer.flushNow()
            flushed.fulfill()
        }

        await fulfillment(of: [flushed], timeout: 1.0)
        let appendAttemptCount = await history.appendAttemptCount
        XCTAssertEqual(appendAttemptCount, 1)
        await buffer.discardPending()
    }

    func testBoundedBufferDropsOldestAndCountsOverflow() {
        var buffer = BoundedBuffer<Int>(capacity: 3)

        XCTAssertEqual(buffer.append(1), 0)
        XCTAssertEqual(buffer.append(2), 0)
        XCTAssertEqual(buffer.append(3), 0)
        XCTAssertEqual(buffer.append(4), 1)
        XCTAssertEqual(buffer.append(5), 1)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.droppedCount, 2)
        XCTAssertEqual(buffer.popPrefix(2), [3, 4])
        XCTAssertEqual(buffer.popPrefix(10), [5])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testBoundedBufferPopPrefixPreservesWrappedRemainderOrder() {
        var buffer = BoundedBuffer<Int>(capacity: 4)
        for value in 1...6 {
            buffer.append(value)
        }

        XCTAssertEqual(buffer.elements, [3, 4, 5, 6])
        XCTAssertEqual(buffer.popPrefix(2), [3, 4])
        XCTAssertEqual(buffer.elements, [5, 6])
        XCTAssertEqual(buffer.append(7), 0)
        XCTAssertEqual(buffer.append(8), 0)
        XCTAssertEqual(buffer.append(9), 1)
        XCTAssertEqual(buffer.elements, [6, 7, 8, 9])
        XCTAssertEqual(buffer.droppedCount, 3)
    }

    func testBoundedBufferSuffixWhileReturnsContiguousTailInOrder() {
        var buffer = BoundedBuffer<Int>(capacity: 5)
        for value in 1...5 {
            buffer.append(value)
        }

        XCTAssertEqual(buffer.suffix { $0 >= 3 }, [3, 4, 5])
        XCTAssertEqual(buffer.suffix { $0 >= 4 }, [4, 5])
        XCTAssertEqual(buffer.suffix { $0 > 5 }, [])
    }

    func testBoundedBufferSuffixWhileHandlesWrappedStorage() {
        var buffer = BoundedBuffer<Int>(capacity: 4)
        for value in 1...7 {
            buffer.append(value)
        }

        XCTAssertEqual(buffer.elements, [4, 5, 6, 7])
        XCTAssertEqual(buffer.suffix { $0 >= 5 }, [5, 6, 7])
        XCTAssertEqual(buffer.suffix { $0 >= 4 }, [4, 5, 6, 7])
        XCTAssertEqual(buffer.suffix { $0 >= 6 }, [6, 7])
    }

    func testBoundedBufferPrependRestoresWrappedPrefixWithoutReordering() {
        var buffer = BoundedBuffer<Int>(capacity: 4)
        for value in 1...6 {
            buffer.append(value)
        }
        XCTAssertEqual(buffer.popPrefix(2), [3, 4])

        buffer.prepend(contentsOf: [3, 4])

        XCTAssertEqual(buffer.elements, [3, 4, 5, 6])
        XCTAssertEqual(buffer.droppedCount, 2)
    }

    func testBoundedBufferPrependDropsTailWhenOverCapacity() {
        var buffer = BoundedBuffer<Int>(capacity: 4)
        for value in 1...6 {
            buffer.append(value)
        }
        XCTAssertEqual(buffer.popPrefix(1), [3])

        buffer.prepend(contentsOf: [1, 2, 3])

        XCTAssertEqual(buffer.elements, [1, 2, 3, 4])
        XCTAssertEqual(buffer.droppedCount, 4)
    }

    func testBoundedBufferCodableAndEqualityIncludeDroppedCount() throws {
        var dropped = BoundedBuffer<Int>(capacity: 2)
        dropped.append(1)
        dropped.append(2)
        dropped.append(3)

        var sameElementsWithoutDrop = BoundedBuffer(elements: [2, 3], capacity: 2)
        XCTAssertNotEqual(dropped, sameElementsWithoutDrop)
        sameElementsWithoutDrop.append(4)
        XCTAssertEqual(sameElementsWithoutDrop.droppedCount, 1)

        let encoded = try JSONEncoder().encode(dropped)
        let decoded = try JSONDecoder().decode(BoundedBuffer<Int>.self, from: encoded)

        XCTAssertEqual(decoded, dropped)
        XCTAssertEqual(decoded.droppedCount, 1)
    }

    func testBoundedBufferDecodesLegacyPayloadWithoutDroppedCount() throws {
        let data = Data(#"{"capacity":2,"elements":[1,2]}"#.utf8)

        let decoded = try JSONDecoder().decode(BoundedBuffer<Int>.self, from: data)

        XCTAssertEqual(decoded.elements, [1, 2])
        XCTAssertEqual(decoded.droppedCount, 0)
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

    func testHistoryExporterEscapesCSVFormulaCells() {
        let host = HostConfig(displayName: "=HYPERLINK(\"https://example.com\")", address: "example.com")
        let sample = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(18),
            timestamp: Date(timeIntervalSince1970: 1_000),
            metadata: ProbeMetadata(note: "@cmd")
        ).withHostMetadata(from: host)

        let csv = HistoryExporter.csv(samples: [sample], host: host)

        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"https://example.com\"\")\""))
        XCTAssertTrue(csv.contains(",'@cmd,"))
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

    func testWidgetSnapshotPublishPolicyReloadsInitialSnapshot() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        let snapshot = WidgetSnapshot.empty

        let decision = policy.decision(for: snapshot, previousSnapshot: nil, lastTimelineReloadAt: nil)

        XCTAssertTrue(decision.shouldSave)
        XCTAssertTrue(decision.shouldReloadTimeline)
    }

    func testWidgetSnapshotPublishPolicySkipsUnchangedFreshSnapshot() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        let previous = WidgetSnapshot.empty
        var current = previous
        current.generatedAt = previous.generatedAt.addingTimeInterval(60)

        let decision = policy.decision(for: current, previousSnapshot: previous, lastTimelineReloadAt: previous.generatedAt)

        XCTAssertFalse(decision.shouldSave)
        XCTAssertFalse(decision.shouldReloadTimeline)
    }

    func testWidgetSnapshotPublishPolicyIgnoresLatencyButPublishesStatusChanges() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        let hostID = UUID()
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let previous = WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [WidgetHost(id: hostID, displayName: "Edge", address: "1.1.1.1", method: .tcp, port: 443, isPrimary: true)],
            health: [WidgetHostHealth(hostID: hostID, status: .healthy, latencyMilliseconds: 12, consecutiveFailureCount: 0, failureReason: nil, latestResultAt: generatedAt)],
            recentSamples: [],
            networkStatus: .connected,
            generatedAt: generatedAt
        )
        var latencyOnly = previous
        latencyOnly.generatedAt = generatedAt.addingTimeInterval(60)
        latencyOnly.health[0].latencyMilliseconds = 34
        latencyOnly.health[0].latestResultAt = latencyOnly.generatedAt
        latencyOnly.health[0].consecutiveFailureCount = 1
        var failed = latencyOnly
        failed.health[0].status = .down
        failed.health[0].failureReason = .timeout

        let latencyDecision = policy.decision(
            for: latencyOnly,
            previousSnapshot: previous,
            lastTimelineReloadAt: generatedAt
        )
        let failureDecision = policy.decision(
            for: failed,
            previousSnapshot: previous,
            lastTimelineReloadAt: generatedAt
        )

        XCTAssertFalse(latencyDecision.shouldSave)
        XCTAssertFalse(latencyDecision.shouldReloadTimeline)
        XCTAssertTrue(failureDecision.shouldSave)
        XCTAssertTrue(failureDecision.shouldReloadTimeline)
    }

    func testWidgetSnapshotPublishPolicySavesHeartbeatWithoutReloadingTimeline() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        let previous = WidgetSnapshot.empty
        var current = previous
        current.generatedAt = previous.generatedAt.addingTimeInterval(301)

        let decision = policy.decision(for: current, previousSnapshot: previous, lastTimelineReloadAt: previous.generatedAt)

        XCTAssertTrue(decision.shouldSave)
        XCTAssertFalse(decision.shouldReloadTimeline)
    }

    func testWidgetSnapshotPublishPolicyThrottlesSampleOnlyChanges() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        var previous = WidgetSnapshot.empty
        previous.generatedAt = Date(timeIntervalSince1970: 1_000)
        var current = previous
        current.generatedAt = previous.generatedAt.addingTimeInterval(60)
        current.recentSamples = [
            WidgetSample(result: PingResult(
                id: UUID(),
                hostID: UUID(),
                timestamp: current.generatedAt,
                latency: .milliseconds(20),
                failureReason: nil
            ))
        ]

        let decision = policy.decision(for: current, previousSnapshot: previous, lastTimelineReloadAt: previous.generatedAt)

        XCTAssertFalse(decision.shouldSave)
        XCTAssertFalse(decision.shouldReloadTimeline)
    }

    func testWidgetSnapshotPublishPolicySavesAndReloadsCoalescedSampleChanges() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        var previous = WidgetSnapshot.empty
        previous.generatedAt = Date(timeIntervalSince1970: 1_000)
        var current = previous
        current.generatedAt = previous.generatedAt.addingTimeInterval(301)
        current.recentSamples = [
            WidgetSample(result: PingResult(
                id: UUID(),
                hostID: UUID(),
                timestamp: current.generatedAt,
                latency: .milliseconds(20),
                failureReason: nil
            ))
        ]

        let decision = policy.decision(for: current, previousSnapshot: previous, lastTimelineReloadAt: previous.generatedAt)

        XCTAssertTrue(decision.shouldSave)
        XCTAssertTrue(decision.shouldReloadTimeline)
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

    func testWidgetSnapshotStoreDoesNotRewriteExistingLegacyBlob() async throws {
        let suiteName = "pingscope-widget-legacy-once-tests-\(UUID().uuidString)"
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
        let firstLegacyBlob = try XCTUnwrap(inspectionDefaults.data(forKey: WidgetSnapshotStore.legacyKey))

        await store.save(WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [WidgetHost(id: hostID, displayName: "H", address: "1.1.1.1", method: .https, port: 443, isPrimary: true)],
            health: [WidgetHostHealth(hostID: hostID, status: .healthy, latencyMilliseconds: 11, consecutiveFailureCount: 0, failureReason: nil, latestResultAt: Date(timeIntervalSince1970: 7_000))],
            recentSamples: [],
            networkStatus: .connected,
            generatedAt: Date(timeIntervalSince1970: 7_001)
        ))

        XCTAssertEqual(inspectionDefaults.data(forKey: WidgetSnapshotStore.legacyKey), firstLegacyBlob)
    }

    private func temporaryHistoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pingscope-history-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("History.sqlite")
    }

    private func metadataJSON(hostID: UUID, db: OpaquePointer?) throws -> String? {
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(db, "SELECT metadata_json FROM ping_samples WHERE host_id = ?;", -1, &statement, nil),
            SQLITE_OK
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, hostID.uuidString, -1, sqliteTransientForTests)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        guard let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    private func insertRawLatencies(
        _ latencies: [Double],
        host: HostConfig,
        startingAt timestamp: Date,
        url: URL
    ) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        INSERT INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        for (index, latency) in latencies.enumerated() {
            sqlite3_bind_text(statement, 1, UUID().uuidString, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 2, host.id.uuidString, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 3, host.address, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 4, host.method.rawValue, -1, sqliteTransientForTests)
            if let port = host.port {
                sqlite3_bind_int64(statement, 5, Int64(port))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_double(statement, 6, timestamp.addingTimeInterval(Double(index)).timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, latency)
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }
}

private let sqliteTransientForTests = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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

    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        Array(stored
            .filter { $0.hostID == hostID && $0.timestamp >= since }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(1, limit)))
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

private actor FailingHistoryStore: PingHistoryStore {
    private(set) var appendAttemptCount = 0

    enum Failure: Error {
        case unavailable
    }

    func append(_ result: PingResult) async {
        appendAttemptCount += 1
    }

    func appendAndWait(_ results: [PingResult]) async throws {
        appendAttemptCount += 1
        throw Failure.unavailable
    }

    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        []
    }

    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        []
    }

    func prune(olderThan cutoff: Date) async {}

    func deleteAll() async {}
}

private struct HistoryExportDocumentProbe: Decodable {
    var host: HostConfig
    var samples: [PingResult]
}

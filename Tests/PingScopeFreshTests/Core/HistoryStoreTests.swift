import XCTest
import SQLite3
@testable import PingScopeCore

final class HistoryStoreTests: XCTestCase {
    func testSQLiteHistoryStoreRoundTripsLocatedAndUnlocatedSamples() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 900)
        let location = try XCTUnwrap(SampleLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            horizontalAccuracy: 12.5,
            networkName: "Wi-Fi",
            networkInterface: "wifi"
        ))
        let store = SQLiteHistoryStore(url: url)

        await store.append(.success(
            hostID: host.id,
            latency: .milliseconds(12),
            timestamp: base,
            location: location,
            networkInterface: "wifi",
            networkName: "Office Wi-Fi",
            isVPN: true
        ).withHostMetadata(from: host))
        await store.append(.failure(
            hostID: host.id,
            reason: .timeout,
            timestamp: base.addingTimeInterval(1)
        ).withHostMetadata(from: host))

        let samples = await SQLiteHistoryStore(url: url).samples(
            hostID: host.id,
            since: base.addingTimeInterval(-1),
            limit: 10
        )

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].location, location)
        XCTAssertEqual(samples[0].networkInterface, "wifi")
        XCTAssertEqual(samples[0].networkName, "Office Wi-Fi")
        XCTAssertTrue(samples[0].isVPN)
        XCTAssertNil(samples[1].location)
        XCTAssertNil(samples[1].networkInterface)
        XCTAssertNil(samples[1].networkName)
        XCTAssertFalse(samples[1].isVPN)
    }

    func testSQLiteHistoryStoreMigratesLegacySchemaAndReadsOldRowsWithoutLocation() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Legacy", address: "legacy.example.com")
        let timestamp = Date(timeIntervalSince1970: 950)
        try createLegacyHistoryDatabase(url: url, host: host, timestamp: timestamp)

        let store = SQLiteHistoryStore(url: url)
        let samples = await store.samples(hostID: host.id, since: timestamp.addingTimeInterval(-1), limit: 10)

        XCTAssertEqual(samples.count, 1)
        XCTAssertNil(samples[0].location)
        XCTAssertNil(samples[0].networkInterface)
        XCTAssertNil(samples[0].networkName)
        XCTAssertFalse(samples[0].isVPN)
        XCTAssertEqual(try historyColumnNames(url: url).intersection([
            "latitude", "longitude", "horizontal_accuracy", "network_name", "network_interface",
            "network_interface_top", "network_name_top", "is_vpn"
        ]).count, 8)
    }

    func testSQLiteHistoryStoreKeepsRowsWithPartialOrCorruptCoordinates() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 975)
        let store = SQLiteHistoryStore(url: url)
        await store.append(.success(hostID: host.id, latency: .milliseconds(10), timestamp: base).withHostMetadata(from: host))
        try insertRawLocations(host: host, startingAt: base.addingTimeInterval(1), url: url)

        let samples = await store.samples(hostID: host.id, since: base, limit: 10)

        XCTAssertEqual(samples.count, 4)
        XCTAssertTrue(samples.allSatisfy { $0.location == nil })
        XCTAssertTrue(samples.allSatisfy { $0.latency != nil })
    }

    func testSQLiteHistoryStoreRetentionIsConfiguredPerStore() async throws {
        let defaultURL = temporaryHistoryURL()
        let thirtyDayURL = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let now = Date()
        let twentyDaysAgo = now.addingTimeInterval(-20 * 86_400)
        let defaultStore = SQLiteHistoryStore(url: defaultURL)
        let thirtyDayStore = SQLiteHistoryStore(url: thirtyDayURL, retention: .days(30))

        for store in [defaultStore, thirtyDayStore] {
            await store.append(.success(hostID: host.id, latency: .milliseconds(20), timestamp: twentyDaysAgo).withHostMetadata(from: host))
            await store.append(.success(hostID: host.id, latency: .milliseconds(1), timestamp: now).withHostMetadata(from: host))
        }

        let defaultSamples = await defaultStore.samples(hostID: host.id, since: twentyDaysAgo.addingTimeInterval(-1), limit: 10)
        let thirtyDaySamples = await thirtyDayStore.samples(hostID: host.id, since: twentyDaysAgo.addingTimeInterval(-1), limit: 10)

        XCTAssertEqual(defaultSamples.count, 1)
        XCTAssertEqual(thirtyDaySamples.count, 2)
    }

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

    func testLocalBatchRetentionPrunePreservesBackfilledRowsInsertedInSameBatch() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Backfill", address: "backfill.example.com")
        let now = Date()
        let backfilled = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(40),
            timestamp: now.addingTimeInterval(-8 * 86_400)
        ).withHostMetadata(from: host)
        let preexistingExpired = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(60),
            timestamp: now.addingTimeInterval(-9 * 86_400)
        ).withHostMetadata(from: host)
        let current = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: now
        ).withHostMetadata(from: host)
        do {
            let seedingStore = SQLiteHistoryStore(url: url, retention: .days(30))
            try await seedingStore.appendAndWait([preexistingExpired])
        }
        let store = SQLiteHistoryStore(url: url, retention: .days(7))

        try await store.appendAndWait([backfilled, current])

        let persisted = await store.samples(
            hostID: host.id,
            since: backfilled.timestamp.addingTimeInterval(-1),
            limit: 10
        )
        let revision = await store.historyRevision()
        XCTAssertEqual(Set(persisted.map(\.id)), Set([backfilled.id, current.id]))
        XCTAssertFalse(persisted.contains { $0.id == preexistingExpired.id })
        XCTAssertEqual(revision, 1)
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

    func testSQLiteHistoryStoreLoadsOrderedWeeklyInputsForMultipleHostsInOneRequest() async throws {
        let url = temporaryHistoryURL()
        let first = HostConfig(displayName: "First", address: "first.example.com")
        let second = HostConfig(displayName: "Second", address: "second.example.com")
        let ignored = HostConfig(displayName: "Ignored", address: "ignored.example.com")
        let endingAt = Date(timeIntervalSince1970: 50_000)
        let store = SQLiteHistoryStore(url: url, retention: .days(30))
        var firstSuccess = PingResult.success(
            hostID: first.id,
            latency: .milliseconds(10),
            timestamp: endingAt.addingTimeInterval(-20),
            networkInterface: "wifi",
            networkName: "Office"
        ).withHostMetadata(from: first)
        firstSuccess.metadata = ProbeMetadata(
            starlink: StarlinkTelemetry(state: "CONNECTED", popPingDropRate: 0.25)
        )
        let rows = [
            PingResult.failure(
                hostID: second.id,
                reason: .timeout,
                timestamp: endingAt.addingTimeInterval(-10),
                networkInterface: "cellular"
            ).withHostMetadata(from: second),
            firstSuccess,
            PingResult.success(
                hostID: ignored.id,
                latency: .milliseconds(99),
                timestamp: endingAt.addingTimeInterval(-5)
            ).withHostMetadata(from: ignored),
            PingResult.success(
                hostID: first.id,
                latency: .milliseconds(20),
                timestamp: endingAt.addingTimeInterval(-30)
            ).withHostMetadata(from: first)
        ]
        try await store.appendAndWait(rows)

        let revision = await store.historyRevision()
        let inputs = await store.weeklyDigestSamples(
            hostIDs: [second.id, first.id],
            since: endingAt.addingTimeInterval(-100),
            through: endingAt
        )

        let expected = [rows[0], firstSuccess, rows[3]].sorted { lhs, rhs in
            if lhs.hostID != rhs.hostID { return lhs.hostID.uuidString < rhs.hostID.uuidString }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        XCTAssertGreaterThan(revision, 0)
        XCTAssertEqual(inputs.map(\.id), expected.map(\.id))
        XCTAssertEqual(inputs.map(\.hostID), expected.map(\.hostID))
        let starlinkInput = try XCTUnwrap(inputs.first { $0.id == firstSuccess.id })
        XCTAssertEqual(starlinkInput.lossFractionOverride, 0.25)
        XCTAssertEqual(starlinkInput.networkInterface, "wifi")
        XCTAssertEqual(starlinkInput.networkName, "Office")
        XCTAssertFalse(try XCTUnwrap(inputs.first { $0.id == rows[0].id }).isSuccess)
    }

    func testSQLiteHistoryStoreChunksWeeklyHostBindsAtConnectionVariableLimit() async throws {
        let url = temporaryHistoryURL()
        let base = Date(timeIntervalSince1970: 55_000)
        let hosts = (0..<7).map { index in
            HostConfig(displayName: "Host \(index)", address: "host-\(index).example.com")
        }
        let rows = hosts.enumerated().flatMap { index, host in
            [
                PingResult.success(
                    hostID: host.id,
                    latency: .milliseconds(Double(index + 1)),
                    timestamp: base.addingTimeInterval(Double(index % 3)),
                    networkInterface: index.isMultiple(of: 2) ? "wifi" : "cellular"
                ).withHostMetadata(from: host),
                PingResult.failure(
                    hostID: host.id,
                    reason: .timeout,
                    timestamp: base.addingTimeInterval(Double(index % 3))
                ).withHostMetadata(from: host)
            ]
        }
        let store = SQLiteHistoryStore(
            url: url,
            retention: .days(30),
            sqliteVariableNumberLimitForTesting: 5
        )
        try await store.appendAndWait(rows.reversed())

        let inputs = await store.weeklyDigestSamples(
            hostIDs: hosts.map(\.id) + [hosts[0].id, hosts[6].id],
            since: base.addingTimeInterval(-1),
            through: base.addingTimeInterval(10)
        )
        let expected = rows.sorted { lhs, rhs in
            if lhs.hostID != rhs.hostID { return lhs.hostID.uuidString < rhs.hostID.uuidString }
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        XCTAssertEqual(inputs.map(\.id), expected.map(\.id))
        XCTAssertEqual(inputs.count, rows.count)
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

    func testSQLiteHistoryStoreUsesUnsyncedTimestampIndexForSyncQueue() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let store = SQLiteHistoryStore(url: url)

        await store.append(.success(hostID: host.id, latency: .milliseconds(10)).withHostMetadata(from: host))

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        let plan = try queryPlanDetails(
            db: db,
            sql: """
            EXPLAIN QUERY PLAN
            SELECT id FROM ping_samples
            WHERE synced = 0
            ORDER BY timestamp DESC
            LIMIT 300;
            """
        )

        XCTAssertTrue(plan.contains { $0.contains("ping_samples_unsynced_time") }, plan.joined(separator: "\n"))
        XCTAssertFalse(plan.contains { $0.contains("USE TEMP B-TREE") }, plan.joined(separator: "\n"))
    }

    func testSQLiteHistoryStoreMarksSyncBatchAtomicallyWhenAnUpdateFails() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 20_000)
        let samples = (0..<3).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset + 1)),
                timestamp: base.addingTimeInterval(Double(offset))
            ).withHostMetadata(from: host)
        }
        let store = SQLiteHistoryStore(url: url)
        try await store.appendAndWait(samples)
        try installFailingSyncMarkTrigger(url: url, sampleID: samples[1].id)

        do {
            try await store.markSamplesSynced(ids: samples.map(\.id))
            XCTFail("Expected the forced middle update to fail")
        } catch {}

        let unsynced = try await store.unsyncedSamples(limit: 10)
        XCTAssertEqual(Set(unsynced.map(\.id)), Set(samples.map(\.id)))
    }

    func testSQLiteHistoryStoreIgnoresDuplicateLocalIDButRemoteUpsertReplacesIt() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let sampleID = UUID()
        let base = Date(timeIntervalSince1970: 25_000)
        let original = PingResult(
            id: sampleID,
            hostID: host.id,
            timestamp: base,
            latency: .milliseconds(10),
            failureReason: nil
        ).withHostMetadata(from: host)
        let localDuplicate = PingResult(
            id: sampleID,
            hostID: host.id,
            timestamp: base.addingTimeInterval(1),
            latency: .milliseconds(20),
            failureReason: nil
        ).withHostMetadata(from: host)
        let remoteReplacement = PingResult(
            id: sampleID,
            hostID: host.id,
            timestamp: base.addingTimeInterval(2),
            latency: .milliseconds(30),
            failureReason: nil
        ).withHostMetadata(from: host)
        let store = SQLiteHistoryStore(url: url)

        try await store.appendAndWait([original])
        try await store.appendAndWait([localDuplicate])

        var stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)
        XCTAssertEqual(stored.map(\.id), [sampleID])
        XCTAssertEqual(try XCTUnwrap(stored.first?.latency).milliseconds, 10, accuracy: 0.01)

        try await store.upsertRemoteSamples([remoteReplacement])

        stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)
        XCTAssertEqual(stored.map(\.id), [sampleID])
        XCTAssertEqual(try XCTUnwrap(stored.first?.latency).milliseconds, 30, accuracy: 0.01)
        let unsynced = try await store.unsyncedSamples(limit: 10)
        XCTAssertTrue(unsynced.isEmpty)
    }

    func testRemoteUpsertChunksLargeBackfillAndAdvancesRevisionPerCommittedChunk() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Remote", address: "remote.example.com")
        let base = Date(timeIntervalSince1970: 30_000)
        let samples = (0..<1_205).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset % 100)),
                timestamp: base.addingTimeInterval(Double(offset))
            ).withHostMetadata(from: host)
        }
        let transactions = SQLiteTransactionObservation()
        let store = SQLiteHistoryStore(
            url: url,
            remoteUpsertChunkSizeForTesting: 500,
            transactionObserverForTesting: transactions.record
        )

        try await store.upsertRemoteSamples(samples)

        let stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 2_000)
        XCTAssertEqual(Set(stored.map(\.id)), Set(samples.map(\.id)))
        XCTAssertEqual(
            transactions.events,
            [.beginImmediate, .commit, .beginImmediate, .commit, .beginImmediate, .commit]
        )
        let revision = await store.historyRevision()
        XCTAssertEqual(revision, 3)
    }

    func testRemoteUpsertFailureKeepsPriorChunksAndRetryConverges() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Remote", address: "remote.example.com")
        let base = Date(timeIntervalSince1970: 40_000)
        let samples = (0..<1_205).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset % 100)),
                timestamp: base.addingTimeInterval(Double(offset))
            ).withHostMetadata(from: host)
        }
        let failedTransactions = SQLiteTransactionObservation()
        let failingStore = SQLiteHistoryStore(
            url: url,
            remoteUpsertChunkSizeForTesting: 500,
            failingRemoteUpsertChunkForTesting: 1,
            transactionObserverForTesting: failedTransactions.record
        )

        do {
            try await failingStore.upsertRemoteSamples(samples)
            XCTFail("Expected the second remote-upsert chunk to fail")
        } catch {}

        var stored = await failingStore.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 2_000)
        XCTAssertEqual(Set(stored.map(\.id)), Set(samples.prefix(500).map(\.id)))
        XCTAssertEqual(failedTransactions.events, [.beginImmediate, .commit])
        let failedRevision = await failingStore.historyRevision()
        XCTAssertEqual(failedRevision, 1)

        let retryTransactions = SQLiteTransactionObservation()
        let retryStore = SQLiteHistoryStore(
            url: url,
            remoteUpsertChunkSizeForTesting: 500,
            transactionObserverForTesting: retryTransactions.record
        )
        try await retryStore.upsertRemoteSamples(samples)

        stored = await retryStore.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 2_000)
        XCTAssertEqual(Set(stored.map(\.id)), Set(samples.map(\.id)))
        XCTAssertEqual(retryTransactions.events.count, 6)
        let retryRevision = await retryStore.historyRevision()
        XCTAssertEqual(retryRevision, 3)
    }

    func testSQLiteHistoryStoreSkipsDuplicateWithoutRollingBackFreshRows() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 26_000)
        let original = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: base
        ).withHostMetadata(from: host)
        let fresh = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(20),
            timestamp: base.addingTimeInterval(1)
        ).withHostMetadata(from: host)
        let duplicate = PingResult(
            id: original.id,
            hostID: host.id,
            timestamp: base.addingTimeInterval(2),
            latency: .milliseconds(30),
            failureReason: nil
        ).withHostMetadata(from: host)
        let store = SQLiteHistoryStore(url: url)
        try await store.appendAndWait([original])

        try await store.appendAndWait([duplicate, fresh])

        let stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)
        XCTAssertEqual(Set(stored.map(\.id)), Set([original.id, fresh.id]))
        XCTAssertEqual(stored.first(where: { $0.id == original.id })?.latency?.milliseconds, 10)
    }

    func testIgnoredFutureDuplicateDoesNotAdvanceRetentionPruneAnchor() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let now = Date()
        let original = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: now.addingTimeInterval(-90)
        ).withHostMetadata(from: host)
        let futureDuplicate = PingResult(
            id: original.id,
            hostID: host.id,
            timestamp: now.addingTimeInterval(86_400),
            latency: .milliseconds(20),
            failureReason: nil
        ).withHostMetadata(from: host)
        let store = SQLiteHistoryStore(url: url, retention: .seconds(60))
        try await store.appendAndWait([original])

        try await store.appendAndWait([futureDuplicate])

        let stored = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(stored.map(\.id), [original.id])
    }

    func testLocalAppendRetentionFailureRollsBackAndCanBeRetried() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date()
        let expired = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(5),
            timestamp: base.addingTimeInterval(-120)
        ).withHostMetadata(from: host)
        let candidate = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: base
        ).withHostMetadata(from: host)
        let later = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(15),
            timestamp: base.addingTimeInterval(1)
        ).withHostMetadata(from: host)
        let transactions = SQLiteTransactionObservation()
        let store = SQLiteHistoryStore(
            url: url,
            retention: .seconds(60),
            transactionObserverForTesting: transactions.record
        )
        _ = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        try insertRawHistorySample(expired, url: url)
        try installFailingHistoryPruneTrigger(url: url)

        var appendFailed = false
        do {
            try await store.appendAndWait([candidate])
        } catch {
            appendFailed = true
        }

        XCTAssertTrue(appendFailed)
        XCTAssertEqual(transactions.events, [.beginImmediate, .rollback])
        var revision = await store.historyRevision()
        XCTAssertEqual(revision, 0)
        var stored = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(stored.map(\.id), [expired.id])

        try removeFailingHistoryPruneTrigger(url: url)
        try await store.appendAndWait([candidate])

        XCTAssertEqual(transactions.events, [.beginImmediate, .rollback, .beginImmediate, .commit])
        revision = await store.historyRevision()
        XCTAssertEqual(revision, 1)
        stored = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(stored.map(\.id), [candidate.id])

        try await store.appendAndWait([later])

        XCTAssertEqual(
            transactions.events,
            [.beginImmediate, .rollback, .beginImmediate, .commit, .beginImmediate, .commit]
        )
        revision = await store.historyRevision()
        XCTAssertEqual(revision, 2)
        stored = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(Set(stored.map(\.id)), Set([candidate.id, later.id]))
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

    func testHistoryWriteBufferFlushesPendingSamplesInOneStoreBatch() async {
        let host = HostConfig(displayName: "Example", address: "example.com")
        let history = BatchRecordingHistoryStore()
        let buffer = HistoryWriteBuffer(
            store: history,
            maxBatchSize: 10,
            flushDelay: .seconds(60)
        )
        let samples = (0..<6).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset + 1))
            ).withHostMetadata(from: host)
        }
        for sample in samples {
            await buffer.append(sample)
        }

        await buffer.flushNow()

        let batches = await history.recordedBatches()
        XCTAssertEqual(batches.map { $0.map(\.id) }, [samples.map(\.id)])
    }

    func testHistoryWriteBufferSkipsDuplicateAndContinuesWithFreshRow() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date(timeIntervalSince1970: 26_500)
        let original = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(10),
            timestamp: base
        ).withHostMetadata(from: host)
        let duplicate = PingResult(
            id: original.id,
            hostID: host.id,
            timestamp: base.addingTimeInterval(1),
            latency: .milliseconds(20),
            failureReason: nil
        ).withHostMetadata(from: host)
        let fresh = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(30),
            timestamp: base.addingTimeInterval(2)
        ).withHostMetadata(from: host)
        let store = SQLiteHistoryStore(url: url)
        try await store.appendAndWait([original])
        let buffer = HistoryWriteBuffer(store: store, maxBatchSize: 10, flushDelay: .seconds(60))
        await buffer.append(duplicate)
        await buffer.append(fresh)

        await buffer.flushNow()
        await buffer.flushNow()

        let stored = await store.samples(hostID: host.id, since: base.addingTimeInterval(-1), limit: 10)
        let diagnostics = await buffer.diagnosticsForTesting()
        XCTAssertEqual(Set(stored.map(\.id)), Set([original.id, fresh.id]))
        XCTAssertEqual(stored.first(where: { $0.id == original.id })?.latency?.milliseconds, 10)
        XCTAssertEqual(diagnostics.pendingCount, 0)
        XCTAssertEqual(diagnostics.consecutiveFailureCount, 0)
    }

    func testHistoryWriteBufferFlushUsesOneSQLiteTransactionForOneBatch() async throws {
        let url = temporaryHistoryURL()
        let host = HostConfig(displayName: "Example", address: "example.com")
        let base = Date()
        let transactions = SQLiteTransactionObservation()
        let store = SQLiteHistoryStore(
            url: url,
            retention: .seconds(60),
            transactionObserverForTesting: transactions.record
        )
        let buffer = HistoryWriteBuffer(
            store: store,
            maxBatchSize: 10,
            flushDelay: .seconds(60)
        )
        let expired = PingResult.success(
            hostID: host.id,
            latency: .milliseconds(1),
            timestamp: base.addingTimeInterval(-120)
        ).withHostMetadata(from: host)
        let retained = (0..<5).map { offset in
            PingResult.success(
                hostID: host.id,
                latency: .milliseconds(Double(offset + 2)),
                timestamp: base.addingTimeInterval(Double(offset))
            ).withHostMetadata(from: host)
        }
        let samples = [expired] + retained
        for sample in samples {
            await buffer.append(sample)
        }

        await buffer.flushNow()

        XCTAssertEqual(transactions.events, [.beginImmediate, .commit])
        let persisted = await store.samples(hostID: host.id, since: .distantPast, limit: 10)
        XCTAssertEqual(
            persisted.map(\.id).sorted { $0.uuidString < $1.uuidString },
            samples.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
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

    func testWidgetSnapshotEncodesResolvedAdaptiveColorsForCustomAndAutomaticHosts() throws {
        let custom = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Custom",
            address: "custom.example",
            displayColor: HostDisplayColor(red: 0.2, green: 0.4, blue: 0.8)
        )
        let automatic = HostConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            displayName: "Automatic",
            address: "automatic.example"
        )
        let snapshot = WidgetSnapshot.make(from: RuntimeSnapshot(
            hosts: [custom, automatic],
            primaryHostID: custom.id,
            healthByHost: [:],
            samplesByHost: [:]
        ))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let encodedHosts = try XCTUnwrap(object["hosts"] as? [[String: Any]])

        XCTAssertEqual(encodedHosts.count, 2)
        for (host, encodedHost) in zip([custom, automatic], encodedHosts) {
            let encodedColor = try XCTUnwrap(encodedHost["displayColor"] as? [String: Any])
            let expected = ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
            assertEncodedRGB(encodedColor["light"], equals: expected.components(for: .light))
            assertEncodedRGB(encodedColor["dark"], equals: expected.components(for: .dark))
        }
    }

    func testWidgetSnapshotKeepsEveryEnabledHostInSavedOrderWithoutPresentationCap() {
        var hosts = (0..<7).map { index in
            HostConfig(
                id: UUID(),
                displayName: "Host \(index + 1)",
                address: "host-\(index + 1).example"
            )
        }
        hosts[2].isEnabled = false
        let enabledHosts = hosts.filter(\.isEnabled)
        let snapshot = WidgetSnapshot.make(from: RuntimeSnapshot(
            hosts: hosts,
            primaryHostID: hosts[2].id,
            healthByHost: [:],
            samplesByHost: [:]
        ))

        XCTAssertEqual(snapshot.hosts.map(\.id), enabledHosts.map(\.id))
        XCTAssertEqual(snapshot.hosts.count, 6, "transport must not apply the five-host presentation cap")
        XCTAssertEqual(snapshot.primaryHostID, enabledHosts.first?.id)
        XCTAssertEqual(snapshot.hosts.filter(\.isPrimary).map(\.id), [enabledHosts[0].id])
    }

    func testWidgetSnapshotDecodesHostsWithoutDisplayColor() throws {
        let host = HostConfig(displayName: "Legacy", address: "legacy.example")
        let snapshot = WidgetSnapshot.make(from: RuntimeSnapshot(
            hosts: [host],
            primaryHostID: host.id,
            healthByHost: [:],
            samplesByHost: [:]
        ))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var hosts = try XCTUnwrap(object["hosts"] as? [[String: Any]])
        hosts[0].removeValue(forKey: "displayColor")
        object["hosts"] = hosts
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WidgetSnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.hosts.map(\.id), [host.id])
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

    private func assertEncodedRGB(
        _ encodedValue: Any?,
        equals expected: HostDisplayColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let encoded = encodedValue as? [String: Any],
              let red = encoded["red"] as? Double,
              let green = encoded["green"] as? Double,
              let blue = encoded["blue"] as? Double else {
            XCTFail("Expected encoded RGB object", file: file, line: line)
            return
        }
        XCTAssertEqual(red, expected.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(green, expected.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(blue, expected.blue, accuracy: 0.000_001, file: file, line: line)
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
        XCTAssertTrue(decision.shouldReloadControls)
    }

    func testWidgetSnapshotPublishPolicyReloadsControlsOnlyForControlRelevantState() {
        let policy = WidgetSnapshotPublishPolicy(heartbeatInterval: 300, timelineReloadInterval: 300)
        let hostID = UUID()
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let previous = WidgetSnapshot(
            primaryHostID: hostID,
            hosts: [WidgetHost(id: hostID, displayName: "Edge", address: "1.1.1.1", method: .tcp, port: 443, isPrimary: true)],
            health: [WidgetHostHealth(hostID: hostID, status: .healthy, latencyMilliseconds: 12, consecutiveFailureCount: 0, failureReason: nil, latestResultAt: generatedAt)],
            recentSamples: [],
            networkStatus: .connected,
            generatedAt: generatedAt,
            monitoring: WidgetMonitoringContext(isActive: true, scope: .focused)
        )
        var latencyOnly = previous
        latencyOnly.generatedAt = generatedAt.addingTimeInterval(301)
        latencyOnly.health[0].latencyMilliseconds = 34
        latencyOnly.health[0].latestResultAt = latencyOnly.generatedAt
        var statusChanged = latencyOnly
        statusChanged.health[0].status = .down
        var scopeChanged = latencyOnly
        scopeChanged.monitoring = WidgetMonitoringContext(isActive: true, scope: .allHosts)

        XCTAssertFalse(policy.decision(for: latencyOnly, previousSnapshot: previous, lastTimelineReloadAt: generatedAt).shouldReloadControls)
        XCTAssertTrue(policy.decision(for: statusChanged, previousSnapshot: previous, lastTimelineReloadAt: generatedAt).shouldReloadControls)
        XCTAssertTrue(policy.decision(for: scopeChanged, previousSnapshot: previous, lastTimelineReloadAt: generatedAt).shouldReloadControls)
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

    private func createLegacyHistoryDatabase(url: URL, host: HostConfig, timestamp: Date) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        let createSQL = """
        CREATE TABLE ping_samples (
            id TEXT PRIMARY KEY, host_id TEXT NOT NULL, address TEXT NOT NULL, method TEXT NOT NULL,
            port INTEGER, timestamp REAL NOT NULL, latency_ms REAL, failure_reason TEXT,
            metadata_note TEXT, metadata_json TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)
        let insertSQL = """
        INSERT INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, UUID().uuidString, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 2, host.id.uuidString, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 3, host.address, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 4, host.method.rawValue, -1, sqliteTransientForTests)
        sqlite3_bind_int64(statement, 5, Int64(host.port ?? 443))
        sqlite3_bind_double(statement, 6, timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, 15)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private func historyColumnNames(url: URL) throws -> Set<String> {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA table_info('ping_samples');", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: text))
            }
        }
        return names
    }

    private func queryPlanDetails(db: OpaquePointer?, sql: String) throws -> [String] {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var details: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 3) {
                details.append(String(cString: text))
            }
        }
        return details
    }

    private func installFailingSyncMarkTrigger(url: URL, sampleID: UUID) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TRIGGER fail_sync_mark
        BEFORE UPDATE OF synced ON ping_samples
        WHEN NEW.id = '\(sampleID.uuidString)'
        BEGIN
            SELECT RAISE(ABORT, 'forced sync mark failure');
        END;
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertRawHistorySample(_ sample: PingResult, url: URL) throws {
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
        sqlite3_bind_text(statement, 1, sample.id.uuidString, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 2, sample.hostID.uuidString, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 3, sample.address, -1, sqliteTransientForTests)
        sqlite3_bind_text(statement, 4, sample.method.rawValue, -1, sqliteTransientForTests)
        if let port = sample.port {
            sqlite3_bind_int64(statement, 5, Int64(port))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_double(statement, 6, sample.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 7, try XCTUnwrap(sample.latency).milliseconds)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private func installFailingHistoryPruneTrigger(url: URL) throws {
        try executeHistorySQL(
            """
            CREATE TRIGGER fail_history_prune
            BEFORE DELETE ON ping_samples
            BEGIN
                SELECT RAISE(ABORT, 'forced history prune failure');
            END;
            """,
            url: url
        )
    }

    private func removeFailingHistoryPruneTrigger(url: URL) throws {
        try executeHistorySQL("DROP TRIGGER fail_history_prune;", url: url)
    }

    private func executeHistorySQL(_ sql: String, url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertRawLocations(host: HostConfig, startingAt timestamp: Date, url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        INSERT INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms, latitude, longitude)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let coordinates: [(Double?, Double?)] = [(37, nil), (91, -122), (37, 181)]
        for (index, coordinates) in coordinates.enumerated() {
            sqlite3_bind_text(statement, 1, UUID().uuidString, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 2, host.id.uuidString, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 3, host.address, -1, sqliteTransientForTests)
            sqlite3_bind_text(statement, 4, host.method.rawValue, -1, sqliteTransientForTests)
            sqlite3_bind_int64(statement, 5, Int64(host.port ?? 443))
            sqlite3_bind_double(statement, 6, timestamp.addingTimeInterval(Double(index)).timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, 10)
            if let latitude = coordinates.0 { sqlite3_bind_double(statement, 8, latitude) }
            else { sqlite3_bind_null(statement, 8) }
            if let longitude = coordinates.1 { sqlite3_bind_double(statement, 9, longitude) }
            else { sqlite3_bind_null(statement, 9) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
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

private actor BatchRecordingHistoryStore: PingHistoryStore {
    private var batches: [[PingResult]] = []

    func append(_ result: PingResult) async {
        batches.append([result])
    }

    func appendAndWait(_ results: [PingResult]) async throws {
        batches.append(results)
    }

    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] { [] }
    func prune(olderThan cutoff: Date) async {}
    func deleteAll() async {}

    func recordedBatches() -> [[PingResult]] { batches }
}

private final class SQLiteTransactionObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [SQLiteHistoryTransactionEvent] = []

    func record(_ event: SQLiteHistoryTransactionEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    var events: [SQLiteHistoryTransactionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

private struct HistoryExportDocumentProbe: Decodable {
    var host: HostConfig
    var samples: [PingResult]
}

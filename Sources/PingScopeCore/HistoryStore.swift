import Foundation
import SQLite3

public struct HistoryWeeklyDigestSample: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let hostID: UUID
    public let timestamp: Date
    public let latencyMilliseconds: Double?
    public let failureReason: FailureReason?
    public let lossFractionOverride: Double?
    public let networkInterface: String?
    public let networkName: String?

    public var isSuccess: Bool {
        latencyMilliseconds != nil && failureReason == nil
    }

    public init(
        id: UUID,
        hostID: UUID,
        timestamp: Date,
        latencyMilliseconds: Double?,
        failureReason: FailureReason?,
        lossFractionOverride: Double?,
        networkInterface: String?,
        networkName: String?
    ) {
        self.id = id
        self.hostID = hostID
        self.timestamp = timestamp
        self.latencyMilliseconds = latencyMilliseconds
        self.failureReason = failureReason
        self.lossFractionOverride = lossFractionOverride
        self.networkInterface = NetworkInterfaceNormalizer.normalize(networkInterface)
        self.networkName = networkName
    }

    public init(_ sample: PingResult) {
        self.init(
            id: sample.id,
            hostID: sample.hostID,
            timestamp: sample.timestamp,
            latencyMilliseconds: sample.latency?.milliseconds,
            failureReason: sample.failureReason,
            lossFractionOverride: sample.metadata.starlink?.popPingDropRate,
            networkInterface: sample.networkInterface,
            networkName: sample.networkName
        )
    }

    fileprivate static func isOrderedBefore(
        _ lhs: HistoryWeeklyDigestSample,
        _ rhs: HistoryWeeklyDigestSample
    ) -> Bool {
        if lhs.hostID != rhs.hostID { return lhs.hostID.uuidString < rhs.hostID.uuidString }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public protocol PingHistoryStore: Sendable {
    func append(_ result: PingResult) async
    func append(_ results: [PingResult]) async
    func appendAndWait(_ results: [PingResult]) async throws
    func upsertRemoteSamples(_ results: [PingResult]) async throws
    func deleteSamples(ids: [UUID]) async throws
    func unsyncedSamples(limit: Int) async throws -> [PingResult]
    func markSamplesSynced(ids: [UUID]) async throws
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult]
    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult]
    func weeklyDigestSamples(hostIDs: [UUID], since: Date, through: Date) async -> [HistoryWeeklyDigestSample]
    func weeklyDigestSampleStream(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) -> AsyncStream<HistoryWeeklyDigestSample>
    func historyRevision() async -> UInt64
    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int
    func prune(olderThan cutoff: Date) async
    func deleteAll() async
}

enum SQLiteHistoryTransactionEvent: Equatable, Sendable {
    case beginImmediate
    case commit
    case rollback
}

private enum SQLiteHistoryTestingError: Error {
    case forcedRemoteUpsertChunkFailure
}

public extension PingHistoryStore {
    func append(_ results: [PingResult]) async {
        for result in results {
            await append(result)
        }
    }

    func appendAndWait(_ results: [PingResult]) async throws {
        await append(results)
    }

    func upsertRemoteSamples(_ results: [PingResult]) async throws {
        try await appendAndWait(results)
    }

    func deleteSamples(ids: [UUID]) async throws {}

    func unsyncedSamples(limit: Int) async throws -> [PingResult] { [] }
    func markSamplesSynced(ids: [UUID]) async throws {}

    func weeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) async -> [HistoryWeeklyDigestSample] {
        var inputs: [HistoryWeeklyDigestSample] = []
        for hostID in Set(hostIDs) {
            let samples = await latestSamples(hostID: hostID, since: since, limit: Int.max)
            inputs.append(contentsOf: samples.lazy
                .filter { $0.timestamp <= through }
                .map(HistoryWeeklyDigestSample.init))
        }
        return inputs.sorted(by: HistoryWeeklyDigestSample.isOrderedBefore)
    }

    func weeklyDigestSampleStream(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) -> AsyncStream<HistoryWeeklyDigestSample> {
        AsyncStream { continuation in
            let task = Task {
                let samples = await weeklyDigestSamples(
                    hostIDs: hostIDs,
                    since: since,
                    through: through
                )
                for sample in samples where !Task.isCancelled {
                    continuation.yield(sample)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func historyRevision() async -> UInt64 { 0 }

    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        let exportedSamples = await samples(hostID: host.id, since: since, limit: 100_000)
        try HistoryExporter.write(samples: exportedSamples, host: host, format: format, to: url)
        return exportedSamples.count
    }
}

public final class SQLiteHistoryStore: PingHistoryStore, @unchecked Sendable {
    private let worker: SQLiteHistoryWorker

    public init(url: URL, retention: Duration = .days(7), logger: (@Sendable (String) -> Void)? = nil) {
        self.worker = SQLiteHistoryWorker(url: url, retention: retention, logger: logger)
    }

    init(
        url: URL,
        retention: Duration = .days(7),
        logger: (@Sendable (String) -> Void)? = nil,
        sqliteVariableNumberLimitForTesting: Int
    ) {
        self.worker = SQLiteHistoryWorker(
            url: url,
            retention: retention,
            logger: logger,
            sqliteVariableNumberLimitOverride: sqliteVariableNumberLimitForTesting
        )
    }

    init(
        url: URL,
        retention: Duration = .days(7),
        logger: (@Sendable (String) -> Void)? = nil,
        transactionObserverForTesting: @escaping @Sendable (SQLiteHistoryTransactionEvent) -> Void
    ) {
        self.worker = SQLiteHistoryWorker(
            url: url,
            retention: retention,
            logger: logger,
            transactionObserver: transactionObserverForTesting
        )
    }

    init(
        url: URL,
        retention: Duration = .days(7),
        logger: (@Sendable (String) -> Void)? = nil,
        remoteUpsertChunkSizeForTesting: Int,
        failingRemoteUpsertChunkForTesting: Int? = nil,
        transactionObserverForTesting: @escaping @Sendable (SQLiteHistoryTransactionEvent) -> Void
    ) {
        self.worker = SQLiteHistoryWorker(
            url: url,
            retention: retention,
            logger: logger,
            transactionObserver: transactionObserverForTesting,
            remoteUpsertChunkSize: remoteUpsertChunkSizeForTesting,
            failingRemoteUpsertChunk: failingRemoteUpsertChunkForTesting
        )
    }

    public static func defaultURL(appName: String = "PingScope") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("History.sqlite")
    }

    public func append(_ result: PingResult) async {
        await worker.append(result)
    }

    public func append(_ results: [PingResult]) async {
        await worker.append(results)
    }

    public func appendAndWait(_ results: [PingResult]) async throws {
        try await worker.appendAndWait(results)
    }

    public func upsertRemoteSamples(_ results: [PingResult]) async throws {
        try await worker.upsertRemoteSamples(results)
    }

    public func deleteSamples(ids: [UUID]) async throws {
        try await worker.deleteSamples(ids: ids)
    }

    public func unsyncedSamples(limit: Int) async throws -> [PingResult] {
        try await worker.unsyncedSamples(limit: limit)
    }

    public func markSamplesSynced(ids: [UUID]) async throws {
        try await worker.markSamplesSynced(ids: ids)
    }

    public func samples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        await worker.samples(hostID: hostID, since: since, limit: limit)
    }

    public func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        await worker.latestSamples(hostID: hostID, since: since, limit: limit)
    }

    public func weeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) async -> [HistoryWeeklyDigestSample] {
        await worker.weeklyDigestSamples(hostIDs: hostIDs, since: since, through: through)
    }

    public func weeklyDigestSampleStream(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) -> AsyncStream<HistoryWeeklyDigestSample> {
        worker.weeklyDigestSampleStream(hostIDs: hostIDs, since: since, through: through)
    }

    public func historyRevision() async -> UInt64 {
        await worker.historyRevision()
    }

    public func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        try await worker.exportSamples(host: host, since: since, format: format, to: url)
    }

    public func prune(olderThan cutoff: Date) async {
        await worker.prune(olderThan: cutoff)
    }

    public func deleteAll() async {
        await worker.deleteAll()
    }
}

private final class SQLiteHistoryWorker: @unchecked Sendable {
    /// Upper bound for a stored latency value; larger REALs are treated as corrupt.
    static let maxStoredLatencyMilliseconds: Double = 3_600_000
    private let queue: DispatchQueue
    private let url: URL
    private let retention: Duration
    private let logger: (@Sendable (String) -> Void)?
    private let connection = SQLiteConnection()
    private let metadataEncoder = JSONEncoder()
    private let metadataDecoder = JSONDecoder()
    private let pruneInterval: TimeInterval = 60
    private var lastPruneAttempt: Date?
    private var statementCache: [String: OpaquePointer] = [:]
    private var revision: UInt64 = 0
    private let sqliteVariableNumberLimitOverride: Int?
    private let transactionObserver: (@Sendable (SQLiteHistoryTransactionEvent) -> Void)?
    private let remoteUpsertChunkSize: Int
    private let failingRemoteUpsertChunk: Int?

    init(
        url: URL,
        retention: Duration = .days(7),
        logger: (@Sendable (String) -> Void)? = nil,
        sqliteVariableNumberLimitOverride: Int? = nil,
        transactionObserver: (@Sendable (SQLiteHistoryTransactionEvent) -> Void)? = nil,
        remoteUpsertChunkSize: Int = 500,
        failingRemoteUpsertChunk: Int? = nil
    ) {
        self.queue = DispatchQueue(label: "PingScope.SQLiteHistoryStore.\(UUID().uuidString)", qos: .utility)
        self.url = url
        self.retention = retention
        self.logger = logger
        self.sqliteVariableNumberLimitOverride = sqliteVariableNumberLimitOverride
        self.transactionObserver = transactionObserver
        self.remoteUpsertChunkSize = max(1, remoteUpsertChunkSize)
        self.failingRemoteUpsertChunk = failingRemoteUpsertChunk
    }

    deinit {
        finalizeCachedStatements()
    }

    func append(_ result: PingResult) async {
        await append([result])
    }

    func append(_ results: [PingResult]) async {
        do {
            try await appendAndWait(results)
        } catch {
            logger?("history append failed: \(error)")
        }
    }

    func appendAndWait(_ results: [PingResult]) async throws {
        try await performWithSQLiteRetry {
            try self.appendAndWaitSync(results)
        }
    }

    private func appendAndWaitSync(_ results: [PingResult]) throws {
        guard !results.isEmpty else { return }
        try openIfNeeded()
        var pruneAttemptTimestamp: Date?
        try withImmediateTransaction {
            let newestTimestamp = try insertRows(results, synced: false, replacingExisting: false)
            if let newestTimestamp,
               shouldPrune(at: newestTimestamp) {
                // Clamp to the wall clock so a single future-stamped sample (forward
                // clock jump, bad NTP) cannot drag the cutoff forward and wipe every
                // host's recent history. Backfilled rows older than this retention
                // cutoff remain eligible for pruning, except for IDs explicitly
                // delivered in this batch. CloudKit can legitimately backfill
                // older samples, so those rows must survive their insert transaction.
                let pruneAnchor = min(newestTimestamp, Date())
                try pruneSync(
                    olderThan: pruneAnchor.addingTimeInterval(-retention.seconds),
                    excludingIDs: results.map(\.id)
                )
                pruneAttemptTimestamp = newestTimestamp
            }
        }
        revision &+= 1
        if let pruneAttemptTimestamp {
            lastPruneAttempt = pruneAttemptTimestamp
        }
    }

    func upsertRemoteSamples(_ results: [PingResult]) async throws {
        guard !results.isEmpty else { return }
        var chunkIndex = 0
        for startIndex in stride(from: 0, to: results.count, by: remoteUpsertChunkSize) {
            let endIndex = min(results.count, startIndex + remoteUpsertChunkSize)
            let chunk = Array(results[startIndex..<endIndex])
            let currentChunkIndex = chunkIndex
            try await performWithSQLiteRetry {
                if self.failingRemoteUpsertChunk == currentChunkIndex {
                    throw SQLiteHistoryTestingError.forcedRemoteUpsertChunkFailure
                }
                try self.openIfNeeded()
                try self.insert(chunk, synced: true, replacingExisting: true)
                self.revision &+= 1
            }
            chunkIndex += 1
        }
    }

    func unsyncedSamples(limit: Int) async throws -> [PingResult] {
        try await performWithSQLiteRetry {
            try self.openIfNeeded()
            return try self.queryUnsynced(limit: max(1, limit))
        }
    }

    func markSamplesSynced(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await performWithSQLiteRetry {
            try self.openIfNeeded()
            try self.withImmediateTransaction {
                try self.withStatement("UPDATE ping_samples SET synced = 1 WHERE id = ?;") { statement in
                    for id in ids {
                        self.bindText(id.uuidString, to: 1, in: statement)
                        let result = sqlite3_step(statement)
                        guard result == SQLITE_DONE else { throw self.sqliteError(.stepFailed, code: result) }
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                    }
                }
            }
        }
    }

    func samples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        do {
            return try await performWithSQLiteRetry {
                try self.openIfNeeded()
                return try self.query(hostID: hostID, since: since, limit: max(1, limit))
            }
        } catch {
            logger?("history query failed: \(error)")
            return []
        }
    }

    func latestSamples(hostID: UUID, since: Date, limit: Int) async -> [PingResult] {
        do {
            return try await performWithSQLiteRetry {
                try self.openIfNeeded()
                return try self.queryLatest(hostID: hostID, since: since, limit: max(1, limit))
            }
        } catch {
            logger?("history latest query failed: \(error)")
            return []
        }
    }

    func weeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) async -> [HistoryWeeklyDigestSample] {
        let uniqueHostIDs = Array(Set(hostIDs)).sorted { $0.uuidString < $1.uuidString }
        guard !uniqueHostIDs.isEmpty else { return [] }
        do {
            return try await performWithSQLiteRetry {
                try self.openIfNeeded()
                guard let db = self.connection.db else {
                    throw SQLiteHistoryError.openFailed(message: "database is not open")
                }
                if let override = self.sqliteVariableNumberLimitOverride {
                    let priorLimit = sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, Int32(max(3, override)))
                    defer { sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, priorLimit) }
                    return try self.queryWeeklyDigestSamples(
                        hostIDs: uniqueHostIDs,
                        since: since,
                        through: through
                    )
                }
                return try self.queryWeeklyDigestSamples(
                    hostIDs: uniqueHostIDs,
                    since: since,
                    through: through
                )
            }
        } catch {
            logger?("history weekly digest query failed: \(error)")
            return []
        }
    }

    func weeklyDigestSampleStream(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) -> AsyncStream<HistoryWeeklyDigestSample> {
        let uniqueHostIDs = Array(Set(hostIDs)).sorted { $0.uuidString < $1.uuidString }
        guard !uniqueHostIDs.isEmpty else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                do {
                    try await self.performWithSQLiteRetry {
                        try self.openIfNeeded()
                        guard let db = self.connection.db else {
                            throw SQLiteHistoryError.openFailed(message: "database is not open")
                        }
                        if let override = self.sqliteVariableNumberLimitOverride {
                            let priorLimit = sqlite3_limit(
                                db,
                                SQLITE_LIMIT_VARIABLE_NUMBER,
                                Int32(max(3, override))
                            )
                            defer { sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, priorLimit) }
                            try self.streamWeeklyDigestSamples(
                                hostIDs: uniqueHostIDs,
                                since: since,
                                through: through,
                                onSample: { continuation.yield($0) }
                            )
                        } else {
                            try self.streamWeeklyDigestSamples(
                                hostIDs: uniqueHostIDs,
                                since: since,
                                through: through,
                                onSample: { continuation.yield($0) }
                            )
                        }
                    }
                } catch {
                    self.logger?("history weekly digest stream failed: \(error)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func historyRevision() async -> UInt64 {
        (try? await perform { self.revision }) ?? 0
    }

    func exportSamples(host: HostConfig, since: Date, format: HistoryExportFormat, to url: URL) async throws -> Int {
        try await performWithSQLiteRetry {
            try self.openIfNeeded()
            return try HistoryExporter.writeStreaming(
                host: host,
                format: format,
                sampleCount: nil,
                to: url
            ) { writer in
                try self.streamSamples(hostID: host.id, since: since, to: writer)
            }
        }
    }

    func prune(olderThan cutoff: Date) async {
        do {
            try await performWithSQLiteRetry {
                try self.openIfNeeded()
                try self.pruneSync(olderThan: cutoff)
                self.lastPruneAttempt = Date()
                self.revision &+= 1
            }
        } catch {
            logger?("history prune failed: \(error)")
            return
        }
    }

    func deleteAll() async {
        do {
            try await performWithSQLiteRetry {
                try self.openIfNeeded()
                try self.execute("DELETE FROM ping_samples;")
                self.revision &+= 1
            }
        } catch {
            logger?("history delete failed: \(error)")
            return
        }
    }

    func deleteSamples(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await performWithSQLiteRetry {
            try self.openIfNeeded()
            try self.withImmediateTransaction {
                try self.withStatement("DELETE FROM ping_samples WHERE id = ?;") { statement in
                    for id in ids {
                        self.bindText(id.uuidString, to: 1, in: statement)
                        let result = sqlite3_step(statement)
                        guard result == SQLITE_DONE else {
                            throw self.sqliteError(.stepFailed, code: result)
                        }
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                    }
                }
            }
            self.revision &+= 1
        }
    }

    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performWithSQLiteRetry<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await perform(operation)
            } catch {
                lastError = error
                guard isTransientSQLiteError(error), attempt < 2 else { break }
                let backoffMilliseconds = Double(50 * (1 << attempt)) + Double.random(in: 0...25)
                try await Task.sleep(nanoseconds: UInt64(backoffMilliseconds * 1_000_000))
            }
        }
        throw lastError ?? SQLiteHistoryError.openFailed(message: "unknown SQLite retry failure")
    }

    private func openIfNeeded() throws {
        guard connection.db == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        // NOMUTEX is safe because this handle is confined to SQLiteHistoryWorker's serial queue.
        // Do not share connection.db across queues without restoring SQLite serialization.
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let handle = opened else {
            // SQLite returns a handle even on failure so the error message can be
            // read; it must still be closed or every failed open leaks a connection.
            let message = opened.map(Self.errorMessage) ?? "unable to open database"
            if let opened {
                sqlite3_close(opened)
            }
            throw SQLiteHistoryError.openFailed(message: message)
        }
        connection.db = handle
        do {
            sqlite3_busy_timeout(handle, 2_000)
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try execute("""
            CREATE TABLE IF NOT EXISTS ping_samples (
                id TEXT PRIMARY KEY,
                host_id TEXT NOT NULL,
                address TEXT NOT NULL,
                method TEXT NOT NULL,
                port INTEGER,
                timestamp REAL NOT NULL,
                latency_ms REAL,
                failure_reason TEXT,
                metadata_note TEXT,
                metadata_json TEXT
            );
            """)
            try addColumnIfNeeded(table: "ping_samples", column: "metadata_json", definition: "TEXT")
            try addColumnIfNeeded(table: "ping_samples", column: "latitude", definition: "REAL")
            try addColumnIfNeeded(table: "ping_samples", column: "longitude", definition: "REAL")
            try addColumnIfNeeded(table: "ping_samples", column: "horizontal_accuracy", definition: "REAL")
            try addColumnIfNeeded(table: "ping_samples", column: "network_name", definition: "TEXT")
            try addColumnIfNeeded(table: "ping_samples", column: "network_interface", definition: "TEXT")
            try addColumnIfNeeded(table: "ping_samples", column: "network_interface_top", definition: "TEXT")
            try addColumnIfNeeded(table: "ping_samples", column: "network_name_top", definition: "TEXT")
            try addColumnIfNeeded(table: "ping_samples", column: "is_vpn", definition: "INTEGER")
            try addColumnIfNeeded(table: "ping_samples", column: "synced", definition: "INTEGER NOT NULL DEFAULT 0")
            try execute("CREATE INDEX IF NOT EXISTS ping_samples_host_time ON ping_samples(host_id, timestamp);")
            try execute("CREATE INDEX IF NOT EXISTS ping_samples_timestamp ON ping_samples(timestamp);")
            try execute("CREATE INDEX IF NOT EXISTS ping_samples_unsynced_time ON ping_samples(synced, timestamp DESC);")
        } catch {
            // Never cache a half-initialized connection: openIfNeeded no-ops once
            // connection.db is set, which would make withSQLiteRetry retry against
            // a schema-less handle forever instead of reopening.
            finalizeCachedStatements()
            sqlite3_close(handle)
            connection.db = nil
            throw error
        }
    }

    private func shouldPrune(at timestamp: Date) -> Bool {
        guard let lastPruneAttempt else { return true }
        return timestamp.timeIntervalSince(lastPruneAttempt) >= pruneInterval
    }

    private func isTransientSQLiteError(_ error: Error) -> Bool {
        guard let sqliteError = error as? SQLiteHistoryError else { return false }
        return sqliteError.isTransient
    }

    private func insert(
        _ results: [PingResult],
        synced: Bool,
        replacingExisting: Bool
    ) throws {
        try withImmediateTransaction {
            _ = try insertRows(results, synced: synced, replacingExisting: replacingExisting)
        }
    }

    private func insertRows(
        _ results: [PingResult],
        synced: Bool,
        replacingExisting: Bool
    ) throws -> Date? {
        let insertVerb = replacingExisting ? "INSERT OR REPLACE" : "INSERT OR IGNORE"
        let sql = """
        \(insertVerb) INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json,
         latitude, longitude, horizontal_accuracy, network_name, network_interface,
         network_interface_top, network_name_top, is_vpn, synced)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        return try withStatement(sql) { statement in
            var newestInsertedTimestamp: Date?
            for result in results {
                try bindInsert(result, to: statement)
                sqlite3_bind_int(statement, 19, synced ? 1 : 0)
                let stepResult = sqlite3_step(statement)
                guard stepResult == SQLITE_DONE else {
                    throw sqliteError(.stepFailed, code: stepResult)
                }
                if sqlite3_changes(connection.db) > 0,
                   newestInsertedTimestamp.map({ result.timestamp > $0 }) ?? true {
                    newestInsertedTimestamp = result.timestamp
                }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
            }
            return newestInsertedTimestamp
        }
    }
    private func bindInsert(_ result: PingResult, to statement: OpaquePointer) throws {
        bindText(result.id.uuidString, to: 1, in: statement)
        bindText(result.hostID.uuidString, to: 2, in: statement)
        bindText(result.address, to: 3, in: statement)
        bindText(result.method.rawValue, to: 4, in: statement)
        if let port = result.port {
            sqlite3_bind_int64(statement, 5, Int64(port))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_double(statement, 6, result.timestamp.timeIntervalSince1970)
        if let latency = result.latency {
            sqlite3_bind_double(statement, 7, latency.milliseconds)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        if let failureReason = result.failureReason {
            bindText(failureReason.rawValue, to: 8, in: statement)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        if let note = result.metadata.note {
            bindText(note, to: 9, in: statement)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        if result.metadata.starlink != nil,
           let metadataData = try? metadataEncoder.encode(result.metadata),
           let metadataText = String(data: metadataData, encoding: .utf8) {
            bindText(metadataText, to: 10, in: statement)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        if let location = result.location {
            sqlite3_bind_double(statement, 11, location.latitude)
            sqlite3_bind_double(statement, 12, location.longitude)
            if let horizontalAccuracy = location.horizontalAccuracy {
                sqlite3_bind_double(statement, 13, horizontalAccuracy)
            } else {
                sqlite3_bind_null(statement, 13)
            }
            if let networkName = location.networkName {
                bindText(networkName, to: 14, in: statement)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            if let networkInterface = location.networkInterface {
                bindText(networkInterface, to: 15, in: statement)
            } else {
                sqlite3_bind_null(statement, 15)
            }
        } else {
            for index in 11...15 {
                sqlite3_bind_null(statement, Int32(index))
            }
        }
        if let networkInterface = result.networkInterface {
            bindText(networkInterface, to: 16, in: statement)
        } else {
            sqlite3_bind_null(statement, 16)
        }
        if let networkName = result.networkName {
            bindText(networkName, to: 17, in: statement)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        sqlite3_bind_int(statement, 18, result.isVPN ? 1 : 0)
    }

    private func query(hostID: UUID, since: Date, limit: Int) throws -> [PingResult] {
        let sql = """
        SELECT id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json,
               latitude, longitude, horizontal_accuracy, network_name, network_interface,
               network_interface_top, network_name_top, is_vpn
        FROM ping_samples
        WHERE host_id = ? AND timestamp >= ?
        ORDER BY timestamp ASC
        LIMIT ?;
        """
        var results: [PingResult] = []
        try withStatement(sql) { statement in
            bindText(hostID.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, since.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                if let result = result(from: statement) {
                    results.append(result)
                }
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: stepResult)
            }
        }
        return results
    }

    private func queryLatest(hostID: UUID, since: Date, limit: Int) throws -> [PingResult] {
        let sql = """
        SELECT id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json,
               latitude, longitude, horizontal_accuracy, network_name, network_interface,
               network_interface_top, network_name_top, is_vpn
        FROM ping_samples
        WHERE host_id = ? AND timestamp >= ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        var results: [PingResult] = []
        try withStatement(sql) { statement in
            bindText(hostID.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, since.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                if let result = result(from: statement) {
                    results.append(result)
                }
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: stepResult)
            }
        }
        return results
    }

    private func queryWeeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date
    ) throws -> [HistoryWeeklyDigestSample] {
        var samples: [HistoryWeeklyDigestSample] = []
        try streamWeeklyDigestSamples(
            hostIDs: hostIDs,
            since: since,
            through: through
        ) {
            samples.append($0)
        }
        return samples
    }

    private func streamWeeklyDigestSamples(
        hostIDs: [UUID],
        since: Date,
        through: Date,
        onSample: (HistoryWeeklyDigestSample) -> Void
    ) throws {
        guard let db = connection.db else {
            throw SQLiteHistoryError.openFailed(message: "database is not open")
        }
        let variableLimit = Int(sqlite3_limit(db, SQLITE_LIMIT_VARIABLE_NUMBER, -1))
        let maximumHostsPerQuery = max(1, variableLimit - 2)
        for startIndex in stride(from: 0, to: hostIDs.count, by: maximumHostsPerQuery) {
            let endIndex = min(hostIDs.count, startIndex + maximumHostsPerQuery)
            try streamWeeklyDigestSampleChunk(
                hostIDs: Array(hostIDs[startIndex..<endIndex]),
                since: since,
                through: through,
                onSample: onSample
            )
        }
    }

    private func streamWeeklyDigestSampleChunk(
        hostIDs: [UUID],
        since: Date,
        through: Date,
        onSample: (HistoryWeeklyDigestSample) -> Void
    ) throws {
        let placeholders = Array(repeating: "?", count: hostIDs.count).joined(separator: ", ")
        let sql = """
        SELECT id, host_id, timestamp, latency_ms, failure_reason,
               CASE WHEN json_valid(metadata_json)
                    THEN json_extract(metadata_json, '$.starlink.popPingDropRate')
               END,
               network_interface_top, network_name_top
        FROM ping_samples
        WHERE host_id IN (\(placeholders)) AND timestamp >= ? AND timestamp <= ?
        ORDER BY host_id ASC, timestamp ASC, id ASC;
        """
        try withStatement(sql) { statement in
            for (offset, hostID) in hostIDs.enumerated() {
                bindText(hostID.uuidString, to: Int32(offset + 1), in: statement)
            }
            let sinceIndex = Int32(hostIDs.count + 1)
            sqlite3_bind_double(statement, sinceIndex, since.timeIntervalSince1970)
            sqlite3_bind_double(statement, sinceIndex + 1, through.timeIntervalSince1970)

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                if let sample = weeklyDigestSample(from: statement) {
                    onSample(sample)
                }
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: stepResult)
            }
        }
    }

    private func queryUnsynced(limit: Int) throws -> [PingResult] {
        let sql = """
        SELECT id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json,
               latitude, longitude, horizontal_accuracy, network_name, network_interface,
               network_interface_top, network_name_top, is_vpn
        FROM ping_samples
        WHERE synced = 0
        ORDER BY timestamp DESC
        LIMIT ?;
        """
        var results: [PingResult] = []
        try withStatement(sql) { statement in
            sqlite3_bind_int64(statement, 1, Int64(limit))
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                if let result = result(from: statement) { results.append(result) }
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else { throw sqliteError(.stepFailed, code: stepResult) }
        }
        return results
    }

    private func streamSamples(hostID: UUID, since: Date, to writer: HistoryExportSampleWriter) throws -> Int {
        let sql = """
        SELECT id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json,
               latitude, longitude, horizontal_accuracy, network_name, network_interface,
               network_interface_top, network_name_top, is_vpn
        FROM ping_samples
        WHERE host_id = ? AND timestamp >= ?
        ORDER BY timestamp ASC;
        """
        var count = 0
        try withStatement(sql) { statement in
            bindText(hostID.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, since.timeIntervalSince1970)

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                if let result = result(from: statement) {
                    try writer.write(result)
                    count += 1
                }
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: stepResult)
            }
        }
        return count
    }

    private func pruneSync(olderThan cutoff: Date, excludingIDs: [UUID] = []) throws {
        guard !excludingIDs.isEmpty else {
            try withStatement("DELETE FROM ping_samples WHERE timestamp < ?;") { statement in
                sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
                let result = sqlite3_step(statement)
                guard result == SQLITE_DONE else {
                    throw sqliteError(.stepFailed, code: result)
                }
            }
            return
        }
        let encodedIDs = try metadataEncoder.encode(excludingIDs.map(\.uuidString))
        guard let jsonIDs = String(data: encodedIDs, encoding: .utf8) else {
            throw SQLiteHistoryError.stepFailed(code: SQLITE_MISMATCH, message: "unable to encode retention exclusions")
        }
        let sql = """
        DELETE FROM ping_samples
        WHERE timestamp < ?
          AND id NOT IN (SELECT value FROM json_each(?));
        """
        try withStatement(sql) { statement in
            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            bindText(jsonIDs, to: 2, in: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: result)
            }
        }
    }

    private func weeklyDigestSample(from statement: OpaquePointer) -> HistoryWeeklyDigestSample? {
        guard let idText = text(at: 0, in: statement),
              let id = UUID(uuidString: idText),
              let hostIDText = text(at: 1, in: statement),
              let hostID = UUID(uuidString: hostIDText) else {
            return nil
        }
        let latencyMilliseconds: Double?
        if sqlite3_column_type(statement, 3) == SQLITE_NULL {
            latencyMilliseconds = nil
        } else {
            let value = sqlite3_column_double(statement, 3)
            latencyMilliseconds = value.isFinite && value >= 0 && value <= Self.maxStoredLatencyMilliseconds
                ? value
                : nil
        }
        let lossFractionOverride = sqlite3_column_type(statement, 5) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, 5)
        return HistoryWeeklyDigestSample(
            id: id,
            hostID: hostID,
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            latencyMilliseconds: latencyMilliseconds,
            failureReason: text(at: 4, in: statement).flatMap(FailureReason.init(rawValue:)),
            lossFractionOverride: lossFractionOverride,
            networkInterface: text(at: 6, in: statement),
            networkName: text(at: 7, in: statement)
        )
    }

    private func execute(_ sql: String) throws {
        guard let db = connection.db else { throw SQLiteHistoryError.openFailed(message: "database is not open") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? Self.errorMessage(db)
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
            throw SQLiteHistoryError.stepFailed(code: result, message: message)
        }
    }

    private func withImmediateTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        transactionObserver?(.beginImmediate)
        do {
            try body()
            try execute("COMMIT;")
            transactionObserver?(.commit)
        } catch {
            try? execute("ROLLBACK;")
            transactionObserver?(.rollback)
            throw error
        }
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        guard connection.db != nil else { throw SQLiteHistoryError.openFailed(message: "database is not open") }
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        var exists = false
        try withStatement("PRAGMA table_info('\(escapedTable)');") { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                if text(at: 1, in: statement) == column {
                    exists = true
                    break
                }
            }
        }
        if !exists {
            try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        }
    }

    private func withStatement<Value>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> Value
    ) throws -> Value {
        let statement = try cachedStatement(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return try body(statement)
    }

    private func cachedStatement(_ sql: String) throws -> OpaquePointer {
        if let statement = statementCache[sql] {
            return statement
        }
        guard let db = connection.db else { throw SQLiteHistoryError.openFailed(message: "database is not open") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryError.prepareFailed(code: result, message: Self.errorMessage(db))
        }
        statementCache[sql] = statement
        return statement
    }

    private func finalizeCachedStatements() {
        for statement in statementCache.values {
            sqlite3_finalize(statement)
        }
        statementCache.removeAll()
    }

    private func sqliteError(_ fallback: SQLiteHistoryError.Kind, code: Int32) -> SQLiteHistoryError {
        guard let db = connection.db else {
            return .openFailed(message: "database is not open")
        }
        switch fallback {
        case .prepareFailed:
            return .prepareFailed(code: code, message: Self.errorMessage(db))
        case .stepFailed:
            return .stepFailed(code: code, message: Self.errorMessage(db))
        }
    }

    private static func errorMessage(_ db: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: message)
    }

    private func result(from statement: OpaquePointer) -> PingResult? {
        guard let idText = text(at: 0, in: statement),
              let id = UUID(uuidString: idText),
              let hostIDText = text(at: 1, in: statement),
              let hostID = UUID(uuidString: hostIDText),
              let address = text(at: 2, in: statement),
              let methodText = text(at: 3, in: statement),
              let method = PingMethod(rawValue: methodText) else {
            return nil
        }

        let port: UInt16?
        if sqlite3_column_type(statement, 4) == SQLITE_NULL {
            port = nil
        } else {
            port = UInt16(clamping: sqlite3_column_int64(statement, 4))
        }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let latency: Duration?
        if sqlite3_column_type(statement, 6) == SQLITE_NULL {
            latency = nil
        } else {
            // A corrupt or externally edited row (NaN/Infinity/huge REAL) would trap
            // converting to Duration's Int128 attoseconds — and re-trap on every read.
            let latencyMilliseconds = sqlite3_column_double(statement, 6)
            if latencyMilliseconds.isFinite, latencyMilliseconds >= 0,
               latencyMilliseconds <= Self.maxStoredLatencyMilliseconds {
                latency = .milliseconds(latencyMilliseconds)
            } else {
                latency = nil
            }
        }
        let failureReason = text(at: 7, in: statement).flatMap(FailureReason.init(rawValue:))
        let metadata: ProbeMetadata
        if let metadataText = text(at: 9, in: statement),
           let metadataData = metadataText.data(using: .utf8),
           let decoded = try? metadataDecoder.decode(ProbeMetadata.self, from: metadataData) {
            metadata = decoded
        } else {
            metadata = ProbeMetadata(note: text(at: 8, in: statement))
        }
        let location: SampleLocation?
        if sqlite3_column_type(statement, 10) != SQLITE_NULL,
           sqlite3_column_type(statement, 11) != SQLITE_NULL {
            let horizontalAccuracy = sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 12)
            location = SampleLocation(
                latitude: sqlite3_column_double(statement, 10),
                longitude: sqlite3_column_double(statement, 11),
                horizontalAccuracy: horizontalAccuracy,
                networkName: text(at: 13, in: statement),
                networkInterface: text(at: 14, in: statement)
            )
        } else {
            location = nil
        }

        return PingResult(
            id: id,
            hostID: hostID,
            address: address,
            method: method,
            port: port,
            timestamp: timestamp,
            latency: latency,
            failureReason: failureReason,
            metadata: metadata,
            location: location,
            networkInterface: text(at: 15, in: statement),
            networkName: text(at: 16, in: statement),
            isVPN: sqlite3_column_type(statement, 17) != SQLITE_NULL
                && sqlite3_column_int(statement, 17) != 0
        )
    }

    private func bindText(_ value: String, to index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func text(at index: Int32, in statement: OpaquePointer) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}

private enum SQLiteHistoryError: Error, CustomStringConvertible {
    enum Kind {
        case prepareFailed
        case stepFailed
    }

    case openFailed(message: String)
    case prepareFailed(code: Int32, message: String)
    case stepFailed(code: Int32, message: String)

    var description: String {
        switch self {
        case .openFailed(let message):
            "SQLite open failed: \(message)"
        case .prepareFailed(let code, let message):
            "SQLite prepare failed (\(code)): \(message)"
        case .stepFailed(let code, let message):
            "SQLite step failed (\(code)): \(message)"
        }
    }

    var isTransient: Bool {
        switch self {
        case .openFailed:
            false
        case .prepareFailed(let code, _), .stepFailed(let code, _):
            code == SQLITE_BUSY || code == SQLITE_LOCKED
        }
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    var db: OpaquePointer?

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public extension Duration {
    static func days(_ value: Double) -> Duration {
        .seconds(value * 86_400)
    }
}

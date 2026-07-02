import Foundation
import SQLite3

public protocol PingHistoryStore: Sendable {
    func append(_ result: PingResult) async
    func append(_ results: [PingResult]) async
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult]
    func prune(olderThan cutoff: Date) async
    func deleteAll() async
}

public extension PingHistoryStore {
    func append(_ results: [PingResult]) async {
        for result in results {
            await append(result)
        }
    }
}

public actor SQLiteHistoryStore: PingHistoryStore {
    private let url: URL
    private let retention: Duration
    private let logger: (@Sendable (String) -> Void)?
    private let connection = SQLiteConnection()
    private let metadataEncoder = JSONEncoder()
    private let metadataDecoder = JSONDecoder()
    private let pruneInterval: TimeInterval = 60
    private var lastPruneAttempt: Date?

    public init(url: URL, retention: Duration = .days(7), logger: (@Sendable (String) -> Void)? = nil) {
        self.url = url
        self.retention = retention
        self.logger = logger
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
        await append([result])
    }

    public func append(_ results: [PingResult]) async {
        guard !results.isEmpty else { return }
        do {
            try await withSQLiteRetry {
                try openIfNeeded()
                try insert(results)
                if let newestTimestamp = results.map(\.timestamp).max(), shouldPrune(at: newestTimestamp) {
                    try pruneSync(olderThan: newestTimestamp.addingTimeInterval(-retention.seconds))
                    lastPruneAttempt = newestTimestamp
                }
            }
        } catch {
            logger?("history append failed: \(error)")
            return
        }
    }

    public func samples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        do {
            return try await withSQLiteRetry {
                try openIfNeeded()
                return try query(hostID: hostID, since: since, limit: max(1, limit))
            }
        } catch {
            logger?("history query failed: \(error)")
            return []
        }
    }

    public func prune(olderThan cutoff: Date) async {
        do {
            try await withSQLiteRetry {
                try openIfNeeded()
                try pruneSync(olderThan: cutoff)
                lastPruneAttempt = Date()
            }
        } catch {
            logger?("history prune failed: \(error)")
            return
        }
    }

    public func deleteAll() async {
        do {
            try await withSQLiteRetry {
                try openIfNeeded()
                try execute("DELETE FROM ping_samples;")
            }
        } catch {
            logger?("history delete failed: \(error)")
            return
        }
    }

    private func openIfNeeded() throws {
        guard connection.db == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        // NOMUTEX is safe because this handle is confined to the SQLiteHistoryStore actor.
        // Do not share connection.db across threads without restoring SQLite serialization.
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
            try execute("CREATE INDEX IF NOT EXISTS ping_samples_host_time ON ping_samples(host_id, timestamp);")
            try execute("CREATE INDEX IF NOT EXISTS ping_samples_timestamp ON ping_samples(timestamp);")
        } catch {
            // Never cache a half-initialized connection: openIfNeeded no-ops once
            // connection.db is set, which would make withSQLiteRetry retry against
            // a schema-less handle forever instead of reopening.
            sqlite3_close(handle)
            connection.db = nil
            throw error
        }
    }

    private func shouldPrune(at timestamp: Date) -> Bool {
        guard let lastPruneAttempt else { return true }
        return timestamp.timeIntervalSince(lastPruneAttempt) >= pruneInterval
    }

    private func withSQLiteRetry<T>(_ operation: () throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try operation()
            } catch {
                lastError = error
                guard isTransientSQLiteError(error), attempt < 2 else { break }
                try? await Task.sleep(for: .milliseconds(Double(50 * (attempt + 1))))
            }
        }
        throw lastError ?? SQLiteHistoryError.openFailed(message: "unknown SQLite retry failure")
    }

    private func isTransientSQLiteError(_ error: Error) -> Bool {
        guard let sqliteError = error as? SQLiteHistoryError else { return false }
        return sqliteError.isTransient
    }

    private func insert(_ results: [PingResult]) throws {
        let sql = """
        INSERT OR REPLACE INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let shouldWrapInTransaction = true
        if shouldWrapInTransaction {
            try execute("BEGIN IMMEDIATE;")
        }
        do {
            try withStatement(sql) { statement in
                for result in results {
                    try bindInsert(result, to: statement)
                    let stepResult = sqlite3_step(statement)
                    guard stepResult == SQLITE_DONE else {
                        throw sqliteError(.stepFailed, code: stepResult)
                    }
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }
            }
            if shouldWrapInTransaction {
                try execute("COMMIT;")
            }
        } catch {
            if shouldWrapInTransaction {
                try? execute("ROLLBACK;")
            }
            throw error
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
        if let metadataData = try? metadataEncoder.encode(result.metadata),
           let metadataText = String(data: metadataData, encoding: .utf8) {
            bindText(metadataText, to: 10, in: statement)
        } else {
            sqlite3_bind_null(statement, 10)
        }
    }

    private func query(hostID: UUID, since: Date, limit: Int) throws -> [PingResult] {
        let sql = """
        SELECT id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json
        FROM ping_samples
        WHERE host_id = ? AND timestamp >= ?
        ORDER BY timestamp ASC
        LIMIT ?;
        """
        var results: [PingResult] = []
        try withStatement(sql) { statement in
            bindText(hostID.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, since.timeIntervalSince1970)
            sqlite3_bind_int(statement, 3, Int32(limit))

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

    private func pruneSync(olderThan cutoff: Date) throws {
        try withStatement("DELETE FROM ping_samples WHERE timestamp < ?;") { statement in
            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw sqliteError(.stepFailed, code: result)
            }
        }
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

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        guard let db = connection.db else { throw SQLiteHistoryError.openFailed(message: "database is not open") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryError.prepareFailed(code: result, message: Self.errorMessage(db))
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
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
            latency = .milliseconds(sqlite3_column_double(statement, 6))
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

        return PingResult(
            id: id,
            hostID: hostID,
            address: address,
            method: method,
            port: port,
            timestamp: timestamp,
            latency: latency,
            failureReason: failureReason,
            metadata: metadata
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

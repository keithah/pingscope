import Foundation
import SQLite3

public protocol PingHistoryStore: Sendable {
    func append(_ result: PingResult) async
    func samples(hostID: UUID, since: Date, limit: Int) async -> [PingResult]
    func prune(olderThan cutoff: Date) async
    func deleteAll() async
}

public actor SQLiteHistoryStore: PingHistoryStore {
    private let url: URL
    private let retention: Duration
    private let connection = SQLiteConnection()

    public init(url: URL, retention: Duration = .days(7)) {
        self.url = url
        self.retention = retention
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
        do {
            try openIfNeeded()
            try insert(result)
            try pruneSync(olderThan: result.timestamp.addingTimeInterval(-retention.seconds))
        } catch {
            return
        }
    }

    public func samples(hostID: UUID, since: Date, limit: Int = 10_000) async -> [PingResult] {
        do {
            try openIfNeeded()
            return try query(hostID: hostID, since: since, limit: max(1, limit))
        } catch {
            return []
        }
    }

    public func prune(olderThan cutoff: Date) async {
        do {
            try openIfNeeded()
            try pruneSync(olderThan: cutoff)
        } catch {
            return
        }
    }

    public func deleteAll() async {
        do {
            try openIfNeeded()
            try execute("DELETE FROM ping_samples;")
        } catch {
            return
        }
    }

    private func openIfNeeded() throws {
        guard connection.db == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened else {
            throw SQLiteHistoryError.openFailed
        }
        connection.db = opened
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
    }

    private func insert(_ result: PingResult) throws {
        let sql = """
        INSERT OR REPLACE INTO ping_samples
        (id, host_id, address, method, port, timestamp, latency_ms, failure_reason, metadata_note, metadata_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
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
            if let metadataData = try? JSONEncoder().encode(result.metadata),
               let metadataText = String(data: metadataData, encoding: .utf8) {
                bindText(metadataText, to: 10, in: statement)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteHistoryError.stepFailed
            }
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

            while sqlite3_step(statement) == SQLITE_ROW {
                if let result = result(from: statement) {
                    results.append(result)
                }
            }
        }
        return results
    }

    private func pruneSync(olderThan cutoff: Date) throws {
        try withStatement("DELETE FROM ping_samples WHERE timestamp < ?;") { statement in
            sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteHistoryError.stepFailed
            }
        }
    }

    private func execute(_ sql: String) throws {
        guard let db = connection.db else { throw SQLiteHistoryError.openFailed }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteHistoryError.stepFailed
        }
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        guard connection.db != nil else { throw SQLiteHistoryError.openFailed }
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
        guard let db = connection.db else { throw SQLiteHistoryError.openFailed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
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
           let decoded = try? JSONDecoder().decode(ProbeMetadata.self, from: metadataData) {
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

private enum SQLiteHistoryError: Error {
    case openFailed
    case prepareFailed
    case stepFailed
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

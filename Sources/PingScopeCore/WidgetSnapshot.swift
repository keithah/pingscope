import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var primaryHostID: UUID?
    public var hosts: [WidgetHost]
    public var health: [WidgetHostHealth]
    public var recentSamples: [WidgetSample]
    public var networkStatus: NetworkConnectivityStatus
    public var generatedAt: Date

    public init(
        version: Int = 1,
        primaryHostID: UUID?,
        hosts: [WidgetHost],
        health: [WidgetHostHealth],
        recentSamples: [WidgetSample],
        networkStatus: NetworkConnectivityStatus,
        generatedAt: Date = Date()
    ) {
        self.version = version
        self.primaryHostID = primaryHostID
        self.hosts = hosts
        self.health = health
        self.recentSamples = recentSamples
        self.networkStatus = networkStatus
        self.generatedAt = generatedAt
    }

    public static func make(
        from snapshot: RuntimeSnapshot,
        networkStatus: NetworkConnectivityStatus = .connected,
        sampleLimitPerHost: Int = 60,
        generatedAt: Date = Date()
    ) -> WidgetSnapshot {
        let hosts = snapshot.hosts.map {
            WidgetHost(
                id: $0.id,
                displayName: $0.displayName,
                address: $0.address,
                method: $0.method,
                port: $0.port,
                isPrimary: $0.id == snapshot.primaryHostID
            )
        }

        let health = snapshot.hosts.map { host in
            let hostHealth = snapshot.healthByHost[host.id] ?? HostHealth(hostID: host.id, thresholds: host.thresholds)
            return WidgetHostHealth(
                hostID: host.id,
                status: hostHealth.status,
                latencyMilliseconds: hostHealth.latestResult?.latency?.milliseconds,
                consecutiveFailureCount: hostHealth.consecutiveFailureCount,
                failureReason: hostHealth.latestResult?.failureReason,
                latestResultAt: hostHealth.latestResult?.timestamp
            )
        }

        let limit = max(1, sampleLimitPerHost)
        let samples = snapshot.samplesByHost.values.flatMap { series in
            series.samples.suffix(limit).map(WidgetSample.init(result:))
        }
        .sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }

        return WidgetSnapshot(
            primaryHostID: snapshot.primaryHostID,
            hosts: hosts,
            health: health,
            recentSamples: samples,
            networkStatus: networkStatus,
            generatedAt: generatedAt
        )
    }

    public static let empty = WidgetSnapshot(
        primaryHostID: nil,
        hosts: [],
        health: [],
        recentSamples: [],
        networkStatus: .connected
    )

    public var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > 15 * 60
    }
}

public struct WidgetHost: Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var address: String
    public var method: PingMethod
    public var port: UInt16?
    public var isPrimary: Bool

    public init(
        id: UUID,
        displayName: String,
        address: String,
        method: PingMethod,
        port: UInt16?,
        isPrimary: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.address = address
        self.method = method
        self.port = port
        self.isPrimary = isPrimary
    }
}

public struct WidgetHostHealth: Codable, Equatable, Sendable {
    public var hostID: UUID
    public var status: HealthStatus
    public var latencyMilliseconds: Double?
    public var consecutiveFailureCount: Int
    public var failureReason: FailureReason?
    public var latestResultAt: Date?

    public init(
        hostID: UUID,
        status: HealthStatus,
        latencyMilliseconds: Double?,
        consecutiveFailureCount: Int,
        failureReason: FailureReason?,
        latestResultAt: Date?
    ) {
        self.hostID = hostID
        self.status = status
        self.latencyMilliseconds = latencyMilliseconds
        self.consecutiveFailureCount = consecutiveFailureCount
        self.failureReason = failureReason
        self.latestResultAt = latestResultAt
    }
}

public struct WidgetSample: Codable, Equatable, Sendable {
    public var id: UUID
    public var hostID: UUID
    public var timestamp: Date
    public var latencyMilliseconds: Double?
    public var failureReason: FailureReason?

    public init(result: PingResult) {
        self.id = result.id
        self.hostID = result.hostID
        self.timestamp = result.timestamp
        self.latencyMilliseconds = result.latency?.milliseconds
        self.failureReason = result.failureReason
    }
}

public actor WidgetSnapshotStore {
    public static let defaultSuiteName = "6R7S5GA944.group.com.hadm.PingScope"
    public static let defaultKey = "PingScopeWidgetSnapshot"
    public static let legacyKey = "widgetData"

    private let defaults: UserDefaults
    private let key: String

    public init(suiteName: String? = defaultSuiteName, key: String = defaultKey) {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
        self.key = key
    }

    public init(defaults: UserDefaults, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func save(_ snapshot: WidgetSnapshot) async {
        guard let data = try? JSONEncoder.widgetSnapshotEncoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        if let legacyData = try? JSONEncoder.widgetSnapshotEncoder.encode(LegacyWidgetData(snapshot: snapshot)) {
            defaults.set(legacyData, forKey: Self.legacyKey)
        }
    }

    public func load() async -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.widgetSnapshotDecoder.decode(WidgetSnapshot.self, from: data)
    }

    public func delete() async {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: Self.legacyKey)
    }
}

private struct LegacyWidgetData: Codable, Equatable, Sendable {
    var version: Int = 1
    var results: [SimplifiedPingResult]
    var hosts: [SimplifiedHost]
    var lastUpdate: Date

    init(snapshot: WidgetSnapshot) {
        let latestByHost = Dictionary(grouping: snapshot.recentSamples, by: \.hostID).compactMapValues { samples in
            samples.max { $0.timestamp < $1.timestamp }
        }
        let healthByHost = Dictionary(uniqueKeysWithValues: snapshot.health.map { ($0.hostID, $0) })
        self.hosts = snapshot.hosts.map {
            SimplifiedHost(id: $0.id, name: $0.displayName, address: $0.address)
        }
        self.results = snapshot.hosts.map { host in
            let latest = latestByHost[host.id]
            let health = healthByHost[host.id]
            return SimplifiedPingResult(
                hostID: host.id,
                latencyMS: latest?.latencyMilliseconds ?? health?.latencyMilliseconds,
                isSuccess: (latest?.failureReason ?? health?.failureReason) == nil && (latest?.latencyMilliseconds ?? health?.latencyMilliseconds) != nil,
                timestamp: latest?.timestamp ?? health?.latestResultAt ?? snapshot.generatedAt
            )
        }
        self.lastUpdate = snapshot.generatedAt
    }

    struct SimplifiedPingResult: Codable, Equatable, Sendable {
        var hostID: UUID
        var latencyMS: Double?
        var isSuccess: Bool
        var timestamp: Date
    }

    struct SimplifiedHost: Codable, Equatable, Sendable {
        var id: UUID
        var name: String
        var address: String
    }
}

private extension JSONEncoder {
    static var widgetSnapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var widgetSnapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

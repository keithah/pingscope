import Foundation

struct WidgetData: Codable, Equatable, Sendable {
    var version: Int
    var results: [SimplifiedPingResult]
    var hosts: [SimplifiedHost]
    var lastUpdate: Date

    init(
        version: Int = 1,
        results: [SimplifiedPingResult],
        hosts: [SimplifiedHost],
        lastUpdate: Date
    ) {
        self.version = version
        self.results = results
        self.hosts = hosts
        self.lastUpdate = lastUpdate
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

    static let placeholder = WidgetData(
        results: [],
        hosts: [],
        lastUpdate: Date()
    )

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdate) > 15 * 60
    }
}

struct WidgetSnapshotData: Codable, Equatable, Sendable {
    var version: Int
    var primaryHostID: UUID?
    var hosts: [Host]
    var health: [HostHealth]
    var recentSamples: [Sample]
    var networkStatus: String
    var generatedAt: Date

    struct Host: Codable, Equatable, Sendable {
        var id: UUID
        var displayName: String
        var address: String
        var method: String
        var port: UInt16?
        var isPrimary: Bool
    }

    struct HostHealth: Codable, Equatable, Sendable {
        var hostID: UUID
        var status: String
        var latencyMilliseconds: Double?
        var consecutiveFailureCount: Int
        var failureReason: String?
        var latestResultAt: Date?
    }

    struct Sample: Codable, Equatable, Sendable {
        var id: UUID
        var hostID: UUID
        var timestamp: Date
        var latencyMilliseconds: Double?
        var failureReason: String?
    }

    var primaryHost: Host? {
        hosts.first { $0.id == primaryHostID } ?? hosts.first { $0.isPrimary } ?? hosts.first
    }

    var primaryHealth: HostHealth? {
        guard let primaryHost else { return nil }
        return health.first { $0.hostID == primaryHost.id }
    }

    var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > 15 * 60
    }

    var statusLabel: String {
        if isStale { return "Stale" }
        switch networkStatus {
        case "connected": return "Live"
        case "noInternet": return "No Internet"
        case "noIPAddress": return "No IP"
        case "notConnected": return "Offline"
        default: return "Unknown"
        }
    }
}

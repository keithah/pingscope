import Foundation
import PingScopeExtensionSupport

enum WidgetFreshness {
    static let staleInterval = WidgetTimelineSchedule.staleInterval
}

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
        isStale(at: Date())
    }

    func isStale(at date: Date) -> Bool {
        WidgetContentFreshness.isStale(contentGeneratedAt: lastUpdate, at: date)
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
    private var cachedHealthByHostID: [UUID: HostHealth]

    enum CodingKeys: String, CodingKey {
        case version
        case primaryHostID
        case hosts
        case health
        case recentSamples
        case networkStatus
        case generatedAt
    }

    struct Host: Codable, Equatable, Sendable {
        var id: UUID
        var displayName: String
        var address: String
        var method: String
        var port: UInt16?
        var isPrimary: Bool
        var displayColor: DisplayColor?
    }

    struct DisplayColor: Codable, Equatable, Sendable {
        var light: RGB
        var dark: RGB
    }

    struct RGB: Codable, Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
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

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        primaryHostID = try container.decodeIfPresent(UUID.self, forKey: .primaryHostID)
        hosts = try container.decode([Host].self, forKey: .hosts)
        health = try container.decode([HostHealth].self, forKey: .health)
        recentSamples = try container.decode([Sample].self, forKey: .recentSamples)
        networkStatus = try container.decode(String.self, forKey: .networkStatus)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        cachedHealthByHostID = Dictionary(uniqueKeysWithValues: health.map { ($0.hostID, $0) })
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(primaryHostID, forKey: .primaryHostID)
        try container.encode(hosts, forKey: .hosts)
        try container.encode(health, forKey: .health)
        try container.encode(recentSamples, forKey: .recentSamples)
        try container.encode(networkStatus, forKey: .networkStatus)
        try container.encode(generatedAt, forKey: .generatedAt)
    }

    var primaryHost: Host? {
        hosts.first { $0.id == primaryHostID } ?? hosts.first { $0.isPrimary } ?? hosts.first
    }

    var primaryHealth: HostHealth? {
        guard let primaryHost else { return nil }
        return cachedHealthByHostID[primaryHost.id]
    }

    var healthByHostID: [UUID: HostHealth] {
        cachedHealthByHostID
    }

    var graphPresentation: WidgetMultiHostGraphPresentation {
        WidgetMultiHostGraphPresentation(
            hosts: hosts.map {
                WidgetGraphHost(
                    id: $0.id,
                    displayName: $0.displayName,
                    displayColor: $0.displayColor.map {
                        WidgetGraphDisplayColor(
                            light: WidgetGraphRGB(red: $0.light.red, green: $0.light.green, blue: $0.light.blue),
                            dark: WidgetGraphRGB(red: $0.dark.red, green: $0.dark.green, blue: $0.dark.blue)
                        )
                    }
                )
            },
            samples: recentSamples.map {
                WidgetGraphSample(
                    id: $0.id,
                    hostID: $0.hostID,
                    timestamp: $0.timestamp,
                    latencyMilliseconds: $0.latencyMilliseconds
                )
            }
        )
    }

    var isStale: Bool {
        isStale(at: Date())
    }

    var statusLabel: String {
        statusLabel(at: Date())
    }

    func isStale(at date: Date) -> Bool {
        WidgetContentFreshness.isStale(contentGeneratedAt: generatedAt, at: date)
    }

    func statusLabel(at date: Date) -> String {
        if isStale(at: date) { return "Stale" }
        switch networkStatus {
        case "connected": return "Live"
        case "noInternet": return "No Internet"
        case "noIPAddress": return "No IP"
        case "notConnected": return "Offline"
        default: return "Unknown"
        }
    }
}

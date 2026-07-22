import Foundation

public struct WidgetSnapshotData: Codable, Equatable, Sendable {
    public var version: Int
    public var primaryHostID: UUID?
    public var hosts: [Host]
    public var health: [HostHealth]
    public var recentSamples: [Sample]
    public var networkStatus: String
    public var generatedAt: Date
    private var cachedHealthByHostID: [UUID: HostHealth]

    private enum CodingKeys: String, CodingKey {
        case version
        case primaryHostID
        case hosts
        case health
        case recentSamples
        case networkStatus
        case generatedAt
    }

    public struct Host: Codable, Equatable, Sendable {
        public var id: UUID
        public var displayName: String
        public var address: String
        public var method: String
        public var port: UInt16?
        public var isPrimary: Bool
        public var displayColor: DisplayColor?

        private enum CodingKeys: String, CodingKey {
            case id
            case displayName
            case address
            case method
            case port
            case isPrimary
            case displayColor
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            displayName = try container.decode(String.self, forKey: .displayName)
            address = try container.decode(String.self, forKey: .address)
            method = try container.decode(String.self, forKey: .method)
            port = try container.decodeIfPresent(UInt16.self, forKey: .port)
            isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
            displayColor = (try? container.decodeIfPresent(DisplayColor.self, forKey: .displayColor))?
                .validated
        }
    }

    public struct DisplayColor: Codable, Equatable, Sendable {
        public var light: RGB
        public var dark: RGB

        public init(light: RGB, dark: RGB) {
            self.light = light
            self.dark = dark
        }

        var validated: DisplayColor? {
            guard light.isValid, dark.isValid else { return nil }
            return self
        }
    }

    public struct RGB: Codable, Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var isValid: Bool {
            red.isFinite && green.isFinite && blue.isFinite
                && (0...1).contains(red) && (0...1).contains(green) && (0...1).contains(blue)
        }
    }

    public struct HostHealth: Codable, Equatable, Sendable {
        public var hostID: UUID
        public var status: String
        public var latencyMilliseconds: Double?
        public var consecutiveFailureCount: Int
        public var failureReason: String?
        public var latestResultAt: Date?
    }

    public struct Sample: Codable, Equatable, Sendable {
        public var id: UUID
        public var hostID: UUID
        public var timestamp: Date
        public var latencyMilliseconds: Double?
        public var failureReason: String?
    }

    public init(from decoder: any Decoder) throws {
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

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(primaryHostID, forKey: .primaryHostID)
        try container.encode(hosts, forKey: .hosts)
        try container.encode(health, forKey: .health)
        try container.encode(recentSamples, forKey: .recentSamples)
        try container.encode(networkStatus, forKey: .networkStatus)
        try container.encode(generatedAt, forKey: .generatedAt)
    }

    public var primaryHost: Host? {
        hosts.first { $0.id == primaryHostID } ?? hosts.first { $0.isPrimary } ?? hosts.first
    }

    public var primaryHealth: HostHealth? {
        guard let primaryHost else { return nil }
        return cachedHealthByHostID[primaryHost.id]
    }

    public var healthByHostID: [UUID: HostHealth] {
        cachedHealthByHostID
    }

    public var graphPresentation: WidgetMultiHostGraphPresentation {
        WidgetMultiHostGraphPresentation(
            hosts: hosts.map {
                WidgetGraphHost(
                    id: $0.id,
                    displayName: $0.displayName,
                    displayColor: $0.displayColor?.validated.map {
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

    public var isStale: Bool {
        isStale(at: Date())
    }

    public var statusLabel: String {
        statusLabel(at: Date())
    }

    public func isStale(at date: Date) -> Bool {
        WidgetContentFreshness.isStale(contentGeneratedAt: generatedAt, at: date)
    }

    public func statusLabel(at date: Date) -> String {
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

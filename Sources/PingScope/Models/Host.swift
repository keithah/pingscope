import Foundation

/// Host configuration for ping monitoring
struct Host: Sendable, Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let address: String
    let port: UInt16
    let pingMethod: PingMethod
    let intervalOverride: Duration?
    let timeoutOverride: Duration?
    let greenThresholdMSOverride: Double?
    let yellowThresholdMSOverride: Double?
    let notificationsEnabled: Bool
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case port
        case pingMethod
        case intervalOverrideSeconds
        case timeoutOverrideSeconds
        case greenThresholdMSOverride
        case yellowThresholdMSOverride
        case notificationsEnabled
        case isDefault
        case protocolType
        case timeoutSeconds
    }

    private enum LegacyProtocolType: String, Codable {
        case tcp
        case udp
    }

    /// Create a new host with default values
    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: UInt16 = 443,
        pingMethod: PingMethod = .tcp,
        intervalOverride: Duration? = nil,
        timeout: Duration? = nil,
        greenThresholdMSOverride: Double? = nil,
        yellowThresholdMSOverride: Double? = nil,
        notificationsEnabled: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.pingMethod = pingMethod
        self.intervalOverride = intervalOverride
        self.timeoutOverride = timeout
        self.greenThresholdMSOverride = greenThresholdMSOverride
        self.yellowThresholdMSOverride = yellowThresholdMSOverride
        self.notificationsEnabled = notificationsEnabled
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        port = try container.decode(UInt16.self, forKey: .port)

        if let pingMethod = try container.decodeIfPresent(PingMethod.self, forKey: .pingMethod) {
            self.pingMethod = pingMethod
        } else {
            let legacyProtocolType = try container.decodeIfPresent(LegacyProtocolType.self, forKey: .protocolType) ?? .tcp
            self.pingMethod = legacyProtocolType == .udp ? .udp : .tcp
        }

        if let intervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .intervalOverrideSeconds) {
            intervalOverride = .seconds(intervalSeconds)
        } else {
            intervalOverride = nil
        }

        if let timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutOverrideSeconds) {
            timeoutOverride = .seconds(timeoutSeconds)
        } else if let legacyTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds) {
            timeoutOverride = .seconds(legacyTimeoutSeconds)
        } else {
            timeoutOverride = nil
        }

        greenThresholdMSOverride = try container.decodeIfPresent(Double.self, forKey: .greenThresholdMSOverride)
        yellowThresholdMSOverride = try container.decodeIfPresent(Double.self, forKey: .yellowThresholdMSOverride)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(port, forKey: .port)
        try container.encode(pingMethod, forKey: .pingMethod)
        try container.encodeIfPresent(intervalOverride.map(Self.durationToTimeInterval), forKey: .intervalOverrideSeconds)
        try container.encodeIfPresent(timeoutOverride.map(Self.durationToTimeInterval), forKey: .timeoutOverrideSeconds)
        try container.encodeIfPresent(greenThresholdMSOverride, forKey: .greenThresholdMSOverride)
        try container.encodeIfPresent(yellowThresholdMSOverride, forKey: .yellowThresholdMSOverride)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(isDefault, forKey: .isDefault)
    }

    func effectiveInterval(_ globals: GlobalDefaults) -> Duration {
        intervalOverride ?? globals.interval
    }

    func effectiveTimeout(_ globals: GlobalDefaults) -> Duration {
        timeoutOverride ?? globals.timeout
    }

    func effectiveGreenThresholdMS(_ globals: GlobalDefaults) -> Double {
        greenThresholdMSOverride ?? globals.greenThresholdMS
    }

    func effectiveYellowThresholdMS(_ globals: GlobalDefaults) -> Double {
        yellowThresholdMSOverride ?? globals.yellowThresholdMS
    }

    private static func durationToTimeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }

    /// Google DNS default host
    static let googleDNS = Host(
        name: "Google DNS",
        address: "8.8.8.8",
        port: 443,
        pingMethod: .tcp,
        timeout: .seconds(3),
        notificationsEnabled: true,
        isDefault: true
    )

    /// Cloudflare DNS default host
    static let cloudflareDNS = Host(
        name: "Cloudflare",
        address: "1.1.1.1",
        port: 443,
        pingMethod: .tcp,
        timeout: .seconds(3),
        notificationsEnabled: true,
        isDefault: true
    )

    static let defaults: [Host] = [googleDNS, cloudflareDNS]
}

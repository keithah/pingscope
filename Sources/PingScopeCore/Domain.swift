import Foundation

public enum NetworkTier: String, CaseIterable, Codable, Equatable, Sendable {
    case localGateway
    case ispEdge
    case upstream
    case remoteService

    public var depth: Int {
        switch self {
        case .localGateway: 0
        case .ispEdge: 1
        case .upstream: 2
        case .remoteService: 3
        }
    }

    public var displayName: String {
        switch self {
        case .localGateway: "Router / gateway"
        case .ispEdge: "ISP / modem path"
        case .upstream: "Internet"
        case .remoteService: "Website or service"
        }
    }

    public var settingsName: String {
        switch self {
        case .localGateway: "Router / gateway"
        case .ispEdge: "ISP / modem path"
        case .upstream: "Internet check"
        case .remoteService: "Website or service"
        }
    }

    public var helpText: String {
        switch self {
        case .localGateway:
            "Your local router or default gateway. If this fails, the local network is probably the problem."
        case .ispEdge:
            "The next hop after your router, modem, satellite dish, or ISP edge. If this fails while the router works, blame the WAN path."
        case .upstream:
            "A general internet target such as public DNS. If this fails while local/ISP checks work, the broader internet path is suspect."
        case .remoteService:
            "A specific website, API, or service. If this fails while internet checks work, that service is probably isolated."
        }
    }

    public var shortName: String {
        switch self {
        case .localGateway: "Router"
        case .ispEdge: "ISP"
        case .upstream: "Internet"
        case .remoteService: "Service"
        }
    }
}

public struct HostConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var address: String
    public var tier: NetworkTier?
    public var method: PingMethod
    public var port: UInt16?
    public var interval: Duration
    public var timeout: Duration
    public var thresholds: LatencyThresholds
    public var isEnabled: Bool
    public var notifications: HostNotificationPolicy

    public init(
        id: UUID = UUID(),
        displayName: String,
        address: String,
        tier: NetworkTier? = nil,
        method: PingMethod = .tcp,
        port: UInt16? = 443,
        interval: Duration = .seconds(2),
        timeout: Duration = .seconds(2),
        thresholds: LatencyThresholds = .defaults,
        isEnabled: Bool = true,
        notifications: HostNotificationPolicy = .inherit
    ) {
        self.id = id
        self.displayName = displayName
        self.address = address
        self.tier = tier
        self.method = method
        self.port = port
        self.interval = interval
        self.timeout = timeout
        self.thresholds = thresholds
        self.isEnabled = isEnabled
        self.notifications = notifications
    }

    public static let defaultInternet = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1", method: .icmp, port: nil)
    public static let defaultGoogleDNS = HostConfig(displayName: "Google DNS", address: "8.8.8.8", method: .icmp, port: nil)
    public static let fallbackDefaultGatewayAddress = "192.168.1.1"
    public static let defaultGateway = defaultGatewayHost(address: fallbackDefaultGatewayAddress)

    public static func defaultGatewayHost(address: String) -> HostConfig {
        HostConfig(
            displayName: "Default Gateway",
            address: address,
            tier: .localGateway,
            method: .icmp,
            port: nil,
            interval: .seconds(2),
            timeout: .seconds(1),
            thresholds: LatencyThresholds(degradedMilliseconds: 20, downAfterFailures: 3)
        )
    }

    public static func defaultHosts(gatewayAddress: String? = nil) -> [HostConfig] {
        [
            defaultInternet,
            defaultGoogleDNS,
            defaultGatewayHost(address: gatewayAddress ?? fallbackDefaultGatewayAddress)
        ]
    }
    public static let defaultStarlinkDish = HostConfig(
        displayName: "Starlink",
        address: "192.168.100.1",
        tier: .localGateway,
        method: .starlink,
        port: PingMethod.starlink.defaultPort,
        interval: .seconds(5),
        timeout: .seconds(2),
        thresholds: LatencyThresholds(degradedMilliseconds: 150, downAfterFailures: 3)
    )
    public static let starlinkDiscoveryCandidates: [HostConfig] = [
        .defaultStarlinkDish,
        HostConfig(
            displayName: "Starlink",
            address: "192.168.1.1",
            tier: .localGateway,
            method: .starlink,
            port: 9000,
            interval: .seconds(5),
            timeout: .seconds(2),
            thresholds: LatencyThresholds(degradedMilliseconds: 150, downAfterFailures: 3)
        ),
        HostConfig(
            displayName: "Starlink",
            address: "192.168.1.1",
            tier: .localGateway,
            method: .starlink,
            port: PingMethod.starlink.defaultPort,
            interval: .seconds(5),
            timeout: .seconds(2),
            thresholds: LatencyThresholds(degradedMilliseconds: 150, downAfterFailures: 3)
        )
    ]

    public var validationErrors: [HostValidationError] {
        var errors: [HostValidationError] = []
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingDisplayName)
        }
        if trimmedAddress.isEmpty {
            errors.append(.missingAddress)
        } else if trimmedAddress.hasPrefix("-") || trimmedAddress.rangeOfCharacter(from: .controlCharacters) != nil {
            errors.append(.invalidAddress)
        }
        if method != .icmp, port == nil {
            errors.append(.invalidPort)
        } else if let port, port == 0 {
            errors.append(.invalidPort)
        }
        if interval < .milliseconds(250) {
            errors.append(.intervalTooShort)
        }
        if timeout < .milliseconds(250) {
            errors.append(.timeoutTooShort)
        }
        if thresholds.degradedMilliseconds < 1 {
            errors.append(.degradedThresholdTooLow)
        }
        return errors
    }

    public mutating func apply(method: PingMethod) {
        self.method = method
        self.port = method.defaultPort
    }

    public var requiresLocalNetworkPermission: Bool {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedAddress = normalizedAddress.lowercased()
        if Self.isLocalIPv6Literal(lowercasedAddress) {
            return true
        }

        let parts = normalizedAddress.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        if parts[0] == 10 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 169, parts[1] == 254 { return true }
        if parts[0] == 127 { return true }
        return false
    }

    public var effectiveNetworkTier: NetworkTier {
        NetworkTierClassifier().tier(for: self)
    }

    public func sanitizedForStorage() -> HostConfig? {
        var host = self
        host.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        host.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        host.interval = min(max(interval, .milliseconds(250)), .seconds(86_400))
        host.timeout = min(max(timeout, .milliseconds(250)), .seconds(60))
        host.thresholds.degradedMilliseconds = max(1, thresholds.degradedMilliseconds)
        host.thresholds.downAfterFailures = max(1, thresholds.downAfterFailures)
        return host.validationErrors.isEmpty ? host : nil
    }

    public static func sanitizedHosts(_ hosts: [HostConfig], limit: Int = 64) -> [HostConfig] {
        // Duplicate IDs (corrupt or hand-migrated blobs) must not survive: hosts
        // are keyed by ID in coordinators and history, and keyed dictionaries
        // built with uniqueKeysWithValues trap on duplicates.
        var seenIDs = Set<UUID>()
        let uniqueHosts = hosts.compactMap { host -> HostConfig? in
            guard let sanitized = host.sanitizedForStorage(),
                  seenIDs.insert(sanitized.id).inserted else { return nil }
            return sanitized
        }
        return Array(uniqueHosts.prefix(max(1, limit)))
    }

    private static func isLocalIPv6Literal(_ address: String) -> Bool {
        let literal = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if literal == "::1" { return true }
        if literal.hasPrefix("fe80:") { return true }
        if literal.hasPrefix("fc") || literal.hasPrefix("fd") { return true }
        return false
    }
}

public extension HostConfig {
    /// Stable gateway classification for UI scopes that intentionally omit the router.
    var isDefaultGateway: Bool {
        tier == .localGateway || displayName == "Default Gateway"
    }
}

public struct NetworkTierClassifier: Sendable {
    public init() {}

    public func tier(for host: HostConfig) -> NetworkTier {
        if let tier = host.tier {
            return tier
        }
        if host.method == .starlink {
            return .ispEdge
        }
        if host.displayName.localizedCaseInsensitiveContains("gateway") {
            return .localGateway
        }
        if host.requiresLocalNetworkPermission {
            return .localGateway
        }
        if Self.knownUpstreamAddresses.contains(host.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return .upstream
        }
        return .remoteService
    }

    private static let knownUpstreamAddresses: Set<String> = [
        "1.1.1.1",
        "1.0.0.1",
        "8.8.8.8",
        "8.8.4.4",
        "9.9.9.9",
        "149.112.112.112",
        "208.67.222.222",
        "208.67.220.220"
    ]
}

public enum HostValidationError: String, Codable, Equatable, Sendable {
    case missingDisplayName
    case missingAddress
    case invalidAddress
    case invalidPort
    case intervalTooShort
    case timeoutTooShort
    case degradedThresholdTooLow
}

public enum PingMethod: String, CaseIterable, Codable, Sendable {
    case https
    case tcp
    case udp
    case icmp
    case starlink

    public var defaultPort: UInt16? {
        switch self {
        case .https: 443
        case .tcp: 443
        case .udp: 53
        case .icmp: nil
        case .starlink: 9200
        }
    }

    public var displayName: String {
        switch self {
        case .https: "HTTPS"
        case .tcp: "TCP"
        case .udp: "UDP"
        case .icmp: "ICMP"
        case .starlink: "Starlink"
        }
    }

    public static var appStoreAvailableCases: [PingMethod] {
        [.https, .tcp, .udp, .starlink]
    }
}

public struct LatencyThresholds: Codable, Equatable, Sendable {
    public var degradedMilliseconds: Double
    public var downAfterFailures: Int

    public init(degradedMilliseconds: Double = 100, downAfterFailures: Int = 3) {
        self.degradedMilliseconds = degradedMilliseconds
        self.downAfterFailures = max(1, downAfterFailures)
    }

    public static let defaults = LatencyThresholds()
}

public enum HostNotificationPolicy: String, CaseIterable, Codable, Sendable {
    case inherit
    case muted
    case enabled

    public var displayName: String {
        switch self {
        case .inherit: "Use Global Settings"
        case .enabled: "Always Notify"
        case .muted: "Muted"
        }
    }
}

public enum FailureReason: String, Codable, Equatable, Sendable {
    case timeout
    case dnsFailure
    case connectionRefused
    case networkUnavailable
    case cancelled
    case icmpUnavailable
    case starlinkUnavailable
    case unknown

    public var userMessage: String {
        switch self {
        case .timeout: "Timed out"
        case .dnsFailure: "DNS failed"
        case .connectionRefused: "Connection refused"
        case .networkUnavailable: "Network unavailable"
        case .cancelled: "Cancelled"
        case .icmpUnavailable: "ICMP unavailable"
        case .starlinkUnavailable: "Starlink unavailable"
        case .unknown: "No response"
        }
    }
}

public struct ProbeMetadata: Codable, Equatable, Sendable {
    public var note: String?
    public var starlink: StarlinkTelemetry?

    public init(note: String? = nil, starlink: StarlinkTelemetry? = nil) {
        self.note = note
        self.starlink = starlink
    }
}

public struct StarlinkTelemetry: Codable, Equatable, Sendable {
    public var state: String?
    public var popPingDropRate: Double?
    public var downlinkThroughputBps: Double?
    public var uplinkThroughputBps: Double?
    public var fractionObstructed: Double?
    public var last24hObstructedSeconds: Double?
    public var uptimeSeconds: Double?
    public var hardwareVersion: String?
    public var softwareVersion: String?
    public var countryCode: String?
    public var activeAlerts: [String]

    public init(
        state: String? = nil,
        popPingDropRate: Double? = nil,
        downlinkThroughputBps: Double? = nil,
        uplinkThroughputBps: Double? = nil,
        fractionObstructed: Double? = nil,
        last24hObstructedSeconds: Double? = nil,
        uptimeSeconds: Double? = nil,
        hardwareVersion: String? = nil,
        softwareVersion: String? = nil,
        countryCode: String? = nil,
        activeAlerts: [String] = []
    ) {
        self.state = state
        self.popPingDropRate = popPingDropRate.map(Self.clampedDropRate)
        self.downlinkThroughputBps = downlinkThroughputBps
        self.uplinkThroughputBps = uplinkThroughputBps
        self.fractionObstructed = fractionObstructed
        self.last24hObstructedSeconds = last24hObstructedSeconds
        self.uptimeSeconds = uptimeSeconds
        self.hardwareVersion = hardwareVersion
        self.softwareVersion = softwareVersion
        self.countryCode = countryCode
        self.activeAlerts = activeAlerts
    }

    public var noteSummary: String {
        var parts: [String] = []
        if let state, !state.isEmpty {
            parts.append("state=\(state)")
        }
        if let popPingDropRate {
            parts.append("drop=\(Int((popPingDropRate * 100).rounded()))%")
        }
        if let fractionObstructed {
            parts.append("obstructed=\(Int((fractionObstructed * 100).rounded()))%")
        }
        if !activeAlerts.isEmpty {
            parts.append("alerts=\(activeAlerts.joined(separator: "|"))")
        }
        return parts.isEmpty ? "Starlink dish status" : parts.joined(separator: " ")
    }

    private static func clampedDropRate(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct SampleLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double?
    public var networkName: String?
    public var networkInterface: String?

    public init?(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double? = nil,
        networkName: String? = nil,
        networkInterface: String? = nil
    ) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }

        self.latitude = latitude
        self.longitude = longitude
        if let horizontalAccuracy, horizontalAccuracy.isFinite, horizontalAccuracy >= 0 {
            self.horizontalAccuracy = horizontalAccuracy
        } else {
            self.horizontalAccuracy = nil
        }
        self.networkName = networkName
        self.networkInterface = Self.normalizedInterface(networkInterface)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case horizontalAccuracy
        case networkName
        case networkInterface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        let horizontalAccuracy = try container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy)
        let networkName = try container.decodeIfPresent(String.self, forKey: .networkName)
        let networkInterface = try container.decodeIfPresent(String.self, forKey: .networkInterface)

        guard let normalized = SampleLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            networkName: networkName,
            networkInterface: networkInterface
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude,
                in: container,
                debugDescription: "Location coordinates must be finite and within valid ranges."
            )
        }
        self = normalized
    }

    private static func normalizedInterface(_ value: String?) -> String? {
        guard let value else { return nil }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "wifi": "wifi"
        case "cellular": "cellular"
        case "wired": "wired"
        default: "other"
        }
    }
}

public struct PingResult: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var hostID: UUID
    public var address: String
    public var method: PingMethod
    public var port: UInt16?
    public var timestamp: Date
    public var latency: Duration?
    public var failureReason: FailureReason?
    public var metadata: ProbeMetadata
    public var location: SampleLocation?

    private enum CodingKeys: String, CodingKey {
        case id
        case hostID
        case address
        case method
        case port
        case timestamp
        case latency
        case failureReason
        case metadata
        case location
    }

    public init(
        id: UUID = UUID(),
        hostID: UUID,
        address: String = "",
        method: PingMethod = .tcp,
        port: UInt16? = 443,
        timestamp: Date = Date(),
        latency: Duration?,
        failureReason: FailureReason?,
        metadata: ProbeMetadata = ProbeMetadata(),
        location: SampleLocation? = nil
    ) {
        self.id = id
        self.hostID = hostID
        self.address = address
        self.method = method
        self.port = port
        self.timestamp = timestamp
        self.latency = latency
        self.failureReason = failureReason
        self.metadata = metadata
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        address = try container.decode(String.self, forKey: .address)
        method = try container.decode(PingMethod.self, forKey: .method)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latency = try container.decodeIfPresent(Duration.self, forKey: .latency)
        failureReason = try container.decodeIfPresent(FailureReason.self, forKey: .failureReason)
        metadata = try container.decode(ProbeMetadata.self, forKey: .metadata)
        location = (try? container.decodeIfPresent(SampleLocation.self, forKey: .location)) ?? nil
    }

    public var isSuccess: Bool {
        latency != nil && failureReason == nil
    }

    public static func success(
        hostID: UUID,
        latency: Duration,
        timestamp: Date = Date(),
        metadata: ProbeMetadata = ProbeMetadata(),
        location: SampleLocation? = nil
    ) -> PingResult {
        PingResult(
            hostID: hostID,
            timestamp: timestamp,
            latency: latency,
            failureReason: nil,
            metadata: metadata,
            location: location
        )
    }

    public static func failure(
        hostID: UUID,
        reason: FailureReason,
        timestamp: Date = Date(),
        metadata: ProbeMetadata = ProbeMetadata(),
        location: SampleLocation? = nil
    ) -> PingResult {
        PingResult(
            hostID: hostID,
            timestamp: timestamp,
            latency: nil,
            failureReason: reason,
            metadata: metadata,
            location: location
        )
    }

    public func withHostMetadata(from host: HostConfig) -> PingResult {
        var copy = self
        copy.hostID = host.id
        copy.address = host.address
        copy.method = host.method
        copy.port = host.port
        return copy
    }
}

public enum HealthStatus: String, Codable, Equatable, Sendable {
    case noData
    case healthy
    case degraded
    case down
}

public enum NetworkConnectivityStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case connected
    case noInternet
    case noIPAddress
    case notConnected

    public static let defaultAlertStatuses: Set<NetworkConnectivityStatus> = [.noInternet]

    public var displayName: String {
        switch self {
        case .connected: "Connected"
        case .noInternet: "No Internet"
        case .noIPAddress: "No IP Address"
        case .notConnected: "Not Connected"
        }
    }

    public var defaultColorHex: String {
        switch self {
        case .connected: "#7DC45B"
        case .noInternet: "#F08A3C"
        case .noIPAddress: "#FFD24A"
        case .notConnected: "#F05B5F"
        }
    }
}

public enum DiagnosisAlertSensitivity: String, CaseIterable, Codable, Equatable, Sendable {
    case conservative
    case balanced
    case sensitive

    public var displayName: String {
        switch self {
        case .conservative: "Conservative"
        case .balanced: "Balanced"
        case .sensitive: "Sensitive"
        }
    }
}

public struct HostHealth: Codable, Equatable, Sendable {
    public var hostID: UUID
    public var latestResult: PingResult?
    public var consecutiveFailureCount: Int
    public var status: HealthStatus
    public var lastRecoveryTransition: Date?
    public var lastFailureTransition: Date?
    public var thresholds: LatencyThresholds

    public init(hostID: UUID, thresholds: LatencyThresholds = .defaults) {
        self.hostID = hostID
        self.latestResult = nil
        self.consecutiveFailureCount = 0
        self.status = .noData
        self.lastRecoveryTransition = nil
        self.lastFailureTransition = nil
        self.thresholds = thresholds
    }

    public mutating func ingest(_ result: PingResult) {
        let previous = status
        latestResult = result

        if let latency = result.latency {
            consecutiveFailureCount = 0
            let milliseconds = latency.milliseconds
            status = milliseconds >= thresholds.degradedMilliseconds ? .degraded : .healthy
        } else {
            consecutiveFailureCount += 1
            status = consecutiveFailureCount >= thresholds.downAfterFailures ? .down : .degraded
        }

        if previous == .down, status == .healthy || status == .degraded {
            lastRecoveryTransition = result.timestamp
        }
        if previous != .down, status == .down {
            lastFailureTransition = result.timestamp
        }
    }
}

public struct SampleSeries: Codable, Equatable, Sendable {
    public var hostID: UUID
    private var buffer: BoundedBuffer<PingResult>

    public var capacity: Int {
        get { buffer.capacity }
        set { buffer.setCapacity(newValue) }
    }

    public var samples: [PingResult] {
        buffer.elements
    }

    public init(hostID: UUID, capacity: Int = 300) {
        self.hostID = hostID
        self.buffer = BoundedBuffer(capacity: capacity)
    }

    public mutating func append(_ result: PingResult) {
        buffer.append(result)
    }

    public func samples(since cutoff: Date) -> [PingResult] {
        buffer.elements.filter { $0.timestamp >= cutoff }
    }

    public func recentSamples(limit: Int) -> [PingResult] {
        buffer.suffix(limit)
    }

    public var stats: SampleStats {
        SampleStats(samples: samples)
    }

    private enum CodingKeys: String, CodingKey {
        case hostID
        case capacity
        case samples
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        let capacity = try container.decode(Int.self, forKey: .capacity)
        let decodedSamples = try container.decode([PingResult].self, forKey: .samples)
        buffer = BoundedBuffer(elements: decodedSamples, capacity: capacity)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(samples, forKey: .samples)
    }

    public static func == (lhs: SampleSeries, rhs: SampleSeries) -> Bool {
        lhs.hostID == rhs.hostID
            && lhs.buffer == rhs.buffer
    }
}

public struct SampleStats: Equatable, Sendable {
    public let transmitted: Int
    public let received: Int
    public let lossPercent: Double
    public let minimumMilliseconds: Double?
    public let averageMilliseconds: Double?
    public let maximumMilliseconds: Double?

    public init(samples: [PingResult]) {
        transmitted = samples.count
        var receivedCount = 0
        var latencyTotal = 0.0
        var minimum: Double?
        var maximum: Double?
        var lossFraction = 0.0

        for sample in samples {
            if let latency = sample.latency?.milliseconds {
                receivedCount += 1
                latencyTotal += latency
                minimum = minimum.map { Swift.min($0, latency) } ?? latency
                maximum = maximum.map { Swift.max($0, latency) } ?? latency
            }
            if let starlinkDropRate = sample.metadata.starlink?.popPingDropRate {
                lossFraction += min(1, max(0, starlinkDropRate))
            } else {
                lossFraction += sample.isSuccess ? 0 : 1
            }
        }

        received = receivedCount
        lossPercent = transmitted == 0 ? 0 : (lossFraction / Double(transmitted)) * 100
        minimumMilliseconds = minimum
        maximumMilliseconds = maximum
        averageMilliseconds = receivedCount == 0 ? nil : latencyTotal / Double(receivedCount)
    }
}

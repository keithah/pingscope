import Foundation
import PingScopeExtensionSupport

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

public enum PingScopeLiveActivityMode: String, Codable, Hashable, Sendable {
    case focused
    case allHosts
}

public enum PingScopeLiveActivityHealthStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case noData
    case healthy
    case degraded
    case down
}

public enum PingScopeLiveActivityMethod: String, CaseIterable, Codable, Hashable, Sendable {
    case https
    case tcp
    case udp
    case icmp
    case starlink

    public var displayName: String {
        switch self {
        case .https: "HTTPS"
        case .tcp: "TCP"
        case .udp: "UDP"
        case .icmp: "ICMP"
        case .starlink: "Starlink"
        }
    }
}

public enum PingScopeLiveActivityDuration: String, CaseIterable, Codable, Hashable, Sendable {
    case continuous
    case thirtySeconds
    case oneMinute
}

public struct PingScopeLiveActivityHostRow: Codable, Hashable, Sendable {
    public static let sampleLimit = 12
    // These retain room for three rows, twelve Int samples each, and scalar state.
    public static let displayNameCharacterLimit = 24
    public static let displayNameUTF8ByteLimit = 72
    public static let endpointCaptionCharacterLimit = 48
    public static let endpointCaptionUTF8ByteLimit = 144

    public var hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public var status: PingScopeLiveActivityHealthStatus
    public var latestLatencyMilliseconds: Int?
    public let samples: [Int]
    public var isStale: Bool
    public let isDefaultGateway: Bool
    public let identityColor: WidgetGraphDisplayColor

    public init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: PingScopeLiveActivityHealthStatus,
        latestLatencyMilliseconds: Int?,
        samples: [Int],
        isStale: Bool,
        isDefaultGateway: Bool = false,
        identityColor: WidgetGraphDisplayColor? = nil
    ) {
        self.hostID = hostID
        self.displayName = boundedActivityPayloadString(
            displayName,
            characterLimit: Self.displayNameCharacterLimit,
            utf8ByteLimit: Self.displayNameUTF8ByteLimit
        )
        self.endpointCaption = boundedActivityPayloadString(
            endpointCaption,
            characterLimit: Self.endpointCaptionCharacterLimit,
            utf8ByteLimit: Self.endpointCaptionUTF8ByteLimit
        )
        self.status = status
        self.latestLatencyMilliseconds = latestLatencyMilliseconds
        self.samples = Array(samples.prefix(Self.sampleLimit))
        self.isStale = isStale
        self.isDefaultGateway = isDefaultGateway
        self.identityColor = identityColor?.validated ?? .automatic(for: hostID)
    }

    private enum CodingKeys: String, CodingKey {
        case hostID
        case displayName
        case endpointCaption
        case status
        case latestLatencyMilliseconds
        case samples
        case isStale
        case isDefaultGateway
        case identityColor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hostID: try container.decode(UUID.self, forKey: .hostID),
            displayName: try container.decode(String.self, forKey: .displayName),
            endpointCaption: try container.decode(String.self, forKey: .endpointCaption),
            status: try container.decode(PingScopeLiveActivityHealthStatus.self, forKey: .status),
            latestLatencyMilliseconds: try container.decodeIfPresent(Int.self, forKey: .latestLatencyMilliseconds),
            samples: try container.decode([Int].self, forKey: .samples),
            isStale: try container.decode(Bool.self, forKey: .isStale),
            isDefaultGateway: try container.decodeIfPresent(Bool.self, forKey: .isDefaultGateway) ?? false,
            identityColor: (try? container.decodeIfPresent(WidgetGraphDisplayColor.self, forKey: .identityColor)) ?? nil
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hostID)
        hasher.combine(displayName)
        hasher.combine(endpointCaption)
        hasher.combine(status)
        hasher.combine(latestLatencyMilliseconds)
        hasher.combine(samples)
        hasher.combine(isStale)
        hasher.combine(isDefaultGateway)
        hasher.combine(identityColor.light.red)
        hasher.combine(identityColor.light.green)
        hasher.combine(identityColor.light.blue)
        hasher.combine(identityColor.dark.red)
        hasher.combine(identityColor.dark.green)
        hasher.combine(identityColor.dark.blue)
    }

}

public struct PingScopeLiveActivityAttributes: Codable, Sendable {
    public static let hostNameCharacterLimit = PingScopeLiveActivityHostRow.displayNameCharacterLimit
    public static let hostNameUTF8ByteLimit = PingScopeLiveActivityHostRow.displayNameUTF8ByteLimit
    public static let addressCharacterLimit = 128
    public static let addressUTF8ByteLimit = 384

    public struct ContentState: Codable, Hashable, Sendable {
        public static let hostRowLimit = 3
        public static let failureMessageCharacterLimit = 64
        public static let failureMessageUTF8ByteLimit = 192

        public var latencyMilliseconds: Int?
        public var status: PingScopeLiveActivityHealthStatus
        public var lastUpdatedAt: Date?
        public var remainingSeconds: Int
        public var isStale: Bool
        public let failureMessage: String?
        public var mode: PingScopeLiveActivityMode
        public let hostRows: [PingScopeLiveActivityHostRow]
        public var showsDynamicIslandDetails: Bool

        public init(
            latencyMilliseconds: Int?,
            status: PingScopeLiveActivityHealthStatus,
            lastUpdatedAt: Date?,
            remainingSeconds: Int,
            isStale: Bool,
            failureMessage: String? = nil,
            mode: PingScopeLiveActivityMode = .focused,
            hostRows: [PingScopeLiveActivityHostRow] = [],
            showsDynamicIslandDetails: Bool = true
        ) {
            self.latencyMilliseconds = latencyMilliseconds
            self.status = status
            self.lastUpdatedAt = lastUpdatedAt
            self.remainingSeconds = max(0, remainingSeconds)
            self.isStale = isStale
            self.failureMessage = failureMessage.map {
                boundedActivityPayloadString(
                    $0,
                    characterLimit: Self.failureMessageCharacterLimit,
                    utf8ByteLimit: Self.failureMessageUTF8ByteLimit
                )
            }
            self.mode = mode
            self.hostRows = Array(hostRows.prefix(Self.hostRowLimit))
            self.showsDynamicIslandDetails = showsDynamicIslandDetails
        }

        private enum CodingKeys: String, CodingKey {
            case latencyMilliseconds
            case status
            case lastUpdatedAt
            case remainingSeconds
            case isStale
            case failureMessage
            case mode
            case hostRows
            case showsDynamicIslandDetails
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                latencyMilliseconds: try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds),
                status: try container.decode(PingScopeLiveActivityHealthStatus.self, forKey: .status),
                lastUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt),
                remainingSeconds: try container.decode(Int.self, forKey: .remainingSeconds),
                isStale: try container.decode(Bool.self, forKey: .isStale),
                failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
                mode: try container.decodeIfPresent(PingScopeLiveActivityMode.self, forKey: .mode) ?? .focused,
                hostRows: try container.decodeIfPresent([PingScopeLiveActivityHostRow].self, forKey: .hostRows) ?? [],
                showsDynamicIslandDetails: try container.decodeIfPresent(Bool.self, forKey: .showsDynamicIslandDetails) ?? true
            )
        }
    }

    public let hostID: UUID
    public let hostName: String
    public let address: String
    public let method: PingScopeLiveActivityMethod
    public let duration: PingScopeLiveActivityDuration
    public let identityColor: WidgetGraphDisplayColor

    public init(
        hostID: UUID,
        hostName: String,
        address: String,
        method: PingScopeLiveActivityMethod,
        duration: PingScopeLiveActivityDuration,
        identityColor: WidgetGraphDisplayColor? = nil
    ) {
        self.hostID = hostID
        self.hostName = boundedActivityPayloadString(
            hostName,
            characterLimit: Self.hostNameCharacterLimit,
            utf8ByteLimit: Self.hostNameUTF8ByteLimit
        )
        self.address = boundedActivityPayloadString(
            address,
            characterLimit: Self.addressCharacterLimit,
            utf8ByteLimit: Self.addressUTF8ByteLimit
        )
        self.method = method
        self.duration = duration
        self.identityColor = identityColor?.validated ?? .automatic(for: hostID)
    }

    private enum CodingKeys: String, CodingKey {
        case hostID
        case hostName
        case address
        case method
        case duration
        case identityColor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hostID: try container.decode(UUID.self, forKey: .hostID),
            hostName: try container.decode(String.self, forKey: .hostName),
            address: try container.decode(String.self, forKey: .address),
            method: try container.decode(PingScopeLiveActivityMethod.self, forKey: .method),
            duration: try container.decode(PingScopeLiveActivityDuration.self, forKey: .duration),
            identityColor: (try? container.decodeIfPresent(WidgetGraphDisplayColor.self, forKey: .identityColor)) ?? nil
        )
    }
}

private extension WidgetGraphDisplayColor {
    var validated: WidgetGraphDisplayColor? {
        guard light.isValid, dark.isValid else { return nil }
        return self
    }
}

private extension WidgetGraphRGB {
    var isValid: Bool {
        red.isFinite && green.isFinite && blue.isFinite
            && (0...1).contains(red) && (0...1).contains(green) && (0...1).contains(blue)
    }
}

private func boundedActivityPayloadString(
    _ value: String,
    characterLimit: Int,
    utf8ByteLimit: Int
) -> String {
    var bounded: [Character] = []
    bounded.reserveCapacity(characterLimit)
    var utf8ByteCount = 0

    for character in value {
        guard bounded.count < characterLimit else { break }
        let characterUTF8ByteCount = String(character).utf8.count
        guard utf8ByteCount + characterUTF8ByteCount <= utf8ByteLimit else { break }
        bounded.append(character)
        utf8ByteCount += characterUTF8ByteCount
    }
    return String(bounded)
}

#if os(iOS) && canImport(ActivityKit)
@available(iOS 16.2, *)
extension PingScopeLiveActivityAttributes: ActivityAttributes {}
#endif

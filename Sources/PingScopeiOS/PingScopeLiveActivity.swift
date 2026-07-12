import Foundation
import PingScopeCore

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

public enum PingScopeLiveActivityMode: String, Codable, Hashable, Sendable {
    case focused
    case allHosts
}

public struct PingScopeLiveActivityHostRow: Codable, Hashable, Sendable {
    public static let sampleLimit = PingScopeIOSLatencySampleReducer.defaultLimit
    // These retain room for three rows, twelve Int samples each, and scalar state.
    public static let displayNameCharacterLimit = 24
    public static let displayNameUTF8ByteLimit = 72
    public static let endpointCaptionCharacterLimit = 48
    public static let endpointCaptionUTF8ByteLimit = 144

    public var hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public var status: HealthStatus
    public var latestLatencyMilliseconds: Int?
    public let samples: [Int]
    public var isStale: Bool

    public init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: HealthStatus,
        latestLatencyMilliseconds: Int?,
        samples: [Int],
        isStale: Bool
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
    }

    public init(snapshot: PingScopeIOSHostRowSnapshot) {
        self.init(
            hostID: snapshot.hostID,
            displayName: snapshot.displayName,
            endpointCaption: snapshot.endpointCaption,
            status: snapshot.status,
            latestLatencyMilliseconds: snapshot.latestLatencyMilliseconds.map { Int($0.rounded()) },
            samples: PingScopeIOSLatencySampleReducer.reduce(snapshot.samples, limit: Self.sampleLimit)
                .compactMap { $0.latency.map { Int($0.milliseconds.rounded()) } },
            isStale: snapshot.isStale
        )
    }

    private enum CodingKeys: String, CodingKey {
        case hostID
        case displayName
        case endpointCaption
        case status
        case latestLatencyMilliseconds
        case samples
        case isStale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hostID: try container.decode(UUID.self, forKey: .hostID),
            displayName: try container.decode(String.self, forKey: .displayName),
            endpointCaption: try container.decode(String.self, forKey: .endpointCaption),
            status: try container.decode(HealthStatus.self, forKey: .status),
            latestLatencyMilliseconds: try container.decodeIfPresent(Int.self, forKey: .latestLatencyMilliseconds),
            samples: try container.decode([Int].self, forKey: .samples),
            isStale: try container.decode(Bool.self, forKey: .isStale)
        )
    }

}

public struct PingScopeLiveActivityAttributes: Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public static let hostRowLimit = PingScopeIOSHostScopePresentation.activityHostLimit
        public static let failureMessageCharacterLimit = 64
        public static let failureMessageUTF8ByteLimit = 192

        public var latencyMilliseconds: Int?
        public var status: HealthStatus
        public var lastUpdatedAt: Date?
        public var remainingSeconds: Int
        public var isStale: Bool
        public let failureMessage: String?
        public var mode: PingScopeLiveActivityMode
        public let hostRows: [PingScopeLiveActivityHostRow]

        public init(
            latencyMilliseconds: Int?,
            status: HealthStatus,
            lastUpdatedAt: Date?,
            remainingSeconds: Int,
            isStale: Bool,
            failureMessage: String? = nil,
            mode: PingScopeLiveActivityMode = .focused,
            hostRows: [PingScopeLiveActivityHostRow] = []
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
        }

        public init(session: MonitorSessionState, health: HostHealth?, at date: Date = Date()) {
            let latestResult = session.latestResult ?? health?.latestResult
            self.init(
                latencyMilliseconds: latestResult?.latency.map { Int($0.milliseconds.rounded()) },
                status: health?.status ?? .noData,
                lastUpdatedAt: latestResult?.timestamp,
                remainingSeconds: session.duration == .continuous ? 0 : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
                isStale: session.phase(at: date) != .live,
                failureMessage: latestResult?.failureReason?.userMessage
            )
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
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                latencyMilliseconds: try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds),
                status: try container.decode(HealthStatus.self, forKey: .status),
                lastUpdatedAt: try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt),
                remainingSeconds: try container.decode(Int.self, forKey: .remainingSeconds),
                isStale: try container.decode(Bool.self, forKey: .isStale),
                failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
                mode: try container.decodeIfPresent(PingScopeLiveActivityMode.self, forKey: .mode) ?? .focused,
                hostRows: try container.decodeIfPresent([PingScopeLiveActivityHostRow].self, forKey: .hostRows) ?? []
            )
        }
    }

    public var hostID: UUID
    public var hostName: String
    public var address: String
    public var method: PingMethod
    public var duration: MonitorSessionDuration

    public init(host: HostConfig, duration: MonitorSessionDuration) {
        self.hostID = host.id
        self.hostName = host.displayName
        self.address = host.address
        self.method = host.method
        self.duration = duration
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

import Foundation

public struct HostConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var address: String
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
        self.method = method
        self.port = port
        self.interval = interval
        self.timeout = timeout
        self.thresholds = thresholds
        self.isEnabled = isEnabled
        self.notifications = notifications
    }

    public static let defaultInternet = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1")

    public var validationErrors: [HostValidationError] {
        var errors: [HostValidationError] = []
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingDisplayName)
        }
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingAddress)
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
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        if parts[0] == 10 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 169, parts[1] == 254 { return true }
        if parts[0] == 127 { return true }
        return false
    }
}

public enum HostValidationError: String, Codable, Equatable, Sendable {
    case missingDisplayName
    case missingAddress
    case invalidPort
    case intervalTooShort
    case timeoutTooShort
    case degradedThresholdTooLow
}

public enum PingMethod: String, CaseIterable, Codable, Sendable {
    case tcp
    case udp
    case icmp

    public var defaultPort: UInt16? {
        switch self {
        case .tcp: 443
        case .udp: 53
        case .icmp: nil
        }
    }

    public static var appStoreAvailableCases: [PingMethod] {
        [.tcp, .udp]
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
    case unknown

    public var userMessage: String {
        switch self {
        case .timeout: "Timed out"
        case .dnsFailure: "DNS failed"
        case .connectionRefused: "Connection refused"
        case .networkUnavailable: "Network unavailable"
        case .cancelled: "Cancelled"
        case .icmpUnavailable: "ICMP unavailable"
        case .unknown: "No response"
        }
    }
}

public struct ProbeMetadata: Codable, Equatable, Sendable {
    public var note: String?

    public init(note: String? = nil) {
        self.note = note
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

    public init(
        id: UUID = UUID(),
        hostID: UUID,
        address: String = "",
        method: PingMethod = .tcp,
        port: UInt16? = 443,
        timestamp: Date = Date(),
        latency: Duration?,
        failureReason: FailureReason?,
        metadata: ProbeMetadata = ProbeMetadata()
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
    }

    public var isSuccess: Bool {
        latency != nil && failureReason == nil
    }

    public static func success(
        hostID: UUID,
        latency: Duration,
        timestamp: Date = Date(),
        metadata: ProbeMetadata = ProbeMetadata()
    ) -> PingResult {
        PingResult(hostID: hostID, timestamp: timestamp, latency: latency, failureReason: nil, metadata: metadata)
    }

    public static func failure(
        hostID: UUID,
        reason: FailureReason,
        timestamp: Date = Date(),
        metadata: ProbeMetadata = ProbeMetadata()
    ) -> PingResult {
        PingResult(hostID: hostID, timestamp: timestamp, latency: nil, failureReason: reason, metadata: metadata)
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
    public var capacity: Int
    public private(set) var samples: [PingResult]

    public init(hostID: UUID, capacity: Int = 300) {
        self.hostID = hostID
        self.capacity = max(1, capacity)
        self.samples = []
    }

    public mutating func append(_ result: PingResult) {
        samples.append(result)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public func samples(since cutoff: Date) -> [PingResult] {
        samples.filter { $0.timestamp >= cutoff }
    }

    public var stats: SampleStats {
        SampleStats(samples: samples)
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
        let latencies = samples.compactMap { $0.latency?.milliseconds }
        received = latencies.count
        lossPercent = transmitted == 0 ? 0 : (Double(transmitted - received) / Double(transmitted)) * 100
        minimumMilliseconds = latencies.min()
        maximumMilliseconds = latencies.max()
        averageMilliseconds = latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count)
    }
}

public struct NetworkPerspectiveDiagnosis: Equatable, Sendable {
    public enum Scope: String, Codable, Equatable, Sendable {
        case noData
        case allReachable
        case localNetwork
        case upstream
        case remoteService
        case partialDegradation
    }

    public var scope: Scope
    public var title: String
    public var detail: String
    public var affectedHostIDs: [UUID]

    public init(scope: Scope, title: String, detail: String, affectedHostIDs: [UUID] = []) {
        self.scope = scope
        self.title = title
        self.detail = detail
        self.affectedHostIDs = affectedHostIDs
    }
}

public struct NetworkPerspectiveDiagnoser: Sendable {
    public init() {}

    public func diagnose(hosts: [HostConfig], healthByHost: [UUID: HostHealth]) -> NetworkPerspectiveDiagnosis {
        let enabledHosts = hosts.filter(\.isEnabled)
        guard !enabledHosts.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No hosts enabled",
                detail: "Enable at least one host to diagnose network scope."
            )
        }

        let observed = enabledHosts.compactMap { host -> (host: HostConfig, health: HostHealth)? in
            guard let health = healthByHost[host.id], health.latestResult != nil else { return nil }
            return (host, health)
        }
        guard !observed.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No recent measurements",
                detail: "PingScope needs samples before it can infer what is down."
            )
        }

        let down = observed.filter { $0.health.status == .down }
        let degraded = observed.filter { $0.health.status == .degraded }
        let healthy = observed.filter { $0.health.status == .healthy }
        let local = observed.filter { $0.host.isLocalNetworkAnchor }
        let remote = observed.filter { !$0.host.isLocalNetworkAnchor }
        let localDown = local.filter { $0.health.status == .down }
        let remoteDown = remote.filter { $0.health.status == .down }
        let remoteHealthy = remote.filter { $0.health.status == .healthy }

        if down.isEmpty {
            if degraded.isEmpty {
                return NetworkPerspectiveDiagnosis(
                    scope: .allReachable,
                    title: "Everything reachable",
                    detail: "\(healthy.count) monitored host\(healthy.count == 1 ? "" : "s") responding."
                )
            }
            return NetworkPerspectiveDiagnosis(
                scope: .partialDegradation,
                title: "Latency degraded",
                detail: names(degraded) + " above threshold.",
                affectedHostIDs: degraded.map(\.host.id)
            )
        }

        if let firstLocalDown = localDown.first {
            let title = firstLocalDown.host.displayName.localizedCaseInsensitiveContains("gateway") ? "Default gateway down" : "Local network down"
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: title,
                detail: "\(firstLocalDown.host.displayName) is not responding; failures beyond it may be local.",
                affectedHostIDs: localDown.map(\.host.id)
            )
        }

        if !remoteDown.isEmpty, !local.isEmpty, local.allSatisfy({ $0.health.status == .healthy || $0.health.status == .degraded }) {
            if remoteHealthy.isEmpty, remote.count == remoteDown.count {
                return NetworkPerspectiveDiagnosis(
                    scope: .upstream,
                    title: "Upstream or ISP path down",
                    detail: "Local hosts respond, but all monitored remote hosts are down.",
                    affectedHostIDs: remoteDown.map(\.host.id)
                )
            }

            return NetworkPerspectiveDiagnosis(
                scope: .remoteService,
                title: "Remote host down",
                detail: names(remoteDown) + " not responding while local path is reachable.",
                affectedHostIDs: remoteDown.map(\.host.id)
            )
        }

        if !remoteDown.isEmpty, !remoteHealthy.isEmpty {
            return NetworkPerspectiveDiagnosis(
                scope: .remoteService,
                title: "Remote host down",
                detail: names(remoteDown) + " not responding; other remote hosts are reachable.",
                affectedHostIDs: remoteDown.map(\.host.id)
            )
        }

        return NetworkPerspectiveDiagnosis(
            scope: .partialDegradation,
            title: "Multiple failures",
            detail: names(down) + " not responding.",
            affectedHostIDs: down.map(\.host.id)
        )
    }

    private func names(_ hostHealth: [(host: HostConfig, health: HostHealth)]) -> String {
        let names = hostHealth.prefix(3).map(\.host.displayName).joined(separator: ", ")
        let extraCount = hostHealth.count - 3
        return extraCount > 0 ? "\(names), +\(extraCount) more" : names
    }
}

private extension HostConfig {
    var isLocalNetworkAnchor: Bool {
        requiresLocalNetworkPermission || displayName.localizedCaseInsensitiveContains("gateway")
    }
}

public struct NotificationRuleSet: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var cooldown: Duration
    public var alertTypes: Set<AlertType>
    public var latencyThreshold: Duration
    public var notifyOnRecovery: Bool

    public init(
        isEnabled: Bool = true,
        cooldown: Duration = .seconds(300),
            alertTypes: Set<AlertType> = [.hostDown, .recovered, .highLatency, .networkChange, .internetLoss],
        latencyThreshold: Duration = .milliseconds(250),
        notifyOnRecovery: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.cooldown = cooldown
        self.alertTypes = alertTypes
        self.latencyThreshold = latencyThreshold
        self.notifyOnRecovery = notifyOnRecovery
    }
}

public enum AlertType: String, Codable, Hashable, Sendable {
    case hostDown
    case recovered
    case highLatency
    case networkChange
    case internetLoss
}

public enum AlertDecision: Equatable, Sendable {
    case hostDown(hostID: UUID)
    case recovered(hostID: UUID)
    case highLatency(hostID: UUID)
    case networkChange(previousGateway: String?, currentGateway: String?)
    case internetLoss
    case networkStatus(NetworkConnectivityStatus)
}

public struct AlertDecisionEngine: Sendable {
    public var rules: NotificationRuleSet
    private var lastSentAt: [AlertType: Date] = [:]

    public init(rules: NotificationRuleSet = NotificationRuleSet()) {
        self.rules = rules
    }

    public mutating func evaluate(
        result: PingResult,
        previousStatus: HealthStatus,
        currentStatus: HealthStatus
    ) -> AlertDecision? {
        guard rules.isEnabled else { return nil }

        let candidate: (AlertType, AlertDecision)?
        if currentStatus == .down, previousStatus != .down {
            candidate = (.hostDown, .hostDown(hostID: result.hostID))
        } else if previousStatus == .down, currentStatus != .down, rules.notifyOnRecovery {
            candidate = (.recovered, .recovered(hostID: result.hostID))
        } else if let latency = result.latency, latency >= rules.latencyThreshold {
            candidate = (.highLatency, .highLatency(hostID: result.hostID))
        } else {
            candidate = nil
        }

        guard let (type, decision) = candidate, rules.alertTypes.contains(type) else {
            return nil
        }
        guard shouldSend(type, at: result.timestamp) else {
            return nil
        }
        lastSentAt[type] = result.timestamp
        return decision
    }

    public mutating func evaluateNetworkChange(
        previousGateway: String?,
        currentGateway: String?,
        at date: Date = Date()
    ) -> AlertDecision? {
        guard rules.isEnabled,
              rules.alertTypes.contains(.networkChange),
              previousGateway != currentGateway
        else {
            return nil
        }
        guard shouldSend(.networkChange, at: date) else { return nil }
        lastSentAt[.networkChange] = date
        return .networkChange(previousGateway: previousGateway, currentGateway: currentGateway)
    }

    public mutating func evaluateInternetLoss(
        results: [PingResult],
        at date: Date = Date()
    ) -> AlertDecision? {
        guard rules.isEnabled,
              rules.alertTypes.contains(.internetLoss),
              !results.isEmpty,
              results.allSatisfy({ !$0.isSuccess })
        else {
            return nil
        }
        guard shouldSend(.internetLoss, at: date) else { return nil }
        lastSentAt[.internetLoss] = date
        return .internetLoss
    }

    private func shouldSend(_ type: AlertType, at date: Date) -> Bool {
        guard let lastSent = lastSentAt[type] else { return true }
        return date.timeIntervalSince(lastSent) >= rules.cooldown.seconds
    }
}

public extension Duration {
    var seconds: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    var milliseconds: Double {
        seconds * 1_000
    }
}

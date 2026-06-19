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

    public static let defaultInternet = HostConfig(displayName: "Cloudflare DNS", address: "1.1.1.1")
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

    public var effectiveNetworkTier: NetworkTier {
        NetworkTierClassifier().tier(for: self)
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
    case invalidPort
    case intervalTooShort
    case timeoutTooShort
    case degradedThresholdTooLow
}

public enum PingMethod: String, CaseIterable, Codable, Sendable {
    case tcp
    case udp
    case icmp
    case starlink

    public var defaultPort: UInt16? {
        switch self {
        case .tcp: 443
        case .udp: 53
        case .icmp: nil
        case .starlink: 9200
        }
    }

    public var displayName: String {
        switch self {
        case .tcp: "TCP"
        case .udp: "UDP"
        case .icmp: "ICMP"
        case .starlink: "Starlink"
        }
    }

    public static var appStoreAvailableCases: [PingMethod] {
        [.tcp, .udp, .starlink]
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
        let lossFraction: Double = samples.map { sample -> Double in
            if let starlinkDropRate = sample.metadata.starlink?.popPingDropRate {
                return min(1, max(0, starlinkDropRate))
            }
            return sample.isSuccess ? 0 : 1
        }.reduce(0.0) { $0 + $1 }
        lossPercent = transmitted == 0 ? 0 : (lossFraction / Double(transmitted)) * 100
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

    public enum Confidence: String, Codable, Equatable, Sendable {
        case high
        case tentative

        public var displayName: String {
            switch self {
            case .high: "High confidence"
            case .tentative: "Tentative"
            }
        }
    }

    public enum Verdict: Equatable, Sendable {
        case noData
        case allReachable
        case localNetworkDown
        case ispPathDown
        case upstreamDown
        case remoteServiceDown(hostIDs: [UUID])
        case partialDegradation(tier: NetworkTier)
        case multipleFailures(hostIDs: [UUID])
    }

    public struct TierEvidence: Equatable, Sendable {
        public var tier: NetworkTier
        public var totalCount: Int
        public var healthyCount: Int
        public var degradedCount: Int
        public var downCount: Int

        public init(
            tier: NetworkTier,
            totalCount: Int,
            healthyCount: Int,
            degradedCount: Int,
            downCount: Int
        ) {
            self.tier = tier
            self.totalCount = totalCount
            self.healthyCount = healthyCount
            self.degradedCount = degradedCount
            self.downCount = downCount
        }

        public var status: HealthStatus {
            if downCount > 0 { return .down }
            if degradedCount > 0 { return .degraded }
            if healthyCount > 0 { return .healthy }
            return .noData
        }

        public var summary: String {
            "\(healthyCount) ok, \(degradedCount) slow, \(downCount) down"
        }
    }

    public var scope: Scope
    public var title: String
    public var detail: String
    public var affectedHostIDs: [UUID]
    public var verdict: Verdict
    public var confidence: Confidence
    public var faultTier: NetworkTier?
    public var evidenceNote: String?
    public var tierEvidence: [TierEvidence]

    public init(
        scope: Scope,
        title: String,
        detail: String,
        affectedHostIDs: [UUID] = [],
        verdict: Verdict? = nil,
        confidence: Confidence = .high,
        faultTier: NetworkTier? = nil,
        evidenceNote: String? = nil,
        tierEvidence: [TierEvidence] = []
    ) {
        self.scope = scope
        self.title = title
        self.detail = detail
        self.affectedHostIDs = affectedHostIDs
        self.verdict = verdict ?? Self.defaultVerdict(scope: scope, affectedHostIDs: affectedHostIDs)
        self.confidence = confidence
        self.faultTier = faultTier
        self.evidenceNote = evidenceNote
        self.tierEvidence = tierEvidence
    }

    private static func defaultVerdict(scope: Scope, affectedHostIDs: [UUID]) -> Verdict {
        switch scope {
        case .noData: .noData
        case .allReachable: .allReachable
        case .localNetwork: .localNetworkDown
        case .upstream: .upstreamDown
        case .remoteService: .remoteServiceDown(hostIDs: affectedHostIDs)
        case .partialDegradation: .multipleFailures(hostIDs: affectedHostIDs)
        }
    }
}

public struct NetworkPerspectiveDiagnoser: Sendable {
    private struct ObservedHost {
        var host: HostConfig
        var health: HostHealth
        var tier: NetworkTier
    }

    private struct TierSummary {
        var tier: NetworkTier
        var observed: [ObservedHost]

        var down: [ObservedHost] {
            observed.filter { $0.health.status == .down }
        }

        var degraded: [ObservedHost] {
            observed.filter { $0.health.status == .degraded }
        }

        var healthy: [ObservedHost] {
            observed.filter { $0.health.status == .healthy }
        }

        var downRatio: Double {
            observed.isEmpty ? 0 : Double(down.count) / Double(observed.count)
        }

        var degradedRatio: Double {
            observed.isEmpty ? 0 : Double(degraded.count) / Double(observed.count)
        }

        var hasDown: Bool {
            !down.isEmpty
        }

        var hasDegraded: Bool {
            !degraded.isEmpty
        }
    }

    private let classifier: NetworkTierClassifier

    public init(classifier: NetworkTierClassifier = NetworkTierClassifier()) {
        self.classifier = classifier
    }

    public func diagnose(
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth],
        networkStatus: NetworkConnectivityStatus = .connected
    ) -> NetworkPerspectiveDiagnosis {
        let enabledHosts = hosts.filter(\.isEnabled)
        guard !enabledHosts.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No hosts enabled",
                detail: "Enable at least one host to diagnose network scope.",
                confidence: .tentative
            )
        }

        if let gatedDiagnosis = linkStateDiagnosis(for: networkStatus) {
            return gatedDiagnosis
        }

        let observed = enabledHosts.compactMap { host -> ObservedHost? in
            guard let health = healthByHost[host.id], health.latestResult != nil else { return nil }
            return ObservedHost(host: host, health: health, tier: classifier.tier(for: host))
        }
        guard !observed.isEmpty else {
            return NetworkPerspectiveDiagnosis(
                scope: .noData,
                title: "No recent measurements",
                detail: "PingScope needs samples before it can infer what is down.",
                confidence: .tentative
            )
        }

        let summaries = NetworkTier.allCases
            .map { tier in TierSummary(tier: tier, observed: observed.filter { $0.tier == tier }) }
            .filter { !$0.observed.isEmpty }
            .sorted { $0.tier.depth < $1.tier.depth }
        let tierEvidence = evidenceChain(from: summaries)

        let downSummaries = summaries.filter(\.hasDown)
        if downSummaries.isEmpty {
            let degradedSummaries = summaries.filter(\.hasDegraded)
            if degradedSummaries.isEmpty {
                let healthyCount = observed.filter { $0.health.status == .healthy }.count
                return NetworkPerspectiveDiagnosis(
                    scope: .allReachable,
                    title: "Everything reachable",
                    detail: "\(healthyCount) monitored host\(healthyCount == 1 ? "" : "s") responding.",
                    verdict: .allReachable,
                    confidence: .high,
                    evidenceNote: "\(healthyCount)/\(observed.count) monitored hosts healthy",
                    tierEvidence: tierEvidence
                )
            }
            let summary = degradedSummaries.sorted { $0.tier.depth < $1.tier.depth }.first!
            return NetworkPerspectiveDiagnosis(
                scope: .partialDegradation,
                title: "\(summary.tier.displayName) degraded",
                detail: names(summary.degraded) + " above threshold.",
                affectedHostIDs: summary.degraded.map(\.host.id),
                verdict: .partialDegradation(tier: summary.tier),
                confidence: confidence(for: summary, innerSummaries: innerSummaries(before: summary.tier, in: summaries)),
                faultTier: summary.tier,
                evidenceNote: evidence(for: summary, status: "degraded"),
                tierEvidence: tierEvidence
            )
        }

        let fault = downSummaries.sorted { $0.tier.depth < $1.tier.depth }.first!
        let affected = fault.down.map(\.host.id)
        let confidence = confidence(for: fault, innerSummaries: innerSummaries(before: fault.tier, in: summaries))
        let evidence = evidence(for: fault, status: "down")

        switch fault.tier {
        case .localGateway:
            let title = fault.down.contains { $0.host.displayName.localizedCaseInsensitiveContains("gateway") } ? "Default gateway down" : "Local network down"
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: title,
                detail: "\(names(fault.down)) not responding; failures beyond the router are unknown.",
                affectedHostIDs: affected,
                verdict: .localNetworkDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .ispEdge:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "ISP path down",
                detail: "The router responds, but the modem, dish, or ISP edge is not reachable.",
                affectedHostIDs: affected,
                verdict: .ispPathDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .upstream:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "Upstream path down",
                detail: "Router and ISP checks respond, but internet checks are not reachable.",
                affectedHostIDs: affected,
                verdict: .upstreamDown,
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        case .remoteService:
            return NetworkPerspectiveDiagnosis(
                scope: .remoteService,
                title: affected.count == 1 ? "Remote host down" : "Remote services down",
                detail: names(fault.down) + " not responding while inner tiers are reachable.",
                affectedHostIDs: affected,
                verdict: .remoteServiceDown(hostIDs: affected),
                confidence: confidence,
                faultTier: fault.tier,
                evidenceNote: evidence,
                tierEvidence: tierEvidence
            )
        }
    }

    private func innerSummaries(before tier: NetworkTier, in summaries: [TierSummary]) -> [TierSummary] {
        summaries.filter { $0.tier.depth < tier.depth }
    }

    private func linkStateDiagnosis(for status: NetworkConnectivityStatus) -> NetworkPerspectiveDiagnosis? {
        switch status {
        case .connected:
            return nil
        case .notConnected:
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: "Network disconnected",
                detail: "macOS reports no active network link, so PingScope is not blaming ISP or remote hosts.",
                verdict: .localNetworkDown,
                confidence: .high,
                faultTier: .localGateway,
                evidenceNote: status.displayName
            )
        case .noIPAddress:
            return NetworkPerspectiveDiagnosis(
                scope: .localNetwork,
                title: "No IP address",
                detail: "The local interface has no usable IP address; upstream diagnosis is suppressed.",
                verdict: .localNetworkDown,
                confidence: .high,
                faultTier: .localGateway,
                evidenceNote: status.displayName
            )
        case .noInternet:
            return NetworkPerspectiveDiagnosis(
                scope: .upstream,
                title: "No internet connection",
                detail: "macOS reports no internet route; PingScope will wait for connectivity before naming a host-specific failure.",
                verdict: .upstreamDown,
                confidence: .tentative,
                faultTier: .upstream,
                evidenceNote: status.displayName
            )
        }
    }

    private func confidence(for summary: TierSummary, innerSummaries: [TierSummary]) -> NetworkPerspectiveDiagnosis.Confidence {
        let boundaryIsClean = innerSummaries.allSatisfy { !$0.hasDown }
        guard boundaryIsClean else { return .tentative }
        if summary.observed.count == 1 {
            return summary.down.first?.health.consecutiveFailureCount ?? 0 > 1 || summary.downRatio >= 1 ? .high : .tentative
        }
        return summary.downRatio >= 0.75 || summary.degradedRatio >= 0.75 ? .high : .tentative
    }

    private func evidence(for summary: TierSummary, status: String) -> String {
        let matchingCount = status == "degraded" ? summary.degraded.count : summary.down.count
        return "\(matchingCount)/\(summary.observed.count) \(summary.tier.displayName.lowercased()) host\(summary.observed.count == 1 ? "" : "s") \(status)"
    }

    private func evidenceChain(from summaries: [TierSummary]) -> [NetworkPerspectiveDiagnosis.TierEvidence] {
        summaries.map { summary in
            NetworkPerspectiveDiagnosis.TierEvidence(
                tier: summary.tier,
                totalCount: summary.observed.count,
                healthyCount: summary.healthy.count,
                degradedCount: summary.degraded.count,
                downCount: summary.down.count
            )
        }
    }

    private func names(_ hostHealth: [ObservedHost]) -> String {
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
        alertTypes: Set<AlertType> = [
            .hostDown,
            .recovered,
            .highLatency,
            .networkChange,
            .internetLoss,
            .localNetworkDown,
            .ispPathDown,
            .upstreamDown,
            .remoteServiceDown
        ],
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
    case localNetworkDown
    case ispPathDown
    case upstreamDown
    case remoteServiceDown
    case pathDegraded
}

public enum AlertDecision: Equatable, Sendable {
    case hostDown(hostID: UUID)
    case recovered(hostID: UUID)
    case highLatency(hostID: UUID)
    case networkChange(previousGateway: String?, currentGateway: String?)
    case internetLoss
    case networkStatus(NetworkConnectivityStatus)
    case localNetworkDown
    case ispPathDown
    case upstreamDown
    case remoteServiceDown(hostIDs: [UUID])
    case pathDegraded(tier: NetworkTier)
    case pathRecovered
}

public struct AlertDecisionEngine: Sendable {
    public var rules: NotificationRuleSet
    private var lastSentAt: [AlertType: Date] = [:]
    private var lastDiagnosisSignature: String?

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

    public mutating func evaluateDiagnosis(
        _ diagnosis: NetworkPerspectiveDiagnosis,
        at date: Date = Date()
    ) -> AlertDecision? {
        guard rules.isEnabled else { return nil }

        let signature = diagnosis.alertSignature
        defer { lastDiagnosisSignature = signature }
        guard signature != lastDiagnosisSignature else { return nil }

        if diagnosis.verdict == .allReachable {
            guard lastDiagnosisSignature != nil,
                  rules.notifyOnRecovery,
                  rules.alertTypes.contains(.recovered),
                  shouldSend(.recovered, at: date)
            else { return nil }
            lastSentAt[.recovered] = date
            return .pathRecovered
        }

        let candidate = alertCandidate(for: diagnosis)
        guard let candidate else { return nil }
        guard rules.alertTypes.contains(candidate.type) else { return nil }
        guard shouldSend(candidate.type, at: date) else { return nil }
        lastSentAt[candidate.type] = date
        return candidate.decision
    }

    private func shouldSend(_ type: AlertType, at date: Date) -> Bool {
        guard let lastSent = lastSentAt[type] else { return true }
        return date.timeIntervalSince(lastSent) >= rules.cooldown.seconds
    }

    private func alertCandidate(for diagnosis: NetworkPerspectiveDiagnosis) -> (type: AlertType, decision: AlertDecision)? {
        if diagnosis.confidence != .high {
            switch diagnosis.verdict {
            case .localNetworkDown, .ispPathDown, .upstreamDown, .remoteServiceDown, .multipleFailures:
                return (.internetLoss, .internetLoss)
            case let .partialDegradation(tier):
                return (.pathDegraded, .pathDegraded(tier: tier))
            case .noData, .allReachable:
                return nil
            }
        }

        switch diagnosis.verdict {
        case .localNetworkDown:
            return (.localNetworkDown, .localNetworkDown)
        case .ispPathDown:
            return (.ispPathDown, .ispPathDown)
        case .upstreamDown:
            return (.upstreamDown, .upstreamDown)
        case let .remoteServiceDown(hostIDs):
            return (.remoteServiceDown, .remoteServiceDown(hostIDs: hostIDs))
        case let .partialDegradation(tier):
            return (.pathDegraded, .pathDegraded(tier: tier))
        case let .multipleFailures(hostIDs):
            return (.hostDown, .remoteServiceDown(hostIDs: hostIDs))
        case .noData, .allReachable:
            return nil
        }
    }
}

private extension NetworkPerspectiveDiagnosis {
    var alertSignature: String {
        switch verdict {
        case .noData: "noData"
        case .allReachable: "allReachable"
        case .localNetworkDown: "localNetworkDown"
        case .ispPathDown: "ispPathDown"
        case .upstreamDown: "upstreamDown"
        case let .remoteServiceDown(hostIDs):
            "remoteServiceDown:\(hostIDs.map(\.uuidString).sorted().joined(separator: ","))"
        case let .partialDegradation(tier):
            "partialDegradation:\(tier.rawValue)"
        case let .multipleFailures(hostIDs):
            "multipleFailures:\(hostIDs.map(\.uuidString).sorted().joined(separator: ","))"
        }
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

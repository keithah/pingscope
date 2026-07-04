import Foundation

public enum NotificationAlertStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case quiet
    case balanced
    case verbose
    case custom

    public static let presetCases: [NotificationAlertStyle] = [.quiet, .balanced, .verbose]

    public var displayName: String {
        switch self {
        case .quiet: "Quiet"
        case .balanced: "Balanced"
        case .verbose: "Verbose"
        case .custom: "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .quiet:
            "Only outage and recovery alerts."
        case .balanced:
            "Recommended alerts without noisy transient changes."
        case .verbose:
            "All alert categories with faster sensitivity."
        case .custom:
            "Manual alert and threshold settings."
        }
    }
}

public struct NotificationRuleSet: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var cooldown: Duration
    public var alertTypes: Set<AlertType>
    public var latencyThreshold: Duration
    public var highLatencyConsecutiveSamples: Int
    public var internetLossFailureRatio: Double
    public var diagnosisSensitivity: DiagnosisAlertSensitivity
    public var pathDegradedConsecutiveSamples: Int
    public var notifyOnRecovery: Bool

    public init(
        isEnabled: Bool = true,
        cooldown: Duration = .seconds(300),
        alertTypes: Set<AlertType> = [
            .hostDown,
            .recovered,
            .highLatency,
            .internetLoss,
            .localNetworkDown,
            .ispPathDown,
            .upstreamDown,
            .remoteServiceDown
        ],
        latencyThreshold: Duration = .milliseconds(250),
        highLatencyConsecutiveSamples: Int = 5,
        internetLossFailureRatio: Double = 1.0,
        diagnosisSensitivity: DiagnosisAlertSensitivity = .balanced,
        pathDegradedConsecutiveSamples: Int = 3,
        notifyOnRecovery: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.cooldown = cooldown
        self.alertTypes = alertTypes
        self.latencyThreshold = latencyThreshold
        self.highLatencyConsecutiveSamples = max(1, highLatencyConsecutiveSamples)
        self.internetLossFailureRatio = Self.clampedRatio(internetLossFailureRatio)
        self.diagnosisSensitivity = diagnosisSensitivity
        self.pathDegradedConsecutiveSamples = max(1, pathDegradedConsecutiveSamples)
        self.notifyOnRecovery = notifyOnRecovery
    }

    public init(style: NotificationAlertStyle) {
        self = Self.rules(for: style)
    }

    public var alertStyle: NotificationAlertStyle {
        for style in [NotificationAlertStyle.quiet, .balanced, .verbose] {
            if matchesPreset(style) {
                return style
            }
        }
        return .custom
    }

    public mutating func apply(style: NotificationAlertStyle) {
        guard style != .custom else { return }
        let wasEnabled = isEnabled
        self = Self.rules(for: style)
        isEnabled = wasEnabled
    }

    public static func rules(for style: NotificationAlertStyle) -> NotificationRuleSet {
        switch style {
        case .quiet:
            NotificationRuleSet(
                alertTypes: [
                    .hostDown,
                    .recovered,
                    .internetLoss,
                    .localNetworkDown,
                    .ispPathDown,
                    .upstreamDown,
                    .remoteServiceDown
                ],
                latencyThreshold: .milliseconds(250),
                highLatencyConsecutiveSamples: 10,
                internetLossFailureRatio: 1.0,
                diagnosisSensitivity: .conservative,
                pathDegradedConsecutiveSamples: 5,
                notifyOnRecovery: true
            )
        case .balanced, .custom:
            NotificationRuleSet()
        case .verbose:
            NotificationRuleSet(
                alertTypes: Set(AlertType.allCases),
                latencyThreshold: .milliseconds(250),
                highLatencyConsecutiveSamples: 3,
                internetLossFailureRatio: 0.75,
                diagnosisSensitivity: .sensitive,
                pathDegradedConsecutiveSamples: 2,
                notifyOnRecovery: true
            )
        }
    }

    private func matchesPreset(_ style: NotificationAlertStyle) -> Bool {
        let preset = Self.rules(for: style)
        return cooldown == preset.cooldown
            && alertTypes == preset.alertTypes
            && latencyThreshold == preset.latencyThreshold
            && highLatencyConsecutiveSamples == preset.highLatencyConsecutiveSamples
            && internetLossFailureRatio == preset.internetLossFailureRatio
            && diagnosisSensitivity == preset.diagnosisSensitivity
            && pathDegradedConsecutiveSamples == preset.pathDegradedConsecutiveSamples
            && notifyOnRecovery == preset.notifyOnRecovery
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case cooldown
        case alertTypes
        case latencyThreshold
        case highLatencyConsecutiveSamples
        case internetLossFailureRatio
        case diagnosisSensitivity
        case pathDegradedConsecutiveSamples
        case notifyOnRecovery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.cooldown = try container.decodeIfPresent(Duration.self, forKey: .cooldown) ?? .seconds(300)
        self.alertTypes = try container.decodeIfPresent(Set<AlertType>.self, forKey: .alertTypes) ?? NotificationRuleSet().alertTypes
        self.latencyThreshold = try container.decodeIfPresent(Duration.self, forKey: .latencyThreshold) ?? .milliseconds(250)
        self.highLatencyConsecutiveSamples = max(1, try container.decodeIfPresent(Int.self, forKey: .highLatencyConsecutiveSamples) ?? 5)
        self.internetLossFailureRatio = Self.clampedRatio(try container.decodeIfPresent(Double.self, forKey: .internetLossFailureRatio) ?? 1.0)
        self.diagnosisSensitivity = try container.decodeIfPresent(DiagnosisAlertSensitivity.self, forKey: .diagnosisSensitivity) ?? .balanced
        self.pathDegradedConsecutiveSamples = max(1, try container.decodeIfPresent(Int.self, forKey: .pathDegradedConsecutiveSamples) ?? 3)
        self.notifyOnRecovery = try container.decodeIfPresent(Bool.self, forKey: .notifyOnRecovery) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(cooldown, forKey: .cooldown)
        try container.encode(alertTypes, forKey: .alertTypes)
        try container.encode(latencyThreshold, forKey: .latencyThreshold)
        try container.encode(highLatencyConsecutiveSamples, forKey: .highLatencyConsecutiveSamples)
        try container.encode(internetLossFailureRatio, forKey: .internetLossFailureRatio)
        try container.encode(diagnosisSensitivity, forKey: .diagnosisSensitivity)
        try container.encode(pathDegradedConsecutiveSamples, forKey: .pathDegradedConsecutiveSamples)
        try container.encode(notifyOnRecovery, forKey: .notifyOnRecovery)
    }

    private static func clampedRatio(_ ratio: Double) -> Double {
        min(max(ratio, 0.1), 1.0)
    }
}

public enum AlertType: String, CaseIterable, Codable, Hashable, Sendable {
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
    /// A diagnosis alert the engine is willing to emit but has not yet committed.
    ///
    /// ``diagnosisAlertCandidate(_:at:)`` performs all streak bookkeeping and
    /// gating but leaves the cooldown and last-alerted signature untouched; the
    /// caller commits via ``commit(_:)`` only once it has decided to actually
    /// deliver the alert. Otherwise a suppressed candidate would consume the
    /// cooldown budget of a later, real one.
    public struct DiagnosisAlertCandidate: Equatable, Sendable {
        public let decision: AlertDecision
        fileprivate let type: AlertType
        fileprivate let signature: String
        fileprivate let date: Date
    }

    /// Host-scoped alert types (down / recovered / high latency) cool down per
    /// host; everything else is a single network-wide event. Without the host
    /// dimension, host A's edge-triggered `hostDown` would consume the cooldown
    /// and permanently swallow host B's transition inside the same window.
    private struct CooldownKey: Hashable, Sendable {
        let type: AlertType
        let hostID: UUID?
    }

    public var rules: NotificationRuleSet
    private var lastSentAt: [CooldownKey: Date] = [:]
    private var lastDiagnosisSignature: String?
    private var lastAlertedDiagnosisSignature: String?
    private var diagnosisStreakSignature: String?
    private var diagnosisStreakCount = 0
    private var consecutiveHighLatencyCounts: [UUID: Int] = [:]

    public init(rules: NotificationRuleSet = NotificationRuleSet()) {
        self.rules = rules
    }

    /// A per-host transition alert that passed every gate except delivery.
    /// Produced by ``transitionAlertCandidate(result:previousStatus:currentStatus:)``,
    /// which performs the streak bookkeeping without touching cooldown state;
    /// ``commit(_:)-swift.method`` records the cooldown once the caller decides
    /// the alert will actually be delivered.
    public struct TransitionAlertCandidate: Equatable, Sendable {
        public let decision: AlertDecision
        public let type: AlertType
        public let hostID: UUID
        public let date: Date
    }

    /// Evaluates and immediately commits. Use
    /// ``transitionAlertCandidate(result:previousStatus:currentStatus:)`` +
    /// ``commit(_:)-swift.method`` instead when the caller may still suppress
    /// the alert.
    public mutating func evaluate(
        result: PingResult,
        previousStatus: HealthStatus,
        currentStatus: HealthStatus
    ) -> AlertDecision? {
        guard let candidate = transitionAlertCandidate(
            result: result,
            previousStatus: previousStatus,
            currentStatus: currentStatus
        ) else { return nil }
        commit(candidate)
        return candidate.decision
    }

    /// Runs the edge-detection and high-latency streak bookkeeping for this
    /// result and returns the alert the engine would emit, without committing
    /// cooldown state.
    public mutating func transitionAlertCandidate(
        result: PingResult,
        previousStatus: HealthStatus,
        currentStatus: HealthStatus
    ) -> TransitionAlertCandidate? {
        guard rules.isEnabled else { return nil }

        let candidate: (AlertType, AlertDecision)?
        let isHighLatency = result.latency.map { $0 >= rules.latencyThreshold } ?? false
        if isHighLatency {
            consecutiveHighLatencyCounts[result.hostID, default: 0] += 1
        } else {
            consecutiveHighLatencyCounts[result.hostID] = nil
        }

        if currentStatus == .down, previousStatus != .down {
            candidate = (.hostDown, .hostDown(hostID: result.hostID))
        } else if previousStatus == .down, currentStatus != .down, rules.notifyOnRecovery {
            candidate = (.recovered, .recovered(hostID: result.hostID))
        } else if isHighLatency, consecutiveHighLatencyCounts[result.hostID, default: 0] >= rules.highLatencyConsecutiveSamples {
            candidate = (.highLatency, .highLatency(hostID: result.hostID))
        } else {
            candidate = nil
        }

        guard let (type, decision) = candidate, rules.alertTypes.contains(type) else {
            return nil
        }
        guard shouldSend(type, hostID: result.hostID, at: result.timestamp) else {
            return nil
        }
        return TransitionAlertCandidate(
            decision: decision,
            type: type,
            hostID: result.hostID,
            date: result.timestamp
        )
    }

    /// Records that `candidate` was actually delivered, starting its per-host
    /// cooldown. An undelivered candidate must never be committed: burning the
    /// cooldown for a suppressed alert silently swallows the next real one
    /// inside the window.
    public mutating func commit(_ candidate: TransitionAlertCandidate) {
        lastSentAt[CooldownKey(type: candidate.type, hostID: candidate.hostID)] = candidate.date
    }

    public mutating func evaluateNetworkChange(
        previousGateway: String?,
        currentGateway: String?,
        at date: Date = Date()
    ) -> AlertDecision? {
        guard rules.isEnabled,
              rules.alertTypes.contains(.networkChange),
              let previousGateway,
              let currentGateway,
              previousGateway != currentGateway
        else {
            return nil
        }
        guard shouldSend(.networkChange, at: date) else { return nil }
        lastSentAt[CooldownKey(type: .networkChange, hostID: nil)] = date
        return .networkChange(previousGateway: previousGateway, currentGateway: currentGateway)
    }

    public mutating func evaluateInternetLoss(
        results: [PingResult],
        at date: Date = Date()
    ) -> AlertDecision? {
        guard rules.isEnabled,
              rules.alertTypes.contains(.internetLoss),
              !results.isEmpty
        else {
            return nil
        }
        let failedCount = results.reduce(0) { count, result in
            count + (result.isSuccess ? 0 : 1)
        }
        let failureRatio = Double(failedCount) / Double(results.count)
        guard failureRatio >= rules.internetLossFailureRatio else { return nil }
        guard shouldSend(.internetLoss, at: date) else { return nil }
        lastSentAt[CooldownKey(type: .internetLoss, hostID: nil)] = date
        return .internetLoss
    }

    /// Evaluates and immediately commits. Use ``diagnosisAlertCandidate(_:at:)`` +
    /// ``commit(_:)`` instead when the caller may still suppress the alert.
    public mutating func evaluateDiagnosis(
        _ diagnosis: NetworkPerspectiveDiagnosis,
        at date: Date = Date()
    ) -> AlertDecision? {
        guard let candidate = diagnosisAlertCandidate(diagnosis, at: date) else { return nil }
        commit(candidate)
        return candidate.decision
    }

    /// Runs the streak/signature bookkeeping for this diagnosis and returns the
    /// alert the engine would emit, without committing cooldown state.
    public mutating func diagnosisAlertCandidate(
        _ diagnosis: NetworkPerspectiveDiagnosis,
        at date: Date = Date()
    ) -> DiagnosisAlertCandidate? {
        guard rules.isEnabled else { return nil }

        let signature = diagnosis.alertSignature
        lastDiagnosisSignature = signature

        if diagnosis.verdict == .allReachable {
            diagnosisStreakSignature = nil
            diagnosisStreakCount = 0
            lastAlertedDiagnosisSignature = nil
            return nil
        }

        if diagnosisStreakSignature == signature {
            diagnosisStreakCount += 1
        } else {
            diagnosisStreakSignature = signature
            diagnosisStreakCount = 1
        }

        let candidate = alertCandidate(for: diagnosis)
        guard let candidate else { return nil }
        guard rules.alertTypes.contains(candidate.type) else { return nil }
        if candidate.type == .pathDegraded {
            guard diagnosisStreakCount >= rules.pathDegradedConsecutiveSamples else { return nil }
        }
        guard signature != lastAlertedDiagnosisSignature else { return nil }
        guard shouldSend(candidate.type, at: date) else { return nil }
        return DiagnosisAlertCandidate(
            decision: candidate.decision,
            type: candidate.type,
            signature: signature,
            date: date
        )
    }

    /// Records that `candidate` was actually delivered, starting its cooldown and
    /// deduplicating the diagnosis signature.
    public mutating func commit(_ candidate: DiagnosisAlertCandidate) {
        lastSentAt[CooldownKey(type: candidate.type, hostID: nil)] = candidate.date
        lastAlertedDiagnosisSignature = candidate.signature
    }

    private func shouldSend(_ type: AlertType, hostID: UUID? = nil, at date: Date) -> Bool {
        guard let lastSent = lastSentAt[CooldownKey(type: type, hostID: hostID)] else { return true }
        return date.timeIntervalSince(lastSent) >= rules.cooldown.seconds
    }

    private func alertCandidate(for diagnosis: NetworkPerspectiveDiagnosis) -> (type: AlertType, decision: AlertDecision)? {
        if diagnosis.confidence != .high {
            if rules.diagnosisSensitivity == .conservative {
                return nil
            }
            if rules.diagnosisSensitivity == .sensitive {
                return specificAlertCandidate(for: diagnosis)
            }
            switch diagnosis.verdict {
            case .localNetworkDown, .ispPathDown, .upstreamDown, .remoteServiceDown, .multipleFailures:
                return (.internetLoss, .internetLoss)
            case let .partialDegradation(tier):
                return (.pathDegraded, .pathDegraded(tier: tier))
            case .noData, .allReachable:
                return nil
            }
        }

        return specificAlertCandidate(for: diagnosis)
    }

    private func specificAlertCandidate(for diagnosis: NetworkPerspectiveDiagnosis) -> (type: AlertType, decision: AlertDecision)? {
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

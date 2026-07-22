import Foundation
import PingScopeCore
import os

public enum PingScopeIOSNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unknown

    var permitsScheduling: Bool {
        self == .authorized || self == .provisional
    }
}

private let notificationLogger = Logger(
    subsystem: "com.hadm.PingScope",
    category: "NotificationDelivery"
)

public struct PingScopeIOSNotificationRequest: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    public init(decision: AlertDecision, hosts: [HostConfig]) {
        let hostNameByID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0.displayName) })
        func hostName(_ id: UUID) -> String {
            hostNameByID[id] ?? "Host"
        }

        switch decision {
        case let .hostDown(hostID):
            title = "\(hostName(hostID)) is down"
            body = "PingScope has reached the configured failure threshold."
        case let .recovered(hostID):
            title = "\(hostName(hostID)) recovered"
            body = "Latency measurements are receiving responses again."
        case let .highLatency(hostID):
            title = "High latency on \(hostName(hostID))"
            body = "Latency crossed the configured notification threshold."
        case let .networkChange(previousGateway, currentGateway):
            title = "Network changed"
            body = "Gateway changed from \(previousGateway ?? "none") to \(currentGateway ?? "none")."
        case .internetLoss:
            title = "Internet connection lost"
            body = "All enabled hosts are currently failing."
        case let .networkStatus(status):
            title = status.displayName
            body = "PingScope detected a network status change."
        case .localNetworkDown:
            title = "Local network down"
            body = "PingScope thinks the router or local gateway is the failing boundary."
        case .ispPathDown:
            title = "ISP path down"
            body = "The local gateway responds, but the ISP or modem path does not."
        case .upstreamDown:
            title = "Internet path down"
            body = "Local connectivity is available, but upstream internet checks are failing."
        case let .remoteServiceDown(hostIDs):
            let names = hostIDs.prefix(3).map(hostName).joined(separator: ", ")
            let extra = hostIDs.count > 3 ? ", +\(hostIDs.count - 3) more" : ""
            title = hostIDs.count == 1 ? "\(names) is unreachable" : "Remote services unreachable"
            body = "\(names)\(extra) failed while inner network checks were reachable."
        case let .pathDegraded(tier):
            title = "\(tier.settingsName) degraded"
            body = "PingScope detected slow or unreliable responses on this part of the path."
        case .pathRecovered:
            title = "Network path recovered"
            body = "PingScope measurements are reachable again."
        }
    }
}

public protocol PingScopeIOSNotificationScheduling: Sendable {
    func authorizationStatus() async -> PingScopeIOSNotificationAuthorization
    func requestAuthorization() async -> Bool
    func schedule(_ request: PingScopeIOSNotificationRequest) async throws
}

public enum PingScopeIOSNotificationRuleSource {
    public static func persistedRules(in defaults: UserDefaults = .standard) -> NotificationRuleSet {
        defaults.notificationRules ?? NotificationRuleSet()
    }
}

/// Converts the same result/status transitions used by the live monitor UI into
/// Core alert decisions, then schedules only decisions allowed by iOS consent.
public actor PingScopeIOSNotificationEngine {
    private let center: any PingScopeIOSNotificationScheduling
    private var decisionEngine: AlertDecisionEngine
    private var hosts: [HostConfig]
    private var hostByID: [UUID: HostConfig]
    private var includesAllHosts: Bool
    private var latestResultByHostID: [UUID: PingResult] = [:]
    private var cachedAuthorization: PingScopeIOSNotificationAuthorization?

    public init(
        center: any PingScopeIOSNotificationScheduling,
        rules: NotificationRuleSet = NotificationRuleSet(),
        hosts: [HostConfig] = [],
        includesAllHosts: Bool = false
    ) {
        let sanitizedHosts = HostConfig.sanitizedHosts(hosts)
        self.center = center
        self.decisionEngine = AlertDecisionEngine(rules: rules)
        self.hosts = sanitizedHosts
        self.hostByID = Dictionary(uniqueKeysWithValues: sanitizedHosts.map { ($0.id, $0) })
        self.includesAllHosts = includesAllHosts
    }

    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        switch await refreshAuthorization() {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            _ = await center.requestAuthorization()
            return await refreshAuthorization().permitsScheduling
        case .denied, .unknown:
            return false
        }
    }

    @discardableResult
    public func refreshAuthorization() async -> PingScopeIOSNotificationAuthorization {
        let authorization = await center.authorizationStatus()
        cachedAuthorization = authorization
        return authorization
    }

    public func update(hosts: [HostConfig], includesAllHosts: Bool) {
        let sanitizedHosts = HostConfig.sanitizedHosts(hosts)
        let activeHostIDs = Set(sanitizedHosts.map(\.id))
        self.hosts = sanitizedHosts
        self.hostByID = Dictionary(uniqueKeysWithValues: sanitizedHosts.map { ($0.id, $0) })
        self.includesAllHosts = includesAllHosts
        // Each controller resets its live health at session/scope reconfiguration;
        // stale results must not make the first new failure look like an
        // all-host internet outage.
        latestResultByHostID.removeAll(keepingCapacity: true)
        decisionEngine.prune(activeHostIDs: activeHostIDs)
    }

    public func update(rules: NotificationRuleSet) {
        decisionEngine.rules = rules
    }

    public func ingest(
        _ result: PingResult,
        previousStatus: HealthStatus,
        currentStatus: HealthStatus
    ) async {
        guard await permitsScheduling() else { return }
        guard let host = hostByID[result.hostID], host.notifications != .muted else { return }

        latestResultByHostID[result.hostID] = result
        let transitionCandidate = decisionEngine.transitionAlertCandidate(
            result: result,
            previousStatus: previousStatus,
            currentStatus: currentStatus
        )

        if let internetLoss = internetLossDecision(at: result.timestamp) {
            await schedule(internetLoss)
            return
        }

        if let transitionCandidate {
            decisionEngine.commit(transitionCandidate)
            await schedule(transitionCandidate.decision)
        }
    }

    public func evaluateNetworkChange(
        previousGateway: String?,
        currentGateway: String?,
        at date: Date = Date()
    ) async {
        guard await permitsScheduling() else { return }
        guard let decision = decisionEngine.evaluateNetworkChange(
            previousGateway: previousGateway,
            currentGateway: currentGateway,
            at: date
        ) else { return }
        await schedule(decision)
    }

    private func internetLossDecision(at date: Date) -> AlertDecision? {
        guard includesAllHosts else { return nil }
        let alertableHosts = hosts.filter { $0.isEnabled && $0.notifications != .muted }
        guard !alertableHosts.isEmpty else { return nil }
        let latestResults = alertableHosts.compactMap { latestResultByHostID[$0.id] }
        guard latestResults.count == alertableHosts.count else { return nil }
        return decisionEngine.evaluateInternetLoss(results: latestResults, at: date)
    }

    private func permitsScheduling() async -> Bool {
        if let cachedAuthorization {
            return cachedAuthorization.permitsScheduling
        }
        return await refreshAuthorization().permitsScheduling
    }

    private func schedule(_ decision: AlertDecision) async {
        do {
            try await center.schedule(PingScopeIOSNotificationRequest(decision: decision, hosts: hosts))
        } catch {
            notificationLogger.error(
                "Notification delivery failed category=\(Self.category(for: decision), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private static func category(for decision: AlertDecision) -> String {
        switch decision {
        case .hostDown: "hostDown"
        case .recovered: "recovered"
        case .internetLoss: "internetLoss"
        case .localNetworkDown: "localNetworkDown"
        case .ispPathDown: "ispPathDown"
        case .upstreamDown: "upstreamDown"
        case .remoteServiceDown: "remoteServiceDown"
        case .pathDegraded: "pathDegraded"
        case .pathRecovered: "pathRecovered"
        case .highLatency: "highLatency"
        case .networkChange: "networkChange"
        case .networkStatus: "networkStatus"
        }
    }
}

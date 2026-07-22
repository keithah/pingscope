import Foundation
import PingScopeCore

public enum PingScopeIOSControlKind {
    public static let monitoring = "com.hadm.pingscope.monitoring-control"
    public static let status = "com.hadm.pingscope.status-control"
}

public struct PingScopeIOSIntentHostReference: Codable, Equatable, Sendable {
    public let id: UUID?
    public let name: String?

    public init(id: UUID? = nil, name: String? = nil) {
        self.id = id
        self.name = name
    }
}

public enum PingScopeIOSIntentHostResolution: Equatable, Sendable {
    case found(HostConfig)
    case notFound
}

public enum PingScopeIOSIntentHostResolver {
    public static func resolve(
        _ reference: PingScopeIOSIntentHostReference,
        in hosts: [HostConfig]
    ) -> PingScopeIOSIntentHostResolution {
        if let id = reference.id {
            return hosts.first(where: { $0.id == id }).map(PingScopeIOSIntentHostResolution.found) ?? .notFound
        }
        guard let normalizedName = reference.name.map(normalized), !normalizedName.isEmpty else {
            return .notFound
        }
        return hosts.first(where: { normalized($0.displayName) == normalizedName })
            .map(PingScopeIOSIntentHostResolution.found) ?? .notFound
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct PingScopeIOSIntentHostStatus: Equatable, Sendable {
    public let hostID: UUID
    public let name: String
    public let status: HealthStatus
    public let latencyMilliseconds: Double?

    public init(
        hostID: UUID,
        name: String,
        status: HealthStatus,
        latencyMilliseconds: Double?
    ) {
        self.hostID = hostID
        self.name = name
        self.status = status
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public enum PingScopeIOSStatusIntentMode: Equatable, Sendable {
    case empty
    case monitoringOff
    case focused
    case allHosts
}

public struct PingScopeIOSStatusIntentProjection: Equatable, Sendable {
    public let mode: PingScopeIOSStatusIntentMode
    public let title: String
    public let summary: String
    public let hosts: [PingScopeIOSIntentHostStatus]

    public var outputText: String {
        switch mode {
        case .empty:
            summary
        case .monitoringOff:
            "\(title) — \(summary)"
        case .focused:
            hosts.first.map(Self.hostOutput) ?? summary
        case .allHosts:
            "All Hosts — \(hosts.map(Self.hostOutput).joined(separator: "; "))"
        }
    }

    public init(snapshot: WidgetSnapshot?) {
        guard let snapshot, !snapshot.hosts.isEmpty else {
            mode = .empty
            title = "PingScope"
            summary = "No monitoring data"
            hosts = []
            return
        }

        let healthByHostID = Dictionary(uniqueKeysWithValues: snapshot.health.map { ($0.hostID, $0) })
        hosts = snapshot.hosts.map { host in
            let health = healthByHostID[host.id]
            return PingScopeIOSIntentHostStatus(
                hostID: host.id,
                name: host.displayName,
                status: health?.status ?? .noData,
                latencyMilliseconds: health?.latencyMilliseconds
            )
        }
        let primary = hosts.first(where: { $0.hostID == snapshot.primaryHostID }) ?? hosts[0]
        title = snapshot.monitoring?.scope == .allHosts ? "All Hosts" : primary.name

        guard snapshot.monitoring?.isActive == true else {
            mode = .monitoringOff
            summary = "Monitoring is off"
            return
        }

        switch snapshot.monitoring?.scope {
        case .allHosts:
            mode = .allHosts
            summary = "\(hosts.count) hosts · \(Self.statusLabel(Self.aggregateStatus(hosts.map(\.status))))"
        case .focused, .none:
            mode = .focused
            summary = Self.hostSummary(primary)
        }
    }

    private static func hostSummary(_ host: PingScopeIOSIntentHostStatus) -> String {
        let status = statusLabel(host.status)
        guard let latency = host.latencyMilliseconds, latency.isFinite else { return status }
        return "\(status) · \(Int(latency.rounded())) ms"
    }

    private static func hostOutput(_ host: PingScopeIOSIntentHostStatus) -> String {
        let status = statusLabel(host.status)
        guard let latency = host.latencyMilliseconds, latency.isFinite else {
            return "\(host.name): \(status)"
        }
        return "\(host.name): \(status), \(Int(latency.rounded())) ms"
    }

    private static func aggregateStatus(_ statuses: [HealthStatus]) -> HealthStatus {
        if statuses.contains(.down) { return .down }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.healthy) { return .healthy }
        return .noData
    }

    static func statusLabel(_ status: HealthStatus) -> String {
        switch status {
        case .noData: "No Data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

public enum PingScopeIOSIntentRequest: Codable, Equatable, Sendable {
    case start(hostID: UUID?)
    case stop
}

public final class PingScopeIOSIntentCommandStore: @unchecked Sendable {
    public static let defaultKey = "PingScope.iOS.pendingIntentCommand"

    private let defaults: UserDefaults
    private let key: String
    private let isAvailable: Bool
    private let lock = NSLock()

    public init(
        suiteName: String = WidgetSnapshotStore.defaultSuiteName,
        key: String = defaultKey
    ) {
        if let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
            self.isAvailable = true
        } else {
            self.defaults = .standard
            self.isAvailable = false
        }
        self.key = key
    }

    public init(defaults: UserDefaults, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
        self.isAvailable = true
    }

    @discardableResult
    public func enqueue(_ request: PingScopeIOSIntentRequest) -> Bool {
        guard isAvailable, let data = try? JSONEncoder().encode(request) else { return false }
        lock.withLock {
            defaults.set(data, forKey: key)
        }
        return true
    }

    public func takePending() -> PingScopeIOSIntentRequest? {
        guard isAvailable else { return nil }
        return lock.withLock {
            guard let data = defaults.data(forKey: key) else { return nil }
            defaults.removeObject(forKey: key)
            return try? JSONDecoder().decode(PingScopeIOSIntentRequest.self, from: data)
        }
    }
}

public struct PingScopeIOSIntentMonitoringState: Equatable, Sendable {
    public let scope: PingScopeIOSHostScope
    public let selectedHostID: UUID
    public let isMonitoring: Bool

    public init(scope: PingScopeIOSHostScope, selectedHostID: UUID, isMonitoring: Bool) {
        self.scope = scope
        self.selectedHostID = selectedHostID
        self.isMonitoring = isMonitoring
    }
}

public enum PingScopeIOSIntentAction: Equatable, Sendable {
    case startFocused(UUID)
    case startAllHosts
    case switchToFocused(UUID)
    case stop
    case none
}

public enum PingScopeIOSIntentActionDecision {
    public static func decide(
        request: PingScopeIOSIntentRequest,
        current: PingScopeIOSIntentMonitoringState
    ) -> PingScopeIOSIntentAction {
        switch request {
        case .stop:
            return current.isMonitoring ? .stop : .none
        case .start(let requestedHostID):
            guard let requestedHostID else {
                guard !current.isMonitoring else { return .none }
                return current.scope == .allHosts ? .startAllHosts : .startFocused(current.selectedHostID)
            }
            if current.isMonitoring {
                guard current.scope != .focused || current.selectedHostID != requestedHostID else { return .none }
                return .switchToFocused(requestedHostID)
            }
            return .startFocused(requestedHostID)
        }
    }
}

public struct PingScopeIOSControlStateProjection: Equatable, Sendable {
    public let isMonitoring: Bool
    public let statusText: String
    public let symbolName: String

    public init(isMonitoring: Bool, statusText: String, symbolName: String) {
        self.isMonitoring = isMonitoring
        self.statusText = statusText
        self.symbolName = symbolName
    }

    public init(snapshot: WidgetSnapshot?) {
        let status = PingScopeIOSStatusIntentProjection(snapshot: snapshot)
        isMonitoring = snapshot?.monitoring?.isActive == true
        symbolName = isMonitoring ? "wave.3.right.circle.fill" : "wave.3.right.circle"
        switch status.mode {
        case .empty:
            statusText = status.summary
        case .monitoringOff:
            statusText = "\(status.title) · Off"
        case .focused:
            statusText = "\(status.title) · \(status.summary)"
        case .allHosts:
            statusText = status.summary
        }
    }
}

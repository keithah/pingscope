import Foundation
@_exported import PingScopeLiveActivitySupport
import PingScopeCore

public extension PingScopeLiveActivityHealthStatus {
    init(_ value: HealthStatus) {
        switch value {
        case .noData: self = .noData
        case .healthy: self = .healthy
        case .degraded: self = .degraded
        case .down: self = .down
        }
    }

    var coreValue: HealthStatus {
        switch self {
        case .noData: .noData
        case .healthy: .healthy
        case .degraded: .degraded
        case .down: .down
        }
    }
}

public extension PingScopeLiveActivityMethod {
    init(_ value: PingMethod) {
        switch value {
        case .https: self = .https
        case .tcp: self = .tcp
        case .udp: self = .udp
        case .icmp: self = .icmp
        case .starlink: self = .starlink
        }
    }

    var coreValue: PingMethod {
        switch self {
        case .https: .https
        case .tcp: .tcp
        case .udp: .udp
        case .icmp: .icmp
        case .starlink: .starlink
        }
    }
}

public extension PingScopeLiveActivityDuration {
    init(_ value: MonitorSessionDuration) {
        switch value {
        case .continuous: self = .continuous
        case .thirtySeconds: self = .thirtySeconds
        case .oneMinute: self = .oneMinute
        }
    }

    var coreValue: MonitorSessionDuration {
        switch self {
        case .continuous: .continuous
        case .thirtySeconds: .thirtySeconds
        case .oneMinute: .oneMinute
        }
    }
}

public extension PingScopeLiveActivityAttributes {
    init(host: HostConfig, duration: MonitorSessionDuration) {
        let resolvedColor = ResolvedHostDisplayColor(hostID: host.id, displayColor: host.displayColor)
        self.init(
            hostID: host.id,
            hostName: host.displayName,
            address: host.address,
            method: PingScopeLiveActivityMethod(host.method),
            duration: PingScopeLiveActivityDuration(duration),
            identityColor: WidgetGraphDisplayColor(resolvedColor: resolvedColor)
        )
    }
}

public extension PingScopeLiveActivityAttributes.ContentState {
    @_disfavoredOverload
    init(
        latencyMilliseconds: Int?,
        status: HealthStatus,
        lastUpdatedAt: Date?,
        remainingSeconds: Int,
        isStale: Bool,
        failureMessage: String? = nil,
        mode: PingScopeLiveActivityMode = .focused,
        hostRows: [PingScopeLiveActivityHostRow] = [],
        showsDynamicIslandDetails: Bool = true
    ) {
        self.init(
            latencyMilliseconds: latencyMilliseconds,
            status: PingScopeLiveActivityHealthStatus(status),
            lastUpdatedAt: lastUpdatedAt,
            remainingSeconds: remainingSeconds,
            isStale: isStale,
            failureMessage: failureMessage,
            mode: mode,
            hostRows: hostRows,
            showsDynamicIslandDetails: showsDynamicIslandDetails
        )
    }

    init(session: MonitorSessionState, health: HostHealth?, at date: Date = Date()) {
        let latestResult = session.latestResult ?? health?.latestResult
        self.init(
            latencyMilliseconds: latestResult?.latency.map { Int($0.milliseconds.rounded()) },
            status: health?.status ?? .noData,
            lastUpdatedAt: latestResult?.timestamp,
            remainingSeconds: session.duration == .continuous
                ? 0
                : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
            isStale: session.phase(at: date) != .live,
            failureMessage: latestResult?.failureReason?.userMessage
        )
    }
}

public extension PingScopeLiveActivityHostRow {
    @_disfavoredOverload
    init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: HealthStatus,
        latestLatencyMilliseconds: Int?,
        samples: [Int],
        isStale: Bool,
        isDefaultGateway: Bool = false
    ) {
        self.init(
            hostID: hostID,
            displayName: displayName,
            endpointCaption: endpointCaption,
            status: PingScopeLiveActivityHealthStatus(status),
            latestLatencyMilliseconds: latestLatencyMilliseconds,
            samples: samples,
            isStale: isStale,
            isDefaultGateway: isDefaultGateway
        )
    }

    init(snapshot: PingScopeIOSHostRowSnapshot) {
        self.init(
            hostID: snapshot.hostID,
            displayName: snapshot.displayName,
            endpointCaption: snapshot.endpointCaption,
            status: PingScopeLiveActivityHealthStatus(snapshot.status),
            latestLatencyMilliseconds: snapshot.latestLatencyMilliseconds.map { Int($0.rounded()) },
            samples: PingScopeIOSLatencySampleReducer.reduce(snapshot.samples, limit: Self.sampleLimit)
                .compactMap { $0.latency.map { Int($0.milliseconds.rounded()) } },
            isStale: snapshot.isStale,
            isDefaultGateway: snapshot.isDefaultGateway,
            identityColor: WidgetGraphDisplayColor(
                resolvedColor: snapshot.resolvedColor
            )
        )
    }
}

private extension WidgetGraphDisplayColor {
    init(resolvedColor: ResolvedHostDisplayColor) {
        let light = resolvedColor.components(for: .light)
        let dark = resolvedColor.components(for: .dark)
        self.init(
            light: WidgetGraphRGB(red: light.red, green: light.green, blue: light.blue),
            dark: WidgetGraphRGB(red: dark.red, green: dark.green, blue: dark.blue)
        )
    }
}

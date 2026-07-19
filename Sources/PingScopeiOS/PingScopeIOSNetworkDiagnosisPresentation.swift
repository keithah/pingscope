import Foundation
import PingScopeCore
import PingScopeHistoryKit

public typealias PingScopeIOSDiagnosisTone = NetworkDiagnosisPresentation.Tone

public struct PingScopeIOSDiagnosisPresentation: Equatable, Sendable {
    public let label: String
    public let detail: String
    public let systemImage: String
    public let tone: PingScopeIOSDiagnosisTone
    public let accessibilityLabel: String
    public let showsCompactRow: Bool

    public init(diagnosis: NetworkPerspectiveDiagnosis) {
        let shared = NetworkDiagnosisPresentation(diagnosis: diagnosis)
        label = shared.label
        detail = shared.detail
        systemImage = shared.systemImage
        tone = shared.tone
        accessibilityLabel = shared.accessibilityLabel
        showsCompactRow = shared.showsCompactRow
    }
}

public struct PingScopeIOSStarlinkPresentation: Equatable, Sendable, Identifiable {
    public let hostID: UUID
    public let hostName: String
    public let state: String
    public let dropRate: String
    public let obstruction: String
    public let downlinkThroughput: String
    public let uplinkThroughput: String
    public let uptime: String
    public let alerts: String?

    public var id: UUID { hostID }

    public init?(host: HostConfig, telemetry: StarlinkTelemetry?) {
        guard let shared = StarlinkTelemetryPresentation(host: host, telemetry: telemetry) else { return nil }
        self.init(host: host, shared: shared)
    }

    public static func latest(host: HostConfig, samples: [PingResult]) -> Self? {
        guard let shared = StarlinkTelemetryPresentation.latest(host: host, samples: samples) else { return nil }
        return Self(host: host, shared: shared)
    }

    private init(host: HostConfig, shared: StarlinkTelemetryPresentation) {
        hostID = host.id
        hostName = host.displayName
        state = shared.state
        dropRate = shared.dropRate
        obstruction = shared.obstruction
        downlinkThroughput = shared.downlinkThroughput
        uplinkThroughput = shared.uplinkThroughput
        uptime = shared.uptime
        alerts = shared.alerts
    }
}

public struct PingScopeIOSMonitorInsightsPresentation: Equatable, Sendable {
    public typealias Diagnoser = (
        _ hosts: [HostConfig],
        _ healthByHost: [UUID: HostHealth],
        _ networkStatus: NetworkConnectivityStatus
    ) -> NetworkPerspectiveDiagnosis

    public let diagnosis: PingScopeIOSDiagnosisPresentation?
    public let starlink: [PingScopeIOSStarlinkPresentation]

    public var hasContent: Bool {
        diagnosis != nil || !starlink.isEmpty
    }

    public init(
        snapshots: [LiveMonitorSessionSnapshot],
        networkStatus: NetworkConnectivityStatus = .connected,
        diagnose: Diagnoser = { hosts, healthByHost, networkStatus in
            NetworkPerspectiveDiagnoser().diagnose(
                hosts: hosts,
                healthByHost: healthByHost,
                networkStatus: networkStatus
            )
        }
    ) {
        var hosts: [HostConfig] = []
        var healthByHost: [UUID: HostHealth] = [:]
        hosts.reserveCapacity(snapshots.count)
        healthByHost.reserveCapacity(snapshots.count)

        for snapshot in snapshots where healthByHost[snapshot.host.id] == nil {
            hosts.append(snapshot.host)
            healthByHost[snapshot.host.id] = snapshot.health
        }

        let coreDiagnosis = diagnose(hosts, healthByHost, networkStatus)
        let mappedDiagnosis = PingScopeIOSDiagnosisPresentation(diagnosis: coreDiagnosis)
        diagnosis = mappedDiagnosis.showsCompactRow ? mappedDiagnosis : nil
        starlink = snapshots.compactMap { snapshot in
            PingScopeIOSStarlinkPresentation.latest(
                host: snapshot.host,
                samples: snapshot.series.samples
            )
        }
    }
}

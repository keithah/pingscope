import Foundation
import PingScopeCore

public enum PingScopeIOSLatencySampleReducer {
    public static let defaultLimit = 12

    public static func reduce(_ results: [PingResult], limit: Int) -> [PingResult] {
        let usableResults = results.filter(\.isSuccess)
        guard limit > 0, !usableResults.isEmpty else { return [] }
        guard usableResults.count > limit else { return usableResults }
        guard limit > 1 else { return [usableResults[0]] }

        var reduced: [PingResult] = []
        reduced.reserveCapacity(limit)
        var lastIndex: Int?
        for slot in 0..<limit {
            let position = Double(slot) * Double(usableResults.count - 1) / Double(limit - 1)
            let index = Int(position.rounded())
            if lastIndex != index {
                reduced.append(usableResults[index])
                lastIndex = index
            }
        }
        return reduced
    }
}

public struct PingScopeIOSHostRowSnapshot: Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public let status: HealthStatus
    public let latestLatencyMilliseconds: Double?
    public let samples: [PingResult]
    public let isStale: Bool
    public let isDefaultGateway: Bool
    public let degradedThresholdMilliseconds: Double

    public var reducedSamples: [PingResult] { samples }

    public var latencyText: String {
        Self.latencyText(for: latestLatencyMilliseconds)
    }

    fileprivate static func latencyText(for latency: Double?) -> String {
        guard let latency, latency.isFinite else { return "--ms" }
        let rounded = max(latency, 0).rounded()
        guard rounded < Double(Int.max) else { return "--ms" }
        return "\(Int(rounded))ms"
    }

    public var formattedLatency: String { latencyText }

    fileprivate init(
        hostID: UUID,
        displayName: String,
        endpointCaption: String,
        status: HealthStatus,
        latestLatencyMilliseconds: Double?,
        samples: [PingResult],
        isStale: Bool,
        isDefaultGateway: Bool = false,
        degradedThresholdMilliseconds: Double = LatencyThresholds.defaults.degradedMilliseconds
    ) {
        self.hostID = hostID
        self.displayName = displayName
        self.endpointCaption = endpointCaption
        self.status = status
        self.latestLatencyMilliseconds = latestLatencyMilliseconds
        self.samples = samples
        self.isStale = isStale
        self.isDefaultGateway = isDefaultGateway
        self.degradedThresholdMilliseconds = degradedThresholdMilliseconds
    }

    public init(
        host: HostConfig,
        health: HostHealth?,
        samples: [PingResult] = [],
        isStale: Bool = false,
        sampleLimit: Int = PingScopeIOSLatencySampleReducer.defaultLimit
    ) {
        self.hostID = host.id
        self.displayName = host.displayName
        self.endpointCaption = "\(host.method.displayName) \(host.address)"
        self.status = health?.status ?? .noData
        self.latestLatencyMilliseconds = health?.latestResult?.latency?.milliseconds
        self.samples = PingScopeIOSLatencySampleReducer.reduce(samples, limit: sampleLimit)
        self.isStale = isStale
        self.isDefaultGateway = host.isDefaultGateway
        self.degradedThresholdMilliseconds = host.thresholds.degradedMilliseconds
    }

    fileprivate func cappedForActivity() -> Self {
        Self(
            hostID: hostID,
            displayName: displayName,
            endpointCaption: endpointCaption,
            status: status,
            latestLatencyMilliseconds: latestLatencyMilliseconds,
            samples: PingScopeIOSLatencySampleReducer.reduce(samples, limit: PingScopeIOSLatencySampleReducer.defaultLimit),
            isStale: isStale,
            isDefaultGateway: isDefaultGateway,
            degradedThresholdMilliseconds: degradedThresholdMilliseconds
        )
    }
}

public struct PingScopeIOSAllHostsRingCell: Identifiable, Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let latencyText: String
    public let ringProgress: Double
    public let status: HealthStatus
    public let colorIndex: Int
    public let ringIndex: Int

    public var id: UUID { hostID }

    public var identityColor: PingScopeIOSHostIdentityPalette.ColorToken {
        PingScopeIOSHostIdentityPalette.color(at: colorIndex)
    }
}

public enum PingScopeIOSHostIdentityPalette {
    public struct RGB: Equatable, Hashable, Sendable {
        public let red: UInt8
        public let green: UInt8
        public let blue: UInt8

        public init(red: UInt8, green: UInt8, blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public enum ColorToken: Int, CaseIterable, Equatable, Sendable {
        case cobalt
        case magenta
        case teal
        case violet
        case gold
        case orange
        case seaGreen
        case purple
        case azure
        case crimson
        case olive
        case bronze

        public var lightRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x25, green: 0x63, blue: 0xEB)
            case .magenta: RGB(red: 0xDB, green: 0x27, blue: 0x77)
            case .teal: RGB(red: 0x08, green: 0x91, blue: 0xB2)
            case .violet: RGB(red: 0x7C, green: 0x3A, blue: 0xED)
            case .gold: RGB(red: 0xCA, green: 0x8A, blue: 0x04)
            case .orange: RGB(red: 0xEA, green: 0x58, blue: 0x0C)
            case .seaGreen: RGB(red: 0x0F, green: 0x76, blue: 0x6E)
            case .purple: RGB(red: 0x93, green: 0x33, blue: 0xEA)
            case .azure: RGB(red: 0x03, green: 0x69, blue: 0xA1)
            case .crimson: RGB(red: 0xBE, green: 0x12, blue: 0x3C)
            case .olive: RGB(red: 0x4D, green: 0x7C, blue: 0x0F)
            case .bronze: RGB(red: 0xA1, green: 0x62, blue: 0x07)
            }
        }

        public var darkRGB: RGB {
            switch self {
            case .cobalt: RGB(red: 0x60, green: 0xA5, blue: 0xFA)
            case .magenta: RGB(red: 0xF4, green: 0x72, blue: 0xB6)
            case .teal: RGB(red: 0x22, green: 0xD3, blue: 0xEE)
            case .violet: RGB(red: 0xA7, green: 0x8B, blue: 0xFA)
            case .gold: RGB(red: 0xFA, green: 0xCC, blue: 0x15)
            case .orange: RGB(red: 0xFB, green: 0x92, blue: 0x3C)
            case .seaGreen: RGB(red: 0x2D, green: 0xD4, blue: 0xBF)
            case .purple: RGB(red: 0xC0, green: 0x84, blue: 0xFC)
            case .azure: RGB(red: 0x38, green: 0xBD, blue: 0xF8)
            case .crimson: RGB(red: 0xFB, green: 0x71, blue: 0x85)
            case .olive: RGB(red: 0xA3, green: 0xE6, blue: 0x35)
            case .bronze: RGB(red: 0xFB, green: 0xBF, blue: 0x24)
            }
        }
    }

    public static let count = ColorToken.allCases.count

    public static func color(at index: Int) -> ColorToken {
        let normalized = ((index % count) + count) % count
        return ColorToken.allCases[normalized]
    }

    public static func color(for hostID: UUID) -> ColorToken {
        color(at: PingScopeIOSAllHostsMonitorPresentation.stableColorIndex(
            for: hostID,
            paletteCount: count
        ))
    }
}

public enum PingScopeIOSAllHostsRingGridPresentation {
    public static let paletteCount = PingScopeIOSHostIdentityPalette.count

    public static func cells(from rows: [PingScopeIOSHostRowSnapshot]) -> [PingScopeIOSAllHostsRingCell] {
        rows.enumerated().map { ringIndex, row in
            let presentation = PingScopeIOSAllHostsMonitorPresentation.rowPresentation(for: row)
            let latency = row.isStale ? nil : row.latestLatencyMilliseconds
            let threshold = max(row.degradedThresholdMilliseconds, 1)
            return PingScopeIOSAllHostsRingCell(
                hostID: row.hostID,
                displayName: presentation.displayName,
                latencyText: presentation.latencyText,
                ringProgress: latency.map { min(max($0 / threshold, 0), 1) } ?? 0,
                status: presentation.displayStatus,
                colorIndex: PingScopeIOSAllHostsMonitorPresentation.stableColorIndex(
                    for: row.hostID,
                    paletteCount: paletteCount
                ),
                ringIndex: ringIndex
            )
        }
    }

    static func latencyText(for latency: Double?) -> String {
        PingScopeIOSHostRowSnapshot.latencyText(for: latency)
    }
}

public struct PingScopeIOSAllHostsConcentricRingPresentation: Equatable, Sendable {
    public static let maximumRingCount = 4
    public static let paletteCount = PingScopeIOSAllHostsRingGridPresentation.paletteCount

    public let rings: [PingScopeIOSAllHostsRingCell]
    public let legendRows: [PingScopeIOSAllHostsRingCell]
    public let overflowCount: Int
    public let firstOverflowHostID: UUID?

    public var overflowLabel: String {
        overflowCount > 0 ? "+\(overflowCount) more" : ""
    }

    public var overflowAccessibilityLabel: String {
        overflowCount > 0 ? "Show \(overflowCount) more hosts" : ""
    }

    public init(rows: [PingScopeIOSHostRowSnapshot]) {
        let visibleCells = Array(
            PingScopeIOSAllHostsRingGridPresentation.cells(from: rows)
                .prefix(Self.maximumRingCount)
        )
        rings = visibleCells
        legendRows = visibleCells
        overflowCount = max(rows.count - visibleCells.count, 0)
        firstOverflowHostID = rows.dropFirst(visibleCells.count).first?.hostID
    }
}

struct PingScopeIOSAllHostsRingRowsFingerprint: Hashable {
    struct Row: Hashable {
        let hostID: UUID
        let displayName: String
        let status: String
        let latencyBitPattern: UInt64?
        let isStale: Bool
        let degradedThresholdBitPattern: UInt64
    }

    let rows: [Row]

    init(_ rows: [PingScopeIOSHostRowSnapshot]) {
        self.rows = rows.map { row in
            Row(
                hostID: row.hostID,
                displayName: row.displayName,
                status: row.status.rawValue,
                latencyBitPattern: row.latestLatencyMilliseconds?.bitPattern,
                isStale: row.isStale,
                degradedThresholdBitPattern: row.degradedThresholdMilliseconds.bitPattern
            )
        }
    }
}

@MainActor
final class PingScopeIOSAllHostsConcentricRingContentMemo {
    private var cache = BoundedMemo<
        PingScopeIOSAllHostsRingRowsFingerprint,
        PingScopeIOSAllHostsConcentricRingPresentation
    >(capacity: 1)

    func resolve(
        _ rows: [PingScopeIOSHostRowSnapshot],
        build: ([PingScopeIOSHostRowSnapshot]) -> PingScopeIOSAllHostsConcentricRingPresentation = {
            PingScopeIOSAllHostsConcentricRingPresentation(rows: $0)
        }
    ) -> PingScopeIOSAllHostsConcentricRingPresentation {
        cache.resolve(PingScopeIOSAllHostsRingRowsFingerprint(rows)) {
            build(rows)
        }
    }
}

public enum PingScopeIOSHostScopePresentation {
    public static let activityHostLimit = 3

    public static func aggregateStatus(from rows: [PingScopeIOSHostRowSnapshot]) -> HealthStatus {
        let statuses = rows.map { $0.isStale ? HealthStatus.noData : $0.status }
        if statuses.contains(.down) { return .down }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.healthy) { return .healthy }
        return .noData
    }

    public static func enabledHosts(from hosts: [HostConfig]) -> [HostConfig] {
        hosts.filter(\.isEnabled)
    }

    public static func enabledHosts(from state: PingScopeIOSHostState) -> [HostConfig] {
        enabledHosts(from: state.hosts)
    }

    public static func rows(
        from hosts: [HostConfig],
        healthByHost: [UUID: HostHealth] = [:],
        samplesByHost: [UUID: [PingResult]] = [:],
        staleHostIDs: Set<UUID> = []
    ) -> [PingScopeIOSHostRowSnapshot] {
        enabledHosts(from: hosts).map { host in
            PingScopeIOSHostRowSnapshot(
                host: host,
                health: healthByHost[host.id],
                samples: samplesByHost[host.id] ?? [],
                isStale: staleHostIDs.contains(host.id)
            )
        }
    }

    public static func activityRows(from rows: [PingScopeIOSHostRowSnapshot]) -> [PingScopeIOSHostRowSnapshot] {
        rows.prefix(activityHostLimit).map { $0.cappedForActivity() }
    }

    public static func activityRows(
        from hosts: [HostConfig],
        healthByHost: [UUID: HostHealth] = [:],
        samplesByHost: [UUID: [PingResult]] = [:],
        staleHostIDs: Set<UUID> = []
    ) -> [PingScopeIOSHostRowSnapshot] {
        activityRows(from: rows(
            from: hosts,
            healthByHost: healthByHost,
            samplesByHost: samplesByHost,
            staleHostIDs: staleHostIDs
        ))
    }
}

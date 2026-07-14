import Foundation

public enum StatusColor: String, Codable, Equatable, Sendable {
    case gray
    case green
    case yellow
    case red
}

public struct MenuBarState: Equatable, Sendable {
    public var text: String
    public var color: StatusColor
    public var accessibilityLabel: String
}

public struct MenuBarGlyphContent: Equatable, Sendable {
    public var latencyText: String
    public var dotDiameter: Double
    public var itemWidth: Double
    public var fontSize: Double
    public var fontWeight: MenuBarFontWeight
    public var textBaselineY: Double
    public var color: StatusColor
    public var accessibilityLabel: String

    public init(
        latencyText: String,
        dotDiameter: Double,
        itemWidth: Double,
        fontSize: Double,
        fontWeight: MenuBarFontWeight,
        textBaselineY: Double,
        color: StatusColor,
        accessibilityLabel: String
    ) {
        self.latencyText = latencyText
        self.dotDiameter = dotDiameter
        self.itemWidth = itemWidth
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textBaselineY = textBaselineY
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct HostStatusSummary: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var endpoint: String
    public var statusText: String
    public var latencyText: String
    public var color: StatusColor
    public var accessibilityLabel: String

    public init(
        id: UUID,
        name: String,
        endpoint: String,
        statusText: String,
        latencyText: String,
        color: StatusColor,
        accessibilityLabel: String
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.statusText = statusText
        self.latencyText = latencyText
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct LatencyGraphScale: Equatable, Sendable {
    public var maximumMilliseconds: Double
    public var axisMaximumMilliseconds: Double
    public var tickMilliseconds: [Double]

    public init(latencies: [Double]) {
        self.init(maximumMilliseconds: latencies.max())
    }

    public init(maximumMilliseconds: Double?) {
        let maximum = max(maximumMilliseconds ?? 0, 1)
        let axisMaximum = Self.roundedAxisMaximum(for: maximum)
        self.maximumMilliseconds = maximum
        self.axisMaximumMilliseconds = axisMaximum
        self.tickMilliseconds = [axisMaximum, axisMaximum / 2, 0]
    }

    public func label(for milliseconds: Double) -> String {
        "\(Int(milliseconds.rounded()))ms"
    }

    private static func roundedAxisMaximum(for maximum: Double) -> Double {
        let step: Double
        switch maximum {
        case ...10:
            step = 1
        case ...100:
            step = 10
        case ...500:
            step = 25
        case ...1_000:
            step = 50
        default:
            step = 100
        }
        return max(1, ceil(maximum / step) * step)
    }
}

public enum MenuBarFontWeight: String, Codable, Equatable, Sendable {
    case regular
    case medium
}

public enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case tenMinutes = "10m"
    case oneHour = "1h"

    public var id: String { rawValue }

    public static var displayCases: [TimeRange] {
        [.oneMinute, .fiveMinutes, .tenMinutes, .oneHour]
    }

    public var duration: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .oneHour: 3_600
        }
    }
}

public enum HistoryExportRangeUnit: String, CaseIterable, Identifiable, Sendable {
    case hours = "h"
    case days = "d"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hours: "hours"
        case .days: "days"
        }
    }

    fileprivate var secondsMultiplier: TimeInterval {
        switch self {
        case .hours: 3_600
        case .days: 86_400
        }
    }
}

/// The longest History window retained and exposed by first-party PingScope apps.
/// Derive both store retention and export cutoffs from this policy to keep them aligned.
public enum PingHistoryRetention {
    public static let maximumDays: Double = 30
    public static let maximumDuration: Duration = .days(maximumDays)
    public static let maximumTimeInterval: TimeInterval = maximumDuration.seconds
}

public enum HistoryExportRangePreset: String, CaseIterable, Identifiable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case tenMinutes = "10m"
    case oneHour = "1h"
    case max = "Max"
    case custom = "Custom"

    public static let maximumDuration = PingHistoryRetention.maximumTimeInterval
    public static let `default`: Self = .oneHour

    public var id: String { rawValue }

    public func resolvedDuration(customValue: String, customUnit: HistoryExportRangeUnit) -> TimeInterval? {
        switch self {
        case .oneMinute:
            return TimeRange.oneMinute.duration
        case .fiveMinutes:
            return TimeRange.fiveMinutes.duration
        case .tenMinutes:
            return TimeRange.tenMinutes.duration
        case .oneHour:
            return TimeRange.oneHour.duration
        case .max:
            return Self.maximumDuration
        case .custom:
            let trimmed = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite, value > 0 else {
                return nil
            }
            return min(value * customUnit.secondsMultiplier, Self.maximumDuration)
        }
    }

    public func filenameComponent(customValue: String, customUnit: HistoryExportRangeUnit) -> String {
        switch self {
        case .oneMinute, .fiveMinutes, .tenMinutes, .oneHour:
            return rawValue
        case .max:
            return "max"
        case .custom:
            let trimmed = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "custom" }
            let safeValue = trimmed
                .replacingOccurrences(of: ".", with: "p")
                .filter { $0.isNumber || $0 == "p" }
            return safeValue.isEmpty ? "custom" : "\(safeValue)\(customUnit.rawValue)"
        }
    }
}

public struct DisplayStatePresenter: Sendable {
    public init() {}

    public func menuBarState(for host: HostConfig?, health: HostHealth?) -> MenuBarState {
        guard let host else {
            return MenuBarState(text: "--ms", color: .gray, accessibilityLabel: "PingScope has no host configured")
        }

        let color = color(for: health?.status ?? .noData)
        let latencyText: String
        if let milliseconds = health?.latestResult?.latency?.milliseconds {
            latencyText = "\(Int(milliseconds.rounded()))ms"
        } else {
            latencyText = "--ms"
        }

        return MenuBarState(
            text: latencyText,
            color: color,
            accessibilityLabel: "\(host.displayName) latency \(latencyText), \(health?.status.rawValue ?? "no data")"
        )
    }

    public func rangeStatusState(for host: HostConfig?, health: HostHealth?, range: TimeRange, now: Date = Date()) -> MenuBarState {
        guard let host else {
            return MenuBarState(text: "--ms", color: .gray, accessibilityLabel: "PingScope has no host configured")
        }

        guard let latestResult = health?.latestResult,
              latestResult.timestamp >= now.addingTimeInterval(-range.duration) else {
            return MenuBarState(
                text: "--ms",
                color: .gray,
                accessibilityLabel: "\(host.displayName) has no samples in the selected range"
            )
        }

        return menuBarState(for: host, health: health)
    }

    public func rangeStatusLabel(for health: HostHealth?, range: TimeRange, now: Date = Date()) -> String {
        guard let latestResult = health?.latestResult,
              latestResult.timestamp >= now.addingTimeInterval(-range.duration) else {
            return "No Recent Data"
        }
        return health?.status.rawValue.capitalized ?? "No Data"
    }

    public func menuBarGlyphContent(for host: HostConfig?, health: HostHealth?) -> MenuBarGlyphContent {
        let state = menuBarState(for: host, health: health)
        return MenuBarGlyphContent(
            latencyText: state.text,
            dotDiameter: 8,
            itemWidth: 34,
            fontSize: 9.5,
            fontWeight: .regular,
            textBaselineY: 0,
            color: state.color,
            accessibilityLabel: state.accessibilityLabel
        )
    }

    public func hostStatusSummaries(in snapshot: RuntimeSnapshot) -> [HostStatusSummary] {
        snapshot.hosts.map { host in
            let health = snapshot.healthByHost[host.id]
            let observedHealth = health?.latestResult == nil ? nil : health
            let status = observedHealth?.status ?? .noData
            let latencyText: String
            if let milliseconds = observedHealth?.latestResult?.latency?.milliseconds {
                latencyText = "\(Int(milliseconds.rounded()))ms"
            } else {
                latencyText = "--"
            }
            let endpoint = endpointText(for: host)
            let statusText = statusDisplayName(status)
            return HostStatusSummary(
                id: host.id,
                name: host.displayName,
                endpoint: endpoint,
                statusText: statusText,
                latencyText: latencyText,
                color: color(for: status),
                accessibilityLabel: "\(host.displayName) \(endpoint) \(statusText) \(latencyText)"
            )
        }
    }

    public func visibleSamples(in series: SampleSeries?, range: TimeRange, now: Date = Date()) -> [PingResult] {
        guard let series else { return [] }
        return series.samples(since: now.addingTimeInterval(-range.duration))
    }

    public func mergedSamples(history: [PingResult], live: [PingResult], range: TimeRange, now: Date = Date()) -> [PingResult] {
        let cutoff = now.addingTimeInterval(-range.duration)
        let historySamples = Self.ascendingSamples(history, since: cutoff)
        let liveSamples = Self.ascendingSamples(live, since: cutoff)
        var merged: [PingResult] = []
        merged.reserveCapacity(historySamples.count + liveSamples.count)
        var seen = Set<UUID>()
        var historyIndex = 0
        var liveIndex = 0

        while historyIndex < historySamples.count || liveIndex < liveSamples.count {
            let next: PingResult
            if historyIndex == historySamples.count {
                next = liveSamples[liveIndex]
                liveIndex += 1
            } else if liveIndex == liveSamples.count {
                next = historySamples[historyIndex]
                historyIndex += 1
            } else if Self.precedes(historySamples[historyIndex], liveSamples[liveIndex]) {
                next = historySamples[historyIndex]
                historyIndex += 1
            } else {
                next = liveSamples[liveIndex]
                liveIndex += 1
            }
            if seen.insert(next.id).inserted {
                merged.append(next)
            }
        }
        return merged
    }

    public func color(for status: HealthStatus) -> StatusColor {
        switch status {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }

    private static func ascendingSamples(_ samples: [PingResult], since cutoff: Date) -> [PingResult] {
        guard !samples.isEmpty else { return [] }
        let filtered = samples.filter { $0.timestamp >= cutoff }
        guard filtered.count > 1 else { return filtered }
        if isAscending(filtered) {
            return filtered
        }
        if isDescending(filtered) {
            return Array(filtered.reversed())
        }
        return filtered.sorted(by: precedes)
    }

    private static func isAscending(_ samples: [PingResult]) -> Bool {
        zip(samples, samples.dropFirst()).allSatisfy { precedes($0, $1) || $0.id == $1.id }
    }

    private static func isDescending(_ samples: [PingResult]) -> Bool {
        zip(samples, samples.dropFirst()).allSatisfy { precedes($1, $0) || $0.id == $1.id }
    }

    private static func precedes(_ lhs: PingResult, _ rhs: PingResult) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.timestamp < rhs.timestamp
    }

    private func endpointText(for host: HostConfig) -> String {
        if let port = host.port {
            return "\(host.method.displayName) \(host.address):\(port)"
        }
        return "\(host.method.displayName) \(host.address)"
    }

    private func statusDisplayName(_ status: HealthStatus) -> String {
        switch status {
        case .noData: "No Data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

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

public struct LatencyGraphScale: Equatable, Sendable {
    public var maximumMilliseconds: Double
    public var axisMaximumMilliseconds: Double
    public var tickMilliseconds: [Double]

    public init(latencies: [Double]) {
        let maximum = max(latencies.max() ?? 0, 1)
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

    public var duration: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .tenMinutes: 600
        case .oneHour: 3_600
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

    public func visibleSamples(in series: SampleSeries?, range: TimeRange, now: Date = Date()) -> [PingResult] {
        guard let series else { return [] }
        return series.samples(since: now.addingTimeInterval(-range.duration))
    }

    public func mergedSamples(history: [PingResult], live: [PingResult], range: TimeRange, now: Date = Date()) -> [PingResult] {
        let cutoff = now.addingTimeInterval(-range.duration)
        var byID: [UUID: PingResult] = [:]
        for sample in history where sample.timestamp >= cutoff {
            byID[sample.id] = sample
        }
        for sample in live where sample.timestamp >= cutoff {
            byID[sample.id] = sample
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    public func color(for status: HealthStatus) -> StatusColor {
        switch status {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }
}

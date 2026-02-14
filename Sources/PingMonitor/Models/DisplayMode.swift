import Foundation

enum DisplayMode: String, CaseIterable, Codable, Sendable {
    case full
    case compact

    var defaultFrame: DisplayFrameData {
        switch self {
        case .full:
            // Default should match the visual footprint in `images/mainscreen*`.
            return .init(x: 0, y: 0, width: 380, height: 440)
        case .compact:
            // User wants compact much smaller by default.
            return .init(x: 0, y: 0, width: 140, height: 110)
        }
    }
}

enum DisplayTimeRange: String, CaseIterable, Codable, Sendable {
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case oneHour
}

struct DisplaySharedState: Codable, Sendable, Equatable {
    var selectedHostID: UUID?
    var selectedTimeRange: DisplayTimeRange

    init(
        selectedHostID: UUID? = nil,
        selectedTimeRange: DisplayTimeRange = .fiveMinutes
    ) {
        self.selectedHostID = selectedHostID
        self.selectedTimeRange = selectedTimeRange
    }
}

struct DisplayFrameData: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct DisplayModeState: Codable, Sendable, Equatable {
    var graphVisible: Bool
    var historyVisible: Bool
    var frameData: DisplayFrameData

    init(
        graphVisible: Bool = true,
        historyVisible: Bool = true,
        frameData: DisplayFrameData
    ) {
        self.graphVisible = graphVisible
        self.historyVisible = historyVisible
        self.frameData = frameData
    }

    static func `default`(for mode: DisplayMode) -> DisplayModeState {
        DisplayModeState(frameData: mode.defaultFrame)
    }
}

struct DisplayPreferences: Codable, Sendable, Equatable {
    var shared: DisplaySharedState
    var full: DisplayModeState
    var compact: DisplayModeState

    init(
        shared: DisplaySharedState = DisplaySharedState(),
        full: DisplayModeState = .default(for: .full),
        compact: DisplayModeState = .default(for: .compact)
    ) {
        self.shared = shared
        self.full = full
        self.compact = compact
    }

    func modeState(for mode: DisplayMode) -> DisplayModeState {
        switch mode {
        case .full:
            return full
        case .compact:
            return compact
        }
    }

    mutating func setModeState(_ state: DisplayModeState, for mode: DisplayMode) {
        switch mode {
        case .full:
            full = state
        case .compact:
            compact = state
        }
    }
}

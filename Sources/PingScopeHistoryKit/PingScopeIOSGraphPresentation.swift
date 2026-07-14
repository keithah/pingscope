import Foundation
import PingScopeCore

public struct PingScopeIOSGraphPresentation: Sendable, Equatable {
    public let renderData: PingScopeIOSLatencyGraphData
    public let stats: SampleStats

    public init(samples: [PingResult], range: TimeRange, endDate: Date = Date()) {
        self.renderData = PingScopeIOSLatencyGraphData(samples: samples, range: range, endDate: endDate)
        self.stats = SampleStats(samples: samples)
    }
}

public struct PingScopeIOSLatencyGraphPoint: Sendable, Equatable {
    public let timestamp: Date
    public let latencyMilliseconds: Double

    public init(timestamp: Date, latencyMilliseconds: Double) {
        self.timestamp = timestamp
        self.latencyMilliseconds = latencyMilliseconds
    }
}

public struct PingScopeIOSLatencyGraphData: Sendable, Equatable {
    public let startDate: Date
    public let endDate: Date
    public let scale: LatencyGraphScale
    public let points: [PingScopeIOSLatencyGraphPoint]

    public init(samples: [PingResult], range: TimeRange, endDate: Date = Date()) {
        self.init(
            samples: samples,
            startDate: endDate.addingTimeInterval(-range.duration),
            endDate: endDate
        )
    }

    public init(samples: [PingResult], startDate: Date, endDate: Date) {
        self.endDate = endDate
        self.startDate = startDate
        var maximumLatency: Double?
        var points: [PingScopeIOSLatencyGraphPoint] = []
        for sample in samples where sample.timestamp >= startDate && sample.timestamp <= endDate {
            guard let latency = sample.latency?.milliseconds else { continue }
            maximumLatency = maximumLatency.map { max($0, latency) } ?? latency
            points.append(PingScopeIOSLatencyGraphPoint(timestamp: sample.timestamp, latencyMilliseconds: latency))
        }
        self.points = points
        self.scale = LatencyGraphScale(maximumMilliseconds: maximumLatency)
    }

    public init(historyPoints: [HistoryChartPoint], startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
        self.points = historyPoints.map {
            PingScopeIOSLatencyGraphPoint(
                timestamp: $0.timestamp,
                latencyMilliseconds: $0.latencyMilliseconds
            )
        }
        self.scale = LatencyGraphScale(maximumMilliseconds: historyPoints.map(\.latencyMilliseconds).max())
    }
}

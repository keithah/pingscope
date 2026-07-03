import Foundation
import PingScopeCore

#if os(iOS)
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
        self.endDate = endDate
        startDate = endDate.addingTimeInterval(-range.duration)
        var latencies: [Double] = []
        var points: [PingScopeIOSLatencyGraphPoint] = []
        for sample in samples where sample.timestamp >= startDate && sample.timestamp <= endDate {
            guard let latency = sample.latency?.milliseconds else { continue }
            latencies.append(latency)
            points.append(PingScopeIOSLatencyGraphPoint(timestamp: sample.timestamp, latencyMilliseconds: latency))
        }
        self.points = points
        self.scale = LatencyGraphScale(latencies: latencies)
    }
}
#endif

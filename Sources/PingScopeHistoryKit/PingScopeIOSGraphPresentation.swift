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

    /// Returns the closest point in a chronologically ordered rendered series.
    /// An equidistant target resolves to the earlier point.
    public static func nearest(
        to targetDate: Date,
        in chronologicalPoints: [Self]
    ) -> Self? {
        guard let first = chronologicalPoints.first else { return nil }
        guard targetDate >= first.timestamp else { return first }
        let last = chronologicalPoints[chronologicalPoints.count - 1]
        guard targetDate <= last.timestamp else {
            return chronologicalPoints[firstIndex(
                atOrAfter: last.timestamp,
                in: chronologicalPoints
            )]
        }

        let lowerBound = firstIndex(atOrAfter: targetDate, in: chronologicalPoints)

        let later = chronologicalPoints[lowerBound]
        if later.timestamp == targetDate { return later }
        let earlierTimestamp = chronologicalPoints[lowerBound - 1].timestamp
        let earlier = chronologicalPoints[firstIndex(
            atOrAfter: earlierTimestamp,
            in: chronologicalPoints
        )]
        let earlierDistance = targetDate.timeIntervalSince(earlier.timestamp)
        let laterDistance = later.timestamp.timeIntervalSince(targetDate)
        return earlierDistance <= laterDistance ? earlier : later
    }

    private static func firstIndex(
        atOrAfter targetDate: Date,
        in chronologicalPoints: [Self]
    ) -> Int {
        var lowerBound = 0
        var upperBound = chronologicalPoints.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if chronologicalPoints[midpoint].timestamp < targetDate {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }
        return lowerBound
    }
}

public struct PingScopeIOSLatencyGraphData: Sendable, Equatable {
    public static let maximumPointCount = 1_024

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
        self.points = points.downsampledForIOSGraph(maximumPointCount: Self.maximumPointCount)
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

// Intentionally separate from HistoryChartReduction: its endpoint-preserving 1,024-point output is not point-for-point equivalent.
private extension Array where Element == PingScopeIOSLatencyGraphPoint {
    func downsampledForIOSGraph(maximumPointCount: Int) -> [Element] {
        guard maximumPointCount >= 2, count > maximumPointCount else { return self }

        let interior = dropFirst().dropLast()
        let bucketCount = Swift.max(1, (maximumPointCount - 2) / 2)
        var buckets = Swift.Array(repeating: [Element](), count: bucketCount)
        for (offset, point) in interior.enumerated() {
            let bucketIndex = Swift.min(offset * bucketCount / Swift.max(interior.count, 1), bucketCount - 1)
            buckets[bucketIndex].append(point)
        }

        var reduced: [Element] = []
        reduced.reserveCapacity(maximumPointCount)
        reduced.append(self[0])
        for bucket in buckets where !bucket.isEmpty {
            guard let minimum = bucket.min(by: { $0.latencyMilliseconds < $1.latencyMilliseconds }),
                  let maximum = bucket.max(by: { $0.latencyMilliseconds < $1.latencyMilliseconds }) else {
                continue
            }
            if minimum.timestamp <= maximum.timestamp {
                reduced.append(minimum)
                if maximum != minimum { reduced.append(maximum) }
            } else {
                reduced.append(maximum)
                if maximum != minimum { reduced.append(minimum) }
            }
        }
        reduced.append(self[count - 1])
        return reduced
    }
}

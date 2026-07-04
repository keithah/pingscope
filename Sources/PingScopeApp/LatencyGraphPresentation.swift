import PingScopeCore
import SwiftUI

struct HostLatencyGraphSeries: Identifiable {
    let host: HostConfig
    let samples: [PingResult]
    let color: Color
    let isPrimary: Bool

    var id: UUID { host.id }

    static let palette: [Color] = [
        .blue,
        .green,
        .orange,
        .purple,
        .pink,
        .cyan
    ]
}

struct LatencyGraphPoint {
    let index: Int
    let latencyMilliseconds: Double?

    func xPosition(sampleCount: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(index) / CGFloat(max(sampleCount - 1, 1))
    }
}

struct LatencyGraphData {
    let points: [LatencyGraphPoint]
    let scale: LatencyGraphScale
    let sampleCount: Int
    private let latencyCount: Int

    init(samples: [PingResult]) {
        var latencies: [Double] = []
        latencies.reserveCapacity(samples.count)
        var points: [LatencyGraphPoint] = []
        points.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            let latency = sample.latency?.milliseconds
            if let latency {
                latencies.append(latency)
            }
            points.append(LatencyGraphPoint(index: index, latencyMilliseconds: latency))
        }
        self.points = points
        self.sampleCount = samples.count
        self.latencyCount = latencies.count
        scale = LatencyGraphScale(latencies: latencies)
    }

    var isEmpty: Bool {
        points.isEmpty
    }

    var hasLatencyData: Bool {
        latencyCount > 0
    }

    func renderPoints(pixelWidth: CGFloat) -> [LatencyGraphPoint] {
        points.downsampled(toPixelWidth: pixelWidth, sampleCount: sampleCount)
    }
}

struct DrawableHostLatencyGraphSeries {
    let source: HostLatencyGraphSeries
    let points: [LatencyGraphPoint]
    let sampleCount: Int

    func renderPoints(pixelWidth: CGFloat) -> [LatencyGraphPoint] {
        points.downsampled(toPixelWidth: pixelWidth, sampleCount: sampleCount)
    }
}

struct MultiHostLatencyGraphData {
    let drawableSeries: [DrawableHostLatencyGraphSeries]
    let scale: LatencyGraphScale
    private let latencyCount: Int

    init(series: [HostLatencyGraphSeries]) {
        var latencies: [Double] = []
        var drawableSeries: [DrawableHostLatencyGraphSeries] = []
        for hostSeries in series {
            var points: [LatencyGraphPoint] = []
            points.reserveCapacity(hostSeries.samples.count)
            for (index, sample) in hostSeries.samples.enumerated() {
                let latency = sample.latency?.milliseconds
                if let latency {
                    latencies.append(latency)
                }
                points.append(LatencyGraphPoint(index: index, latencyMilliseconds: latency))
            }
            // Fully-failed series must still be drawn: their line is a no-op but
            // the primary host's failure marks are exactly what an outage looks
            // like. Only a series with no samples at all has nothing to render.
            if !points.isEmpty {
                drawableSeries.append(DrawableHostLatencyGraphSeries(source: hostSeries, points: points, sampleCount: hostSeries.samples.count))
            }
        }
        self.drawableSeries = drawableSeries
        self.latencyCount = latencies.count
        scale = LatencyGraphScale(latencies: latencies)
    }

    var isEmpty: Bool {
        drawableSeries.isEmpty
    }

    var hasLatencyData: Bool {
        latencyCount > 0
    }
}

private struct LatencyGraphPointBucket {
    private var minLatencyPoint: LatencyGraphPoint?
    private var maxLatencyPoint: LatencyGraphPoint?
    private var latestLatencyPoint: LatencyGraphPoint?
    private var latestFailurePoint: LatencyGraphPoint?

    mutating func append(_ point: LatencyGraphPoint) {
        guard let latency = point.latencyMilliseconds else {
            latestFailurePoint = point
            return
        }
        if minLatencyPoint?.latencyMilliseconds.map({ latency < $0 }) ?? true {
            minLatencyPoint = point
        }
        if maxLatencyPoint?.latencyMilliseconds.map({ latency > $0 }) ?? true {
            maxLatencyPoint = point
        }
        latestLatencyPoint = point
    }

    var points: [LatencyGraphPoint] {
        var selected: [LatencyGraphPoint] = []
        selected.reserveCapacity(4)
        append(latestFailurePoint, to: &selected)
        append(minLatencyPoint, to: &selected)
        append(maxLatencyPoint, to: &selected)
        append(latestLatencyPoint, to: &selected)
        selected.sort { $0.index < $1.index }
        return selected
    }

    private func append(_ point: LatencyGraphPoint?, to selected: inout [LatencyGraphPoint]) {
        guard let point, !selected.contains(where: { $0.index == point.index }) else { return }
        selected.append(point)
    }
}

private extension Array where Element == LatencyGraphPoint {
    func downsampled(toPixelWidth width: CGFloat, sampleCount: Int) -> [LatencyGraphPoint] {
        let pixelColumns = Swift.max(Int(width.rounded(.up)), 1)
        guard count > pixelColumns * 2, sampleCount > 1 else { return self }

        var buckets = Swift.Array(repeating: LatencyGraphPointBucket(), count: pixelColumns)
        for point in self {
            let normalized = CGFloat(point.index) / CGFloat(Swift.max(sampleCount - 1, 1))
            let bucketIndex = Swift.min(
                Swift.max(Int((normalized * CGFloat(pixelColumns - 1)).rounded(.down)), 0),
                pixelColumns - 1
            )
            buckets[bucketIndex].append(point)
        }
        return buckets.flatMap { $0.points }
    }
}

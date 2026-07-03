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
}

struct LatencyGraphData {
    let points: [LatencyGraphPoint]
    let scale: LatencyGraphScale
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
        self.latencyCount = latencies.count
        scale = LatencyGraphScale(latencies: latencies)
    }

    var isEmpty: Bool {
        points.isEmpty
    }

    var hasLatencyData: Bool {
        latencyCount > 0
    }
}

struct DrawableHostLatencyGraphSeries {
    let source: HostLatencyGraphSeries
    let points: [LatencyGraphPoint]
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
                drawableSeries.append(DrawableHostLatencyGraphSeries(source: hostSeries, points: points))
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

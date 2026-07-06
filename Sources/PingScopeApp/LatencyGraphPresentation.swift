import Foundation
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
    private let renderPointCache = LatencyGraphRenderPointCache()

    init(samples: [PingResult]) {
        var latencyCount = 0
        var maximumLatency: Double?
        var points: [LatencyGraphPoint] = []
        points.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            let latency = sample.latency?.milliseconds
            if let latency {
                latencyCount += 1
                maximumLatency = maximumLatency.map { max($0, latency) } ?? latency
            }
            points.append(LatencyGraphPoint(index: index, latencyMilliseconds: latency))
        }
        self.points = points
        self.sampleCount = samples.count
        self.latencyCount = latencyCount
        scale = LatencyGraphScale(maximumMilliseconds: maximumLatency)
    }

    var isEmpty: Bool {
        points.isEmpty
    }

    var hasLatencyData: Bool {
        latencyCount > 0
    }

    func renderPoints(pixelWidth: CGFloat) -> [LatencyGraphPoint] {
        renderPointCache.renderPoints(points: points, pixelWidth: pixelWidth, sampleCount: sampleCount)
    }

    var renderPointCacheEntryCount: Int {
        renderPointCache.entryCount
    }

    var renderPointCacheKeys: Set<Int> {
        renderPointCache.keys
    }
}

struct DrawableHostLatencyGraphSeries {
    let source: HostLatencyGraphSeries
    let points: [LatencyGraphPoint]
    let sampleCount: Int
    private let renderPointCache = LatencyGraphRenderPointCache()

    func renderPoints(pixelWidth: CGFloat) -> [LatencyGraphPoint] {
        renderPointCache.renderPoints(points: points, pixelWidth: pixelWidth, sampleCount: sampleCount)
    }

    var renderPointCacheEntryCount: Int {
        renderPointCache.entryCount
    }

    var renderPointCacheKeys: Set<Int> {
        renderPointCache.keys
    }
}

struct MultiHostLatencyGraphData {
    let drawableSeries: [DrawableHostLatencyGraphSeries]
    let visibleLegendSeries: [HostLatencyGraphSeries]
    let scale: LatencyGraphScale
    private let latencyCount: Int

    init(series: [HostLatencyGraphSeries]) {
        var latencyCount = 0
        var maximumLatency: Double?
        var drawableSeries: [DrawableHostLatencyGraphSeries] = []
        var visibleLegendSeries: [HostLatencyGraphSeries] = []
        visibleLegendSeries.reserveCapacity(4)
        for hostSeries in series {
            var points: [LatencyGraphPoint] = []
            points.reserveCapacity(hostSeries.samples.count)
            for (index, sample) in hostSeries.samples.enumerated() {
                let latency = sample.latency?.milliseconds
                if let latency {
                    latencyCount += 1
                    maximumLatency = maximumLatency.map { max($0, latency) } ?? latency
                }
                points.append(LatencyGraphPoint(index: index, latencyMilliseconds: latency))
            }
            // Fully-failed series must still be drawn: their line is a no-op but
            // the primary host's failure marks are exactly what an outage looks
            // like. Only a series with no samples at all has nothing to render.
            if !points.isEmpty {
                drawableSeries.append(DrawableHostLatencyGraphSeries(source: hostSeries, points: points, sampleCount: hostSeries.samples.count))
                if visibleLegendSeries.count < 4 {
                    visibleLegendSeries.append(hostSeries)
                }
            }
        }
        self.drawableSeries = drawableSeries
        self.visibleLegendSeries = visibleLegendSeries
        self.latencyCount = latencyCount
        scale = LatencyGraphScale(maximumMilliseconds: maximumLatency)
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

private final class LatencyGraphRenderPointCache {
    private let maximumEntryCount = 4
    private let lock = NSLock()
    private var cache: [Int: [LatencyGraphPoint]] = [:]
    private var recentKeys: [Int] = []

    var entryCount: Int {
        lock.withLock { cache.count }
    }

    var keys: Set<Int> {
        lock.withLock { Set(cache.keys) }
    }

    func renderPoints(points: [LatencyGraphPoint], pixelWidth: CGFloat, sampleCount: Int) -> [LatencyGraphPoint] {
        lock.withLock {
            let pixelColumns = Swift.max(Int(pixelWidth.rounded(.up)), 1)
            if let cached = cache[pixelColumns] {
                markRecentlyUsed(pixelColumns)
                return cached
            }
            let renderPoints = points.downsampled(toPixelColumns: pixelColumns, sampleCount: sampleCount)
            cache[pixelColumns] = renderPoints
            markRecentlyUsed(pixelColumns)
            evictIfNeeded()
            return renderPoints
        }
    }

    private func markRecentlyUsed(_ key: Int) {
        recentKeys.removeAll { $0 == key }
        recentKeys.append(key)
    }

    private func evictIfNeeded() {
        while recentKeys.count > maximumEntryCount {
            let evicted = recentKeys.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

private extension Array where Element == LatencyGraphPoint {
    func downsampled(toPixelColumns pixelColumns: Int, sampleCount: Int) -> [LatencyGraphPoint] {
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

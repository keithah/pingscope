import Foundation
import PingScopeCore

/// Platform-neutral content for a report card built from one exact History window.
public struct HistoryReportPresentation: Equatable, Sendable {
    public let brand: String
    public let hostName: String
    public let rangeLabel: String
    public let sampleCount: Int
    public let averageMilliseconds: Double?
    public let minimumMilliseconds: Double?
    public let p95Milliseconds: Double?
    public let maximumMilliseconds: Double?
    public let lossPercent: Double?
    public let uptimePercent: Double?
    public let graphPresentation: PingScopeIOSHistoryGraphPresentation
    public let networkPresentation: HistoryNetworkPresentation
    public let sessions: [HistorySession]

    public init(host: HostConfig, range: HistoryRange, samples: [PingResult]) {
        brand = "PingScope"
        hostName = host.displayName
        rangeLabel = range.rawValue
        sampleCount = samples.count
        let metrics = HistoryMetrics(samples: samples)
        averageMilliseconds = metrics.averageMilliseconds
        minimumMilliseconds = metrics.minimumMilliseconds
        p95Milliseconds = metrics.p95Milliseconds
        maximumMilliseconds = metrics.maximumMilliseconds
        lossPercent = samples.isEmpty ? nil : metrics.lossPercent
        uptimePercent = samples.isEmpty ? nil : metrics.uptimePercent
        graphPresentation = PingScopeIOSHistoryGraphPresentation(
            reduction: HistoryChartReduction(samples: samples, maximumBucketCount: 120)
        )
        networkPresentation = HistoryNetworkPresentation(samples: samples)
        sessions = HistorySession.sessionize(samples)
    }
}

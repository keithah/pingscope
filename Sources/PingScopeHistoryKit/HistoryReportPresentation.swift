import Foundation
import PingScopeCore

public struct HistoryLocationPresentation: Equatable, Sendable {
    public let locatedSampleCount: Int
    public let totalSampleCount: Int
    public let latestCoordinateText: String?
    public let latestAccuracyText: String?
    public let networkLabels: [String]

    public init(samples: [PingResult], networkLabels: [String]) {
        totalSampleCount = samples.count
        let located = samples.compactMap { sample -> (PingResult, SampleLocation)? in
            guard let location = sample.location,
                  location.latitude.isFinite,
                  location.longitude.isFinite,
                  (-90...90).contains(location.latitude),
                  (-180...180).contains(location.longitude) else { return nil }
            return (sample, location)
        }
        locatedSampleCount = located.count
        let latest = located.max { lhs, rhs in
            if lhs.0.timestamp != rhs.0.timestamp { return lhs.0.timestamp < rhs.0.timestamp }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }?.1
        latestCoordinateText = latest.map {
            String(
                format: "%.4f, %.4f",
                locale: Locale(identifier: "en_US_POSIX"),
                $0.latitude,
                $0.longitude
            )
        }
        latestAccuracyText = latest?.horizontalAccuracy.flatMap(Self.accuracyText(for:))
        self.networkLabels = networkLabels
    }

    public init(samples: [PingResult], mapSummary: HistoryMapSummary) {
        self.init(samples: samples, networkLabels: mapSummary.networkLabels)
    }

    static func accuracyText(for accuracy: Double) -> String? {
        guard accuracy.isFinite else { return nil }
        let rounded = max(accuracy, 0).rounded()
        guard rounded < Double(Int.max) else { return nil }
        return "±\(Int(rounded)) m"
    }
}

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
    public let locationPresentation: HistoryLocationPresentation
    public let sessions: [HistorySession]

    public init(
        host: HostConfig,
        range: HistoryRange,
        samples: [PingResult],
        mapSummary: HistoryMapSummary? = nil
    ) {
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
        locationPresentation = HistoryLocationPresentation(
            samples: samples,
            networkLabels: mapSummary?.networkLabels ?? HistoryMapPresentation.networkLabels(samples: samples)
        )
        sessions = HistorySession.sessionize(samples)
    }
}

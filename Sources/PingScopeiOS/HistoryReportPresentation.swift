import Foundation
import PingScopeCore

public enum HistoryReportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case pdf

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.uppercased()
    }

    public var fileExtension: String { rawValue }
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
    }
}

public struct HistoryReportFilePlanner: Sendable {
    public let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func destination(hostName: String, format: HistoryReportFormat) -> URL {
        let slug = hostName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = slug.isEmpty ? "history" : slug
        return temporaryDirectory.appendingPathComponent(
            "pingscope-\(prefix)-\(UUID().uuidString).\(format.fileExtension)",
            isDirectory: false
        )
    }
}

/// Owns the platform-neutral temporary-file transaction around report rendering.
/// The caller supplies rendering/writing so UIKit remains in the app target.
public struct HistoryReportFileLifecycle {
    private let fileManager: FileManager
    private let planner: HistoryReportFilePlanner

    public init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.planner = HistoryReportFilePlanner(temporaryDirectory: temporaryDirectory)
    }

    public func export(
        hostName: String,
        format: HistoryReportFormat,
        write: (URL) throws -> Void
    ) throws -> HistorySharePayload {
        try fileManager.createDirectory(
            at: planner.temporaryDirectory,
            withIntermediateDirectories: true
        )
        let destination = planner.destination(hostName: hostName, format: format)
        do {
            try write(destination)
            return HistorySharePayload(files: [destination])
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }
}

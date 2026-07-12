import CoreGraphics
import Foundation
import PingScopeCore

public struct PingScopeLiveActivityRowPresentation: Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public let status: HealthStatus
    public let statusAccessibilityDescription: String
    public let latencyMilliseconds: Int?
    public let samples: [Int]

    public var latencyText: String {
        latencyMilliseconds.map { "\($0)ms" } ?? "--ms"
    }

    public var accessibilityLabel: String {
        let latencyDescription = latencyMilliseconds.map { "\($0) milliseconds" } ?? "Latency unavailable"
        return "\(displayName), \(endpointCaption), \(statusAccessibilityDescription), \(latencyDescription)"
    }
}

public enum PingScopeLiveActivityPresentation {
    public static func rows(
        attributes: PingScopeLiveActivityAttributes,
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> [PingScopeLiveActivityRowPresentation] {
        switch contentState.mode {
        case .focused:
            let renderedStatus = displayStatus(contentState.status, isStale: contentState.isStale)
            let samples = contentState.hostRows
                .first(where: { $0.hostID == attributes.hostID })?
                .samples ?? []
            return [
                PingScopeLiveActivityRowPresentation(
                    hostID: attributes.hostID,
                    displayName: attributes.hostName,
                    endpointCaption: "\(attributes.method.displayName) \(attributes.address)",
                    status: renderedStatus,
                    statusAccessibilityDescription: accessibilityStatusDescription(
                        contentState.status,
                        isStale: contentState.isStale
                    ),
                    latencyMilliseconds: visibleLatency(
                        contentState.latencyMilliseconds,
                        status: contentState.status,
                        isStale: contentState.isStale
                    ),
                    samples: samples
                )
            ]
        case .allHosts:
            return contentState.hostRows.map { row in
                let renderedStatus = displayStatus(row.status, isStale: row.isStale)
                return PingScopeLiveActivityRowPresentation(
                    hostID: row.hostID,
                    displayName: row.displayName,
                    endpointCaption: row.endpointCaption,
                    status: renderedStatus,
                    statusAccessibilityDescription: accessibilityStatusDescription(
                        row.status,
                        isStale: row.isStale
                    ),
                    latencyMilliseconds: visibleLatency(
                        row.latestLatencyMilliseconds,
                        status: row.status,
                        isStale: row.isStale
                    ),
                    samples: row.samples
                )
            }
        }
    }

    public static func sessionText(
        duration: MonitorSessionDuration,
        remainingSeconds: Int,
        isStale: Bool = false
    ) -> String {
        if duration == .continuous {
            return isStale ? "Stale" : "Live"
        }
        guard remainingSeconds > 0 else {
            return "Ended"
        }
        return "\(remainingSeconds)s"
    }

    public static func aggregateStatus(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> HealthStatus {
        displayStatus(contentState.status, isStale: contentState.isStale)
    }

    public static func aggregateStatusAccessibilityDescription(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> String {
        accessibilityStatusDescription(contentState.status, isStale: contentState.isStale)
    }

    private static func visibleLatency(
        _ latencyMilliseconds: Int?,
        status: HealthStatus,
        isStale: Bool
    ) -> Int? {
        guard !isStale, status != .noData, status != .down else {
            return nil
        }
        return latencyMilliseconds
    }

    private static func displayStatus(_ status: HealthStatus, isStale: Bool) -> HealthStatus {
        isStale ? .noData : status
    }

    private static func accessibilityStatusDescription(
        _ status: HealthStatus,
        isStale: Bool
    ) -> String {
        isStale ? "Stale" : status.accessibilityDescription
    }
}

public enum PingScopeLiveActivitySparklinePresentation {
    public static func points(samples: [Int], in size: CGSize) -> [CGPoint] {
        let inset: CGFloat = 1
        guard samples.count > 1, size.width > inset * 2, size.height > inset * 2 else {
            return []
        }

        let minimum = Double(samples.min() ?? 0)
        let maximum = Double(samples.max() ?? 0)
        let range = max(maximum - minimum, 1)
        let lastIndex = samples.count - 1

        return samples.enumerated().map { index, sample in
            let progress = CGFloat(index) / CGFloat(lastIndex)
            let normalized = (Double(sample) - minimum) / range
            return CGPoint(
                x: inset + progress * (size.width - inset * 2),
                y: inset + (1 - CGFloat(normalized)) * (size.height - inset * 2)
            )
        }
    }
}

private extension HealthStatus {
    var accessibilityDescription: String {
        switch self {
        case .noData: "No data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

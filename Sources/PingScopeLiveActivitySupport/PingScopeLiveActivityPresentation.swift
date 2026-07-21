import CoreGraphics
import Foundation

public enum PingScopeLiveActivityLayout {
    public static let lockScreenActivityHeightLimit: CGFloat = 160
    public static let lockScreenHorizontalPadding: CGFloat = 16
    public static let lockScreenVerticalPadding: CGFloat = 8
    public static let lockScreenRowHeight: CGFloat = 36
    public static let lockScreenStackSpacing: CGFloat = 3
    public static let lockScreenSessionHeight: CGFloat = 12

    public static let expandedIslandSafeHeightLimit: CGFloat = 136
    public static let expandedIslandHorizontalPadding: CGFloat = 12
    public static let expandedIslandBottomPadding: CGFloat = 8
    public static let expandedIslandRowHeight: CGFloat = 32
    public static let expandedIslandStackSpacing: CGFloat = 3
    public static let expandedIslandSessionHeight: CGFloat = 11

    public static var maximumLockScreenContentHeight: CGFloat {
        lockScreenContentHeight(forHostRows: PingScopeLiveActivityAttributes.ContentState.hostRowLimit)
    }

    public static var maximumExpandedIslandContentHeight: CGFloat {
        expandedIslandContentHeight(forHostRows: PingScopeLiveActivityAttributes.ContentState.hostRowLimit)
    }

    public static func lockScreenContentHeight(forHostRows hostRows: Int) -> CGFloat {
        verticalContentHeight(
            rowCount: cappedHostRowCount(hostRows),
            rowHeight: lockScreenRowHeight,
            sessionHeight: lockScreenSessionHeight,
            stackSpacing: lockScreenStackSpacing,
            topPadding: lockScreenVerticalPadding,
            bottomPadding: lockScreenVerticalPadding
        )
    }

    public static func expandedIslandContentHeight(forHostRows hostRows: Int) -> CGFloat {
        verticalContentHeight(
            rowCount: cappedHostRowCount(hostRows),
            rowHeight: expandedIslandRowHeight,
            sessionHeight: expandedIslandSessionHeight,
            stackSpacing: expandedIslandStackSpacing,
            topPadding: 0,
            bottomPadding: expandedIslandBottomPadding
        )
    }

    private static func cappedHostRowCount(_ hostRows: Int) -> Int {
        min(max(hostRows, 0), PingScopeLiveActivityAttributes.ContentState.hostRowLimit)
    }

    private static func verticalContentHeight(
        rowCount: Int,
        rowHeight: CGFloat,
        sessionHeight: CGFloat,
        stackSpacing: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> CGFloat {
        CGFloat(rowCount) * rowHeight
            + sessionHeight
            + CGFloat(rowCount) * stackSpacing
            + topPadding
            + bottomPadding
    }
}

public struct PingScopeLiveActivityRowPresentation: Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let endpointCaption: String
    public let status: PingScopeLiveActivityHealthStatus
    public let statusAccessibilityDescription: String
    public let latencyMilliseconds: Int?
    public let samples: [Int]
    public let identityColor: WidgetGraphDisplayColor

    public var latencyText: String {
        latencyMilliseconds.map { "\($0)ms" } ?? "--ms"
    }

    public var accessibilityLabel: String {
        let latencyDescription = latencyMilliseconds.map { "\($0) milliseconds" } ?? "Latency unavailable"
        return "\(displayName), \(endpointCaption), \(statusAccessibilityDescription), \(latencyDescription)"
    }
}

public enum PingScopeLiveActivityPresentation {
    public enum DynamicIslandContentStyle: Equatable, Sendable {
        case rich
        case statusOnly
    }

    public static func dynamicIslandContentStyle(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> DynamicIslandContentStyle {
        contentState.showsDynamicIslandDetails ? .rich : .statusOnly
    }

    public static func rows(
        attributes: PingScopeLiveActivityAttributes,
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> [PingScopeLiveActivityRowPresentation] {
        presentedRows(
            attributes: attributes,
            contentState: contentState,
            allHostRows: contentState.hostRows
        )
    }

    public static func dynamicIslandRows(
        attributes: PingScopeLiveActivityAttributes,
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> [PingScopeLiveActivityRowPresentation] {
        presentedRows(
            attributes: attributes,
            contentState: contentState,
            allHostRows: contentState.hostRows.filter { !$0.isDefaultGateway }
        )
    }

    private static func presentedRows(
        attributes: PingScopeLiveActivityAttributes,
        contentState: PingScopeLiveActivityAttributes.ContentState,
        allHostRows: [PingScopeLiveActivityHostRow]
    ) -> [PingScopeLiveActivityRowPresentation] {
        switch contentState.mode {
        case .focused:
            let renderedStatus = displayStatus(contentState.status, isStale: contentState.isStale)
            let payloadRow = contentState.hostRows.first { $0.hostID == attributes.hostID }
            let samples = payloadRow?.samples ?? []
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
                    samples: samples,
                    identityColor: payloadRow?.identityColor ?? attributes.identityColor
                )
            ]
        case .allHosts:
            return allHostRows.map { row in
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
                    samples: row.samples,
                    identityColor: row.identityColor
                )
            }
        }
    }

    public static func sessionText(
        duration: PingScopeLiveActivityDuration,
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
    ) -> PingScopeLiveActivityHealthStatus {
        displayStatus(contentState.status, isStale: contentState.isStale)
    }

    public static func aggregateStatusAccessibilityDescription(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> String {
        accessibilityStatusDescription(contentState.status, isStale: contentState.isStale)
    }

    public static func dynamicIslandAggregateStatus(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> PingScopeLiveActivityHealthStatus {
        guard contentState.mode == .allHosts else {
            return aggregateStatus(contentState: contentState)
        }
        let statuses = contentState.hostRows
            .filter { !$0.isDefaultGateway }
            .map { displayStatus($0.status, isStale: $0.isStale) }
        if statuses.contains(.down) { return .down }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.healthy) { return .healthy }
        return .noData
    }

    public static func dynamicIslandAggregateStatusAccessibilityDescription(
        contentState: PingScopeLiveActivityAttributes.ContentState
    ) -> String {
        guard contentState.mode == .allHosts else {
            return aggregateStatusAccessibilityDescription(contentState: contentState)
        }
        return dynamicIslandAggregateStatus(contentState: contentState).accessibilityDescription
    }

    private static func visibleLatency(
        _ latencyMilliseconds: Int?,
        status: PingScopeLiveActivityHealthStatus,
        isStale: Bool
    ) -> Int? {
        guard !isStale, status != .noData, status != .down else {
            return nil
        }
        return latencyMilliseconds
    }

    private static func displayStatus(
        _ status: PingScopeLiveActivityHealthStatus,
        isStale: Bool
    ) -> PingScopeLiveActivityHealthStatus {
        isStale ? .noData : status
    }

    private static func accessibilityStatusDescription(
        _ status: PingScopeLiveActivityHealthStatus,
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

private extension PingScopeLiveActivityHealthStatus {
    var accessibilityDescription: String {
        switch self {
        case .noData: "No data"
        case .healthy: "Healthy"
        case .degraded: "Degraded"
        case .down: "Down"
        }
    }
}

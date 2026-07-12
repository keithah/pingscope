import ActivityKit
import CoreGraphics
import PingScopeCore
import PingScopeiOS
import SwiftUI
import WidgetKit

@main
struct PingScopeLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PingScopeLiveActivityWidget()
    }
}

struct PingScopeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PingScopeLiveActivityAttributes.self) { context in
            PingScopeLiveActivityView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    PingScopeLiveActivityRowsView(
                        rows: rows(for: context),
                        sessionText: sessionText(for: context),
                        density: .expanded
                    )
                    .padding(.horizontal, PingScopeLiveActivityLayout.expandedIslandHorizontalPadding)
                    .padding(.bottom, PingScopeLiveActivityLayout.expandedIslandBottomPadding)
                }
            } compactLeading: {
                statusDot(aggregateStatus(for: context), diameter: 7)
                    .accessibilityLabel("\(aggregateStatusDescription(for: context)) status")
            } compactTrailing: {
                Text(sessionText(for: context))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 30, alignment: .trailing)
                    .accessibilityLabel("Session \(sessionText(for: context))")
            } minimal: {
                HStack(spacing: 2) {
                    statusDot(aggregateStatus(for: context), diameter: 6)
                    Text(sessionText(for: context))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: 24, alignment: .leading)
                }
                .frame(width: 34, height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(aggregateStatusDescription(for: context)) status, session \(sessionText(for: context))")
            }
        }
    }

    private func rows(
        for context: ActivityViewContext<PingScopeLiveActivityAttributes>
    ) -> [PingScopeLiveActivityRowPresentation] {
        PingScopeLiveActivityPresentation.rows(
            attributes: context.attributes,
            contentState: context.state
        )
    }

    private func sessionText(
        for context: ActivityViewContext<PingScopeLiveActivityAttributes>
    ) -> String {
        PingScopeLiveActivityPresentation.sessionText(
            duration: context.attributes.duration,
            remainingSeconds: context.state.remainingSeconds,
            isStale: context.state.isStale
        )
    }

    private func aggregateStatus(
        for context: ActivityViewContext<PingScopeLiveActivityAttributes>
    ) -> HealthStatus {
        PingScopeLiveActivityPresentation.aggregateStatus(contentState: context.state)
    }

    private func aggregateStatusDescription(
        for context: ActivityViewContext<PingScopeLiveActivityAttributes>
    ) -> String {
        PingScopeLiveActivityPresentation.aggregateStatusAccessibilityDescription(
            contentState: context.state
        )
    }
}

private struct PingScopeLiveActivityView: View {
    let context: ActivityViewContext<PingScopeLiveActivityAttributes>

    var body: some View {
        PingScopeLiveActivityRowsView(
            rows: PingScopeLiveActivityPresentation.rows(
                attributes: context.attributes,
                contentState: context.state
            ),
            sessionText: PingScopeLiveActivityPresentation.sessionText(
                duration: context.attributes.duration,
                remainingSeconds: context.state.remainingSeconds,
                isStale: context.state.isStale
            ),
            density: .lockScreen
        )
        .padding(.horizontal, PingScopeLiveActivityLayout.lockScreenHorizontalPadding)
        .padding(.vertical, PingScopeLiveActivityLayout.lockScreenVerticalPadding)
    }
}

private struct PingScopeLiveActivityRowsView: View {
    let rows: [PingScopeLiveActivityRowPresentation]
    let sessionText: String
    let density: PingScopeLiveActivityRowDensity

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowSpacing) {
            ForEach(rows.prefix(PingScopeLiveActivityAttributes.ContentState.hostRowLimit), id: \.hostID) { row in
                PingScopeLiveActivityHostRowView(row: row, density: density)
            }
            Text(sessionText)
                .font(density.sessionFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: density.sessionHeight, maxHeight: density.sessionHeight, alignment: .trailing)
                .accessibilityLabel("Session \(sessionText)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PingScopeLiveActivityHostRowView: View {
    let row: PingScopeLiveActivityRowPresentation
    let density: PingScopeLiveActivityRowDensity

    var body: some View {
        HStack(spacing: density.columnSpacing) {
            statusDot(row.status, diameter: density.dotDiameter)
                .frame(width: density.dotDiameter, height: density.dotDiameter)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(density.nameFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                Text(row.endpointCaption)
                    .font(density.endpointFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: density.identityWidth, alignment: .leading)

            PingScopeLiveActivitySparkline(samples: row.samples)
                .frame(width: density.sparklineWidth, height: density.sparklineHeight)

            Text(row.latencyText)
                .font(density.latencyFont)
                .foregroundStyle(color(for: row.status))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: density.latencyWidth, alignment: .trailing)
        }
        .frame(height: density.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct PingScopeLiveActivitySparkline: View {
    let samples: [Int]

    var body: some View {
        GeometryReader { proxy in
            let points = PingScopeLiveActivitySparklinePresentation.points(
                samples: samples,
                in: proxy.size
            )
            if points.count > 1 {
                Path(LatencyCurve.smoothedPath(points: points, closed: false))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private enum PingScopeLiveActivityRowDensity {
    case lockScreen
    case expanded

    var rowHeight: CGFloat {
        switch self {
        case .lockScreen: PingScopeLiveActivityLayout.lockScreenRowHeight
        case .expanded: PingScopeLiveActivityLayout.expandedIslandRowHeight
        }
    }

    var rowSpacing: CGFloat {
        switch self {
        case .lockScreen: PingScopeLiveActivityLayout.lockScreenStackSpacing
        case .expanded: PingScopeLiveActivityLayout.expandedIslandStackSpacing
        }
    }

    var columnSpacing: CGFloat {
        switch self {
        case .lockScreen: 7
        case .expanded: 6
        }
    }

    var dotDiameter: CGFloat {
        switch self {
        case .lockScreen: 7
        case .expanded: 7
        }
    }

    var identityWidth: CGFloat {
        switch self {
        case .lockScreen: 120
        case .expanded: 112
        }
    }

    var sparklineWidth: CGFloat {
        switch self {
        case .lockScreen: 62
        case .expanded: 60
        }
    }

    var sparklineHeight: CGFloat {
        switch self {
        case .lockScreen: 22
        case .expanded: 20
        }
    }

    var latencyWidth: CGFloat {
        switch self {
        case .lockScreen: 48
        case .expanded: 46
        }
    }

    var nameFont: Font {
        switch self {
        case .lockScreen: .system(size: 13, weight: .semibold)
        case .expanded: .system(size: 12, weight: .semibold)
        }
    }

    var endpointFont: Font {
        switch self {
        case .lockScreen: .system(size: 10, weight: .medium, design: .monospaced)
        case .expanded: .system(size: 9, weight: .medium, design: .monospaced)
        }
    }

    var latencyFont: Font {
        switch self {
        case .lockScreen: .system(size: 13, weight: .semibold, design: .monospaced)
        case .expanded: .system(size: 12, weight: .semibold, design: .monospaced)
        }
    }

    var sessionFont: Font {
        switch self {
        case .lockScreen: .caption2.monospacedDigit()
        case .expanded: .caption2.monospacedDigit()
        }
    }

    var sessionHeight: CGFloat {
        switch self {
        case .lockScreen: PingScopeLiveActivityLayout.lockScreenSessionHeight
        case .expanded: PingScopeLiveActivityLayout.expandedIslandSessionHeight
        }
    }
}

private func statusDot(_ status: HealthStatus, diameter: CGFloat = 10) -> some View {
    Circle()
        .fill(color(for: status))
        .frame(width: diameter, height: diameter)
}

private func color(for status: HealthStatus) -> Color {
    switch status {
    case .noData: .gray
    case .healthy: .green
    case .degraded: .yellow
    case .down: .red
    }
}

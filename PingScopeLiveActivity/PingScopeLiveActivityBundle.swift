import ActivityKit
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
                DynamicIslandExpandedRegion(.leading) {
                    hostLabel(context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    latencyLabel(context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    statusLabel(context)
                }
            } compactLeading: {
                latencyLabel(context)
            } compactTrailing: {
                statusDot(context.state.status)
            } minimal: {
                statusDot(context.state.status)
            }
        }
    }

    private func hostLabel(_ context: ActivityViewContext<PingScopeLiveActivityAttributes>) -> some View {
        Text(context.attributes.hostName)
            .font(.caption)
            .lineLimit(1)
    }

    private func latencyLabel(_ context: ActivityViewContext<PingScopeLiveActivityAttributes>) -> some View {
        Text(latencyText(context.state))
            .font(.caption.monospacedDigit())
            .lineLimit(1)
    }

    private func statusLabel(_ context: ActivityViewContext<PingScopeLiveActivityAttributes>) -> some View {
        HStack(spacing: 6) {
            statusDot(context.state.status)
            Text(context.state.isStale ? "Stale" : context.state.status.rawValue.capitalized)
                .font(.caption)
            Spacer()
            Text(remainingText(context))
                .font(.caption.monospacedDigit())
        }
    }
}

private struct PingScopeLiveActivityView: View {
    let context: ActivityViewContext<PingScopeLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            statusDot(context.state.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.hostName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(context.attributes.method.rawValue.uppercased()) \(context.attributes.address)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(latencyText(context.state))
                    .font(.title3.monospacedDigit())
                Text(remainingText(context))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private func remainingText(_ context: ActivityViewContext<PingScopeLiveActivityAttributes>) -> String {
    context.attributes.duration == .continuous ? "Live" : "\(context.state.remainingSeconds)s"
}

private func latencyText(_ state: PingScopeLiveActivityAttributes.ContentState) -> String {
    if let latencyMilliseconds = state.latencyMilliseconds {
        return "\(latencyMilliseconds)ms"
    }
    return "--ms"
}

private func statusDot(_ status: HealthStatus) -> some View {
    Circle()
        .fill(color(for: status))
        .frame(width: 10, height: 10)
}

private func color(for status: HealthStatus) -> Color {
    switch status {
    case .noData: .gray
    case .healthy: .green
    case .degraded: .yellow
    case .down: .red
    }
}

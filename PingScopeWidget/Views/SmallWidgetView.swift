import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        let presentation = ringPresentation

        WidgetHealthRing(
            progress: presentation.progress,
            color: presentation.color.opacity(presentation.isFailure ? 0.72 : 1)
        ) {
            VStack(spacing: 3) {
                if let latency = presentation.latency {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(latency.rounded()))")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text("ms")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(presentation.failureText)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Text(presentation.hostName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .opacity(entry.isStale ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            WidgetStatusStyle.backgroundColor
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    private var ringPresentation: SmallWidgetRingPresentation {
        if let snapshot = entry.snapshot,
           let host = snapshot.primaryHost {
            let health = snapshot.primaryHealth
            let latency = health?.latencyMilliseconds
            let isFailure = health?.status == "down" || latency == nil
            return SmallWidgetRingPresentation(
                hostName: host.displayName,
                latency: isFailure ? nil : latency,
                failureText: health?.failureReason ?? "--",
                color: isFailure ? .red : WidgetStatusStyle.color(for: health),
                progress: isFailure ? 1 : WidgetStatusStyle.ringProgress(forLatency: latency),
                isFailure: isFailure
            )
        }

        if let data = entry.data,
           let host = data.hosts.first,
           let result = data.results.first {
            return SmallWidgetRingPresentation(
                hostName: host.name,
                latency: result.isSuccess ? result.latencyMS : nil,
                failureText: result.isSuccess ? "--" : "Timeout",
                color: WidgetStatusStyle.color(for: result),
                progress: result.isSuccess
                    ? WidgetStatusStyle.ringProgress(forLatency: result.latencyMS)
                    : 1,
                isFailure: !result.isSuccess
            )
        }

        return SmallWidgetRingPresentation(
            hostName: "PingScope",
            latency: nil,
            failureText: "--",
            color: .red,
            progress: 1,
            isFailure: true
        )
    }
}

private struct SmallWidgetRingPresentation {
    let hostName: String
    let latency: Double?
    let failureText: String
    let color: Color
    let progress: Double
    let isFailure: Bool
}

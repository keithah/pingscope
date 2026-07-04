import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = entry.snapshot,
               let host = snapshot.primaryHost {
                let primaryHealth = snapshot.primaryHealth
                HStack(spacing: 7) {
                    Circle()
                        .fill(WidgetStatusStyle.color(for: primaryHealth))
                        .frame(width: 10, height: 10)

                    Text(host.displayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }

                if let latency = primaryHealth?.latencyMilliseconds {
                    Text("\(Int(latency.rounded()))ms")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text(primaryHealth?.failureReason ?? "No sample")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                WidgetStaleBadge(isStale: snapshot.isStale, label: snapshot.statusLabel)
            } else if let data = entry.data,
               let host = data.hosts.first,
               let result = data.results.first {

                HStack(spacing: 7) {
                    Circle()
                        .fill(WidgetStatusStyle.color(for: result))
                        .frame(width: 10, height: 10)

                    Text(host.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }

                if let latency = result.latencyMS {
                    Text("\(Int(latency.rounded()))ms")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Text("Timeout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                WidgetStaleBadge(isStale: data.isStale, label: data.isStale ? "Stale" : "Live")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PingScope")
                        .font(.headline)
                    Text("No shared data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .opacity(entry.isStale ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            WidgetStatusStyle.backgroundColor
        }
        .widgetURL(URL(string: "pingscope://open"))
    }
}

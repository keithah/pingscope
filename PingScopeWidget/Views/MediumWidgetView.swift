import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = entry.snapshot {
                let healthByHostID = snapshot.healthByHostID
                HStack(alignment: .top, spacing: 10) {
                    ForEach(snapshot.hosts.prefix(3), id: \.id) { host in
                        let health = healthByHostID[host.id]
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(WidgetStatusStyle.color(for: health))
                                    .frame(width: 7, height: 7)

                                Text(host.displayName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }

                            Text(WidgetStatusStyle.latencyText(for: health))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 8) {
                    WidgetLatencySparkline(samples: snapshot.recentSamples, color: .blue)
                        .frame(height: 28)
                    WidgetStaleBadge(isStale: snapshot.isStale, label: snapshot.statusLabel)
                }
            } else if let data = entry.data {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(zip(data.hosts.prefix(3), data.results.prefix(3))), id: \.0.id) { host, result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(WidgetStatusStyle.color(for: result))
                                    .frame(width: 7, height: 7)

                                Text(host.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }

                            if let latency = result.latencyMS {
                                Text("\(Int(latency.rounded()))ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Timeout")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
                WidgetStaleBadge(isStale: data.isStale, label: data.isStale ? "Stale" : "Live")
            }
        }
        .opacity(entry.isStale ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            WidgetStatusStyle.backgroundColor
        }
        .widgetURL(URL(string: "pingscope://open"))
    }
}

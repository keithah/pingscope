import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PingScope")
                    .font(.headline)

                Spacer()

                if let snapshot = entry.snapshot {
                    WidgetStaleBadge(isStale: snapshot.isStale, label: snapshot.statusLabel)
                } else if let data = entry.data {
                    WidgetStaleBadge(isStale: data.isStale, label: data.isStale ? "Stale" : "Live")
                }
            }

            if let snapshot = entry.snapshot {
                WidgetLatencySparkline(samples: snapshot.recentSamples, color: .blue)
                    .frame(height: 42)
                    .padding(.vertical, 2)

                ForEach(snapshot.hosts, id: \.id) { host in
                    let health = snapshot.health.first { $0.hostID == host.id }
                    HStack {
                        Circle()
                            .fill(WidgetStatusStyle.color(for: health))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.displayName)
                                .font(.subheadline.weight(host.isPrimary ? .semibold : .regular))
                                .lineLimit(1)
                            Text("\(host.method.uppercased()) \(host.address)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(WidgetStatusStyle.latencyText(for: health))
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 1)
                }
            } else if let data = entry.data {
                ForEach(Array(zip(data.hosts, data.results)), id: \.0.id) { host, result in
                    HStack {
                        Circle()
                            .fill(WidgetStatusStyle.color(for: result))
                            .frame(width: 8, height: 8)

                        Text(host.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        if let latency = result.latencyMS {
                            Text("\(Int(latency.rounded()))ms")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Timeout")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Spacer()
        }
        .opacity(isStale ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            WidgetStatusStyle.backgroundColor
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    private var isStale: Bool {
        entry.snapshot?.isStale ?? entry.data?.isStale ?? false
    }
}

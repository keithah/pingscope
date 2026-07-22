import SwiftUI
import WidgetKit
import PingScopeExtensionSupport

struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PingScope")
                    .font(.headline)

                Spacer()

                if let snapshot = entry.snapshot {
                    WidgetStaleBadge(isStale: entry.isStale, label: entry.statusLabel)
                } else if entry.data != nil {
                    WidgetStaleBadge(isStale: entry.isStale, label: entry.statusLabel)
                }
            }

            if let snapshot = entry.snapshot {
                let healthByHostID = snapshot.healthByHostID
                let presentation = snapshot.graphPresentation
                let layout = WidgetLargeFamilyLayout(hostCount: presentation.legend.count)
                WidgetHostKey(presentation: presentation, healthByHostID: healthByHostID)

                if WidgetFamilyRenderPolicy.forFamily(.large).showsSparkline {
                    WidgetMultiHostLatencyGraph(presentation: presentation)
                        .frame(height: 42)
                        .padding(.vertical, 2)
                }

                ForEach(presentation.legend.prefix(layout.detailRowCount), id: \.hostID) { entry in
                    if let host = snapshot.hosts.first(where: { $0.id == entry.hostID }) {
                        let health = healthByHostID[host.id]
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
        .opacity(entry.isStale ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            WidgetStatusStyle.backgroundColor
        }
        .widgetURL(URL(string: "pingscope://open"))
    }
}

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
                    Text(snapshot.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(snapshot.isStale ? .orange : .secondary)
                } else if let data = entry.data {
                    Text(data.lastUpdate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if data.isStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Divider()

            if let snapshot = entry.snapshot {
                ForEach(snapshot.hosts, id: \.id) { host in
                    let health = snapshot.health.first { $0.hostID == host.id }
                    HStack {
                        Circle()
                            .fill(statusColor(for: health))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(host.method.uppercased()) \(host.address)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(latencyText(for: health))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            } else if let data = entry.data {
                ForEach(Array(zip(data.hosts, data.results)), id: \.0.id) { host, result in
                    HStack {
                        Circle()
                            .fill(statusColor(for: result))
                            .frame(width: 10, height: 10)

                        Text(host.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        if let latency = result.latencyMS {
                            Text(String(format: "%.1f ms", latency))
                                .font(.caption)
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
            Color(nsColor: .controlBackgroundColor)
        }
        .widgetURL(URL(string: "pingscope://open"))
    }

    private func statusColor(for result: WidgetData.SimplifiedPingResult) -> Color {
        guard result.isSuccess, let latency = result.latencyMS else { return .red }
        if latency < 50 { return .green }
        if latency < 100 { return .yellow }
        return .red
    }

    private var isStale: Bool {
        entry.snapshot?.isStale ?? entry.data?.isStale ?? false
    }

    private func statusColor(for health: WidgetSnapshotData.HostHealth?) -> Color {
        guard let health else { return .gray }
        switch health.status {
        case "healthy": return .green
        case "degraded": return .yellow
        case "down": return .red
        default: return .gray
        }
    }

    private func latencyText(for health: WidgetSnapshotData.HostHealth?) -> String {
        if let latency = health?.latencyMilliseconds {
            return "\(Int(latency.rounded())) ms"
        }
        return health?.failureReason ?? "No sample"
    }
}

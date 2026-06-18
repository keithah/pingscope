import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            if let snapshot = entry.snapshot {
                ForEach(snapshot.hosts.prefix(3), id: \.id) { host in
                    let health = snapshot.health.first { $0.hostID == host.id }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(for: health))
                                .frame(width: 8, height: 8)

                            Text(host.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }

                        Text(latencyText(for: health))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if snapshot.isStale {
                    Label("Stale", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } else if let data = entry.data {
                ForEach(Array(zip(data.hosts.prefix(3), data.results.prefix(3))), id: \.0.id) { host, result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(for: result))
                                .frame(width: 8, height: 8)

                            Text(host.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }

                        if let latency = result.latencyMS {
                            Text(String(format: "%.1f ms", latency))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Timeout")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if data.isStale {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
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

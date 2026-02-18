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

                if let data = entry.data {
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

            if let data = entry.data {
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
        .opacity(entry.data?.isStale == true ? 0.6 : 1.0)
        .containerBackground(for: .widget) {
            Color(nsColor: .controlBackgroundColor)
        }
    }

    private func statusColor(for result: WidgetData.SimplifiedPingResult) -> Color {
        guard result.isSuccess, let latency = result.latencyMS else { return .red }
        if latency < 50 { return .green }
        if latency < 100 { return .yellow }
        return .red
    }
}

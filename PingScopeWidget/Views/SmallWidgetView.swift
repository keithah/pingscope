import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = entry.data,
               let host = data.hosts.first,
               let result = data.results.first {

                HStack {
                    Circle()
                        .fill(statusColor(for: result))
                        .frame(width: 12, height: 12)

                    Text(host.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let latency = result.latencyMS {
                    Text(String(format: "%.1f ms", latency))
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                } else {
                    Text("Timeout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if data.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Stale")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Text("No Data")
                    .foregroundColor(.secondary)
            }
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

import SwiftUI

struct RecentResultsListView: View {
    let rows: [DisplayViewModel.RecentResultRow]
    var maxVisibleRows: Int? = nil
    var compact: Bool = false
    var showHostName: Bool = true

    private let timeColumnWidth: CGFloat = 65
    private let pingColumnWidth: CGFloat = 56
    private let statusColumnWidth: CGFloat = 64

    var body: some View {
        Group {
            if rows.isEmpty {
                Text("No recent results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: compact ? 2 : 4) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 60, maxHeight: maxHeight)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: DisplayViewModel.RecentResultRow) -> some View {
        HStack(spacing: compact ? 4 : 10) {
            Text(timeText(for: row))
                .font(.system(size: compact ? 10 : 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: compact ? 50 : timeColumnWidth, alignment: .leading)
                .lineLimit(1)

            if showHostName, let hostName = row.hostName {
                Text(hostName)
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(pingTimeText(for: row))
                .font(.system(size: compact ? 10 : 12, weight: .medium).monospacedDigit())
                .foregroundStyle(compact ? statusColor(for: row) : .primary)
                .frame(width: compact ? 42 : pingColumnWidth, alignment: .trailing)

            if !compact {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: row))
                        .frame(width: 6, height: 6)

                    Text(statusText(for: row))
                        .font(.system(size: compact ? 11 : 12, weight: .medium).monospacedDigit())
                        .foregroundColor(statusColor(for: row))
                }
                .frame(width: statusColumnWidth, alignment: .trailing)
            }
        }
        .frame(height: compact ? 20 : 22)
    }

    private var maxHeight: CGFloat? {
        guard let maxVisibleRows else {
            return nil
        }

        let perRowHeight: CGFloat = compact ? 20 : 22
        return CGFloat(maxVisibleRows) * (perRowHeight + (compact ? 2 : 4))
    }

    private func statusColor(for row: DisplayViewModel.RecentResultRow) -> Color {
        guard let latencyMS = row.latencyMS else {
            return .red
        }

        // Use thresholds: green <= 80ms, yellow <= 150ms, red > 150ms
        if latencyMS <= 80 {
            return .green
        } else if latencyMS <= 150 {
            return .yellow
        } else {
            return .red
        }
    }

    private func pingTimeText(for row: DisplayViewModel.RecentResultRow) -> String {
        guard let latencyMS = row.latencyMS else {
            return "--"
        }

        return "\(Int(latencyMS.rounded()))ms"
    }

    private func statusText(for row: DisplayViewModel.RecentResultRow) -> String {
        row.latencyMS == nil ? "FAIL" : "OK"
    }

    private func timeText(for row: DisplayViewModel.RecentResultRow) -> String {
        (compact ? Self.compactTimeFormatter : Self.timeFormatter).string(from: row.timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter
    }()

    private static let compactTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm:ss"
        return formatter
    }()
}

#if DEBUG
struct RecentResultsListView_Previews: PreviewProvider {
    static var previews: some View {
        RecentResultsListView(rows: [
            .init(timestamp: .init(timeIntervalSinceNow: -5), latencyMS: 11, hostName: "Google"),
            .init(timestamp: .init(timeIntervalSinceNow: -10), latencyMS: 95, hostName: "Google"),
            .init(timestamp: .init(timeIntervalSinceNow: -15), latencyMS: nil, hostName: "Cloudflare"),
            .init(timestamp: .init(timeIntervalSinceNow: -20), latencyMS: 180, hostName: "Google")
        ], maxVisibleRows: 6, compact: false, showHostName: true)
        .padding()
        .frame(width: 320, height: 180)
    }
}
#endif

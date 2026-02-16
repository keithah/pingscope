import SwiftUI

struct RecentResultsListView: View {
    let rows: [DisplayViewModel.RecentResultRow]
    var maxVisibleRows: Int? = nil
    var compact: Bool = false
    var showHostName: Bool = true

    private let rowHeight: CGFloat = 22
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
        HStack(spacing: compact ? 6 : 10) {
            Text(Self.timeFormatter.string(from: row.timestamp))
                .font(.system(size: compact ? 11 : 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: compact ? 58 : timeColumnWidth, alignment: .leading)

            if showHostName, let hostName = row.hostName {
                Text(hostName)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(pingTimeText(for: row))
                .font(.system(size: compact ? 11 : 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: compact ? 48 : pingColumnWidth, alignment: .trailing)

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(for: row))
                    .frame(width: 6, height: 6)

                Text(statusText(for: row))
                    .font(.system(size: compact ? 11 : 12, weight: .medium).monospacedDigit())
                    .foregroundColor(statusColor(for: row))
            }
            .frame(width: compact ? 56 : statusColumnWidth, alignment: .trailing)
        }
        .frame(height: rowHeight)
    }

    private var maxHeight: CGFloat? {
        guard let maxVisibleRows else {
            return nil
        }

        return CGFloat(maxVisibleRows) * (rowHeight + (compact ? 2 : 4))
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
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

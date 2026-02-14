import SwiftUI

struct RecentResultsListView: View {
    let rows: [DisplayViewModel.RecentResultRow]
    var maxVisibleRows: Int? = nil

    private let rowHeight: CGFloat = 26

    var body: some View {
        Group {
            if rows.isEmpty {
                Text("No recent results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: DisplayViewModel.RecentResultRow) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(row.isSuccess ? Color.green : Color.red)
                .frame(width: 7, height: 7)

            Text(Self.timeFormatter.string(from: row.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(latencyText(for: row))
                .font(.caption.monospacedDigit())
                .foregroundStyle(row.isSuccess ? .primary : .secondary)
        }
        .frame(height: rowHeight)
    }

    private var maxHeight: CGFloat? {
        guard let maxVisibleRows else {
            return nil
        }

        return CGFloat(maxVisibleRows) * rowHeight
    }

    private func latencyText(for row: DisplayViewModel.RecentResultRow) -> String {
        guard let latencyMS = row.latencyMS else {
            return "Failed"
        }

        return "\(Int(latencyMS.rounded())) ms"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    RecentResultsListView(rows: [
        .init(timestamp: .init(timeIntervalSinceNow: -5), latencyMS: 41),
        .init(timestamp: .init(timeIntervalSinceNow: -10), latencyMS: nil),
        .init(timestamp: .init(timeIntervalSinceNow: -15), latencyMS: 38)
    ], maxVisibleRows: 6)
    .padding()
    .frame(width: 280, height: 180)
}

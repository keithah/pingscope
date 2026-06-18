import SwiftUI
#if os(iOS)
import UIKit
#endif

enum WidgetStatusStyle {
    static var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(.systemBackground)
        #endif
    }

    static func color(for health: WidgetSnapshotData.HostHealth?) -> Color {
        guard let health else { return .gray }
        switch health.status {
        case "healthy": return .green
        case "degraded": return .yellow
        case "down": return .red
        default: return .gray
        }
    }

    static func color(for result: WidgetData.SimplifiedPingResult) -> Color {
        guard result.isSuccess, let latency = result.latencyMS else { return .red }
        if latency < 50 { return .green }
        if latency < 100 { return .yellow }
        return .red
    }

    static func latencyText(for health: WidgetSnapshotData.HostHealth?) -> String {
        if let latency = health?.latencyMilliseconds {
            return "\(Int(latency.rounded()))ms"
        }
        return health?.failureReason ?? "No sample"
    }
}

struct WidgetStaleBadge: View {
    let isStale: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if isStale {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(isStale ? .orange : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isStale ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
    }
}

struct WidgetLatencySparkline: View {
    let samples: [WidgetSnapshotData.Sample]
    var color: Color = .blue

    var body: some View {
        let latencies = samples.compactMap(\.latencyMilliseconds)

        Canvas { context, size in
            guard latencies.count > 1 else {
                let baselineY = size.height * 0.72
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: baselineY))
                baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
                context.stroke(baseline, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                return
            }

            let maximum = max(latencies.max() ?? 1, 1)
            let minimum = latencies.min() ?? 0
            let span = max(maximum - minimum, 1)
            var path = Path()

            for (index, latency) in latencies.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(latencies.count - 1, 1))
                let normalized = (latency - minimum) / span
                let y = size.height - (size.height * CGFloat(normalized))
                let point = CGPoint(x: x, y: min(max(y, 1), size.height - 1))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 1.6)
        }
    }
}

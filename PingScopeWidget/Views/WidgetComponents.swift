import SwiftUI
import PingScopeExtensionSupport
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum WidgetStatusStyle {
    static let degradedThresholdMS = 50.0
    static let downThresholdMS = 100.0

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
        return ringColor(forLatency: latency)
    }

    static func ringColor(forLatency ms: Double?) -> Color {
        guard let ms else { return .gray }
        if ms < degradedThresholdMS { return .green }
        if ms < downThresholdMS { return .yellow }
        return .red
    }

    static func ringProgress(forLatency ms: Double?) -> Double {
        guard let ms, ms > 0 else { return 0 }
        return min(ms / downThresholdMS, 1)
    }

    static func latencyText(for health: WidgetSnapshotData.HostHealth?) -> String {
        if let latency = health?.latencyMilliseconds {
            return "\(Int(latency.rounded()))ms"
        }
        return health?.failureReason ?? "No sample"
    }
}

struct WidgetHealthRing<Center: View>: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 9
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
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

struct WidgetHostKey: View {
    let presentation: WidgetMultiHostGraphPresentation
    let healthByHostID: [UUID: WidgetSnapshotData.HostHealth]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(presentation.legend, id: \.hostID) { entry in
                let health = healthByHostID[entry.hostID]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill((entry.displayColor ?? .automatic(for: entry.hostID)).swiftUIColor)
                            .frame(width: 7, height: 7)

                        Text(entry.displayName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .truncationMode(.tail)
                    }

                    Text(WidgetStatusStyle.latencyText(for: health))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WidgetMultiHostLatencyGraph: View {
    let presentation: WidgetMultiHostGraphPresentation

    var body: some View {
        ZStack {
            Canvas { context, size in
                let baselineY = size.height * 0.72
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: baselineY))
                baseline.addLine(to: CGPoint(x: size.width, y: baselineY))
                context.stroke(baseline, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }

            ForEach(presentation.series, id: \.hostID) { series in
                Canvas { context, size in
                    guard series.pathPoints.count > 1,
                          let timeWindow = presentation.timeWindow,
                          let latencyScale = presentation.latencyScale else {
                        return
                    }
                    let timeSpan = max(timeWindow.end.timeIntervalSince(timeWindow.start), 1)
                    let latencySpan = max(
                        latencyScale.maximumMilliseconds - latencyScale.minimumMilliseconds,
                        1
                    )
                    let points = series.pathPoints.map { sample in
                        let elapsed = sample.timestamp.timeIntervalSince(timeWindow.start)
                        let x = size.width * CGFloat(elapsed / timeSpan)
                        let latency = sample.latencyMilliseconds ?? latencyScale.minimumMilliseconds
                        let normalized = (latency - latencyScale.minimumMilliseconds) / latencySpan
                        let y = size.height - (size.height * CGFloat(normalized))
                        return CGPoint(x: x, y: min(max(y, 1), size.height - 1))
                    }
                    let path = Path(ExtensionLatencyCurve.smoothedPath(points: points, closed: false))
                    let color = (series.displayColor ?? .automatic(for: series.hostID)).swiftUIColor
                    context.stroke(path, with: .color(color), lineWidth: 1.6)
                }
            }
        }
    }
}

private extension WidgetGraphDisplayColor {
    var swiftUIColor: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let components = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: components.red,
                green: components.green,
                blue: components.blue,
                alpha: 1
            )
        })
        #elseif os(iOS)
        Color(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.red,
                green: components.green,
                blue: components.blue,
                alpha: 1
            )
        })
        #else
        Color(red: light.red, green: light.green, blue: light.blue)
        #endif
    }
}

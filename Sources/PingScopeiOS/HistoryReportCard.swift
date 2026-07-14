import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

#if os(iOS)
public struct HistoryReportCard: View {
    public let presentation: HistoryReportPresentation

    public init(presentation: HistoryReportPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.brand)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.blue)
                    Text("NETWORK HISTORY REPORT")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(presentation.hostName)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Text(presentation.rangeLabel)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if presentation.sampleCount == 0 {
                Text("No History samples in this selected window")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AVERAGE")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(latency(presentation.averageMilliseconds) ?? "No successful samples")
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    Text("\(presentation.sampleCount) samples")
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.secondary)
                }

                reportSparkline
                    .frame(height: 190)

                HStack(spacing: 12) {
                    optionalMetric("MIN", value: latency(presentation.minimumMilliseconds))
                    optionalMetric("P95", value: latency(presentation.p95Milliseconds))
                    optionalMetric("MAX", value: latency(presentation.maximumMilliseconds))
                    optionalMetric("LOSS", value: percentage(presentation.lossPercent))
                    optionalMetric("UPTIME", value: percentage(presentation.uptimePercent))
                }
            }
        }
        .padding(44)
        .foregroundStyle(Color.primary)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
    }

    private var reportSparkline: some View {
        Canvas { context, size in
            let presentation = presentation.graphPresentation
            let dates = presentation.averageLineSegments.flatMap { $0 }.map(\.timestamp)
            guard let start = dates.min(), let end = dates.max() else {
                drawFailureBaseline(context: &context, size: size)
                return
            }
            let span = max(end.timeIntervalSince(start), 1)
            let maximum = max(presentation.scale.axisMaximumMilliseconds, 1)
            for segment in presentation.averageLineSegments {
                let points = segment.map { point in
                    CGPoint(
                        x: size.width * point.timestamp.timeIntervalSince(start) / span,
                        y: size.height * (1 - point.latencyMilliseconds / maximum)
                    )
                }
                if points.count > 1 {
                    context.stroke(
                        Path(LatencyCurve.smoothedPath(points: points, closed: false)),
                        with: .linearGradient(
                            Gradient(colors: [.blue, .cyan]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                } else if let point = points.first {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(.blue))
                }
            }
        }
        .padding(18)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityHidden(true)
    }

    private func drawFailureBaseline(context: inout GraphicsContext, size: CGSize) {
        guard !presentation.graphPresentation.failureMarkers.isEmpty else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(path, with: .color(.red), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
    }

    @ViewBuilder
    private func optionalMetric(_ label: String, value: String?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private func latency(_ value: Double?) -> String? {
        value.map { "\(Int($0.rounded())) ms" }
    }

    private func percentage(_ value: Double?) -> String? {
        guard let value else { return nil }
        let rounded = value.rounded()
        return abs(value - rounded) < 0.05 ? "\(Int(rounded))%" : String(format: "%.1f%%", value)
    }
}
#endif

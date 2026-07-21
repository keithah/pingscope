import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

struct AllHostStatusRow: View {
    let summary: HostStatusSummary
    let graphSeries: HostLatencyGraphSeries?

    var body: some View {
        let graphData = LatencyGraphData(samples: graphSeries?.samples ?? [])
        return HStack(spacing: 10) {
            Circle()
                .fill(identityColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(summary.endpoint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            LatencySparkline(graphData: graphData, color: sparklineColor)
                .frame(width: 58, height: 20)
                .opacity(graphData.hasLatencyData ? 1 : 0.18)
            VStack(alignment: .trailing, spacing: 1) {
                Text(summary.latencyText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(identityColor)
                    .lineLimit(1)
            }
            .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.accessibilityLabel)
        .help(summary.accessibilityLabel)
    }

    private var sparklineColor: Color {
        identityColor
    }

    private var identityColor: Color {
        graphSeries?.color
            ?? ResolvedHostDisplayColor(hostID: summary.id, displayColor: nil).swiftUIColor
    }
}

struct StarlinkTelemetrySummary: View {
    let presentation: StarlinkTelemetryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starlink")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: 8) {
                item("State", presentation.state)
                item("Drop", presentation.dropRate)
                item("Obstructed", presentation.obstruction)
                item("Down", presentation.downlinkThroughput)
                item("Up", presentation.uplinkThroughput)
                item("Uptime", presentation.uptime)
            }
            if let alerts = presentation.alerts {
                Text(alerts)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
        }
    }
}

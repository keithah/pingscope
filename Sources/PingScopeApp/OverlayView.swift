import PingScopeCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayPresentationViewModel
    @ObservedObject var liveDisplay: LiveDisplayModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let presentation = viewModel.presentation
        Group {
            switch presentation.displayMode.resolvedForHostScope(showsAllHosts: presentation.showsAllHosts) {
            case .signal:
                presentation.compactMode ? AnyView(signalCompact) : AnyView(signalExpanded)
            case .ring:
                presentation.compactMode ? AnyView(ringCompact) : AnyView(ringExpanded)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(presentation.compactMode ? "Expanded Overlay" : "Compact Overlay") {
                AppDelegate.shared?.toggleOverlayCompactMode()
            }
            if presentation.hostOptions.count > 1 {
                Button(presentation.showsAllHosts ? "Show Primary Host" : "Show All Hosts") {
                    viewModel.toggleAllHosts()
                }
                Button(presentation.showsLegend ? "Hide Legend" : "Show Legend") {
                    viewModel.toggleLegend()
                }
                .disabled(!presentation.showsAllHosts)
            }
            Button("Open Popover") {
                viewModel.openDetails()
            }
            Button("Settings...") {
                AppDelegate.shared?.openSettings()
            }
            Divider()
            Button("Close Overlay") {
                AppDelegate.shared?.hideOverlay()
            }
        }
    }

    private var signalExpanded: some View {
        let presentation = viewModel.presentation
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                PingScopeStatusPill(status: overlayStatus)
                overlayHostSelector
                Spacer()
            }
            .frame(height: 28, alignment: .center)
            .padding(.trailing, 68)
            overlayGraph
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.openDetails()
                }
            HStack {
                Text(presentation.displayPresentation.primaryStats.averageMilliseconds.map { "avg \(Int($0.rounded()))ms" } ?? "avg --")
                Spacer()
                Text("loss \(Int(presentation.displayPresentation.primaryStats.lossPercent.rounded()))%")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 10, trailing: 12))
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 106, maxHeight: .infinity)
    }

    private var signalCompact: some View {
        compactOverlayGraph
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 150, maxWidth: .infinity, minHeight: 54, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.openDetails()
            }
    }

    private var ringCompact: some View {
        let presentation = viewModel.presentation
        return HStack(spacing: 10) {
            PulseHealthRing(progress: ringProgress, color: Color(statusColor: presentation.menuBarState.color), lineWidth: 6)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(latencyNumberText)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(statusColor: presentation.menuBarState.color))
                    Text("ms")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(presentation.showsAllHosts ? "All Hosts" : presentation.primaryHostName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 178, maxWidth: .infinity, minHeight: 76, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openDetails()
        }
    }

    private var ringExpanded: some View {
        let presentation = viewModel.presentation
        return HStack(spacing: 12) {
            PulseHealthRing(progress: ringProgress, color: Color(statusColor: presentation.menuBarState.color), lineWidth: 8)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(latencyNumberText)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(statusColor: presentation.menuBarState.color))
                    if presentation.menuBarState.text.hasSuffix("ms") {
                        Text("ms")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(presentation.showsAllHosts ? "All Hosts" : presentation.primaryHostName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text("avg \(presentation.displayPresentation.primaryStats.averageMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "--")")
                    Text("loss \(Int(presentation.displayPresentation.primaryStats.lossPercent.rounded()))%")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 240, maxWidth: .infinity, minHeight: 96, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.openDetails()
        }
    }

    @ViewBuilder
    private var overlayGraph: some View {
        let presentation = viewModel.presentation
        if presentation.showsAllHosts {
            MultiHostLatencyGraph(
                series: presentation.displayPresentation.allHostGraphSeries,
                graphData: presentation.displayPresentation.allHostsGraphData,
                showsLegend: presentation.showsLegend
            )
        } else {
            LatencyGraph(graphData: presentation.displayPresentation.primaryGraphData)
        }
    }

    @ViewBuilder
    private var compactOverlayGraph: some View {
        let presentation = viewModel.presentation
        if presentation.showsAllHosts {
            MultiHostLatencyGraph(
                series: presentation.displayPresentation.allHostGraphSeries,
                graphData: presentation.displayPresentation.allHostsGraphData,
                showsLegend: false
            )
        } else {
            LatencyGraph(graphData: presentation.displayPresentation.primaryGraphData)
        }
    }

    @ViewBuilder
    private var overlayHostSelector: some View {
        let presentation = viewModel.presentation
        if presentation.hostOptions.count > 1 {
            Menu {
                Button("All Hosts") {
                    viewModel.selectAllHosts()
                }
                Divider()
                ForEach(presentation.hostOptions) { host in
                    Button(host.name) {
                        viewModel.selectHost(host.id)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(presentation.showsAllHosts ? "All Hosts" : presentation.primaryHostName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(presentation.primaryHostName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var latencyNumberText: String {
        let text = viewModel.presentation.menuBarState.text
        if text.hasSuffix("ms") {
            return String(text.dropLast(2))
        }
        return text
    }

    private var ringProgress: Double {
        let presentation = viewModel.presentation
        guard let latest = presentation.displayPresentation.visibleSamples.last?.latency?.milliseconds else {
            return 0
        }
        let threshold = max(presentation.primaryDegradedThresholdMilliseconds, 1)
        return min(max(latest / threshold, 0), 1)
    }

    private var overlayStatus: HealthStatus {
        switch viewModel.presentation.menuBarState.color {
        case .green: .healthy
        case .yellow: .degraded
        case .red: .down
        case .gray: .noData
        }
    }
}

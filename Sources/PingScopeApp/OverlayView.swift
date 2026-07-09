import PingScopeCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayPresentationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let presentation = viewModel.presentation
        Group {
            if presentation.compactMode {
                ringCompact
            } else {
                VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 7) {
                    Text(presentation.menuBarState.text)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(statusColor: presentation.menuBarState.color))
                        .lineLimit(1)
                        .fixedSize()
                    overlayHostSelector
                    Spacer()
                }
                .frame(height: 20, alignment: .center)
                .padding(.trailing, 68)
                    overlayGraph
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.openDetails()
                        }
                }
                .padding(EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
                .frame(minWidth: 190, minHeight: 78)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button(presentation.compactMode ? "Expanded Graph" : "Ring Compact") {
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
        .frame(width: 178, height: 76)
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
}

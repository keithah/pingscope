import PingScopeCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayPresentationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: presentation.compactMode ? 0 : 6) {
            if !presentation.compactMode {
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
            }
            overlayGraph
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.openDetails()
                }
        }
        .padding(presentation.compactMode ? EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6) : EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(minWidth: presentation.compactMode ? 150 : 190, minHeight: presentation.compactMode ? 48 : 78)
        .contextMenu {
            Button(presentation.compactMode ? "Exit Compact Graph" : "Compact Graph") {
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
}

import AppKit
import PingScopeCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var model: PingScopeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: model.overlayCompactMode ? 0 : 6) {
            if !model.overlayCompactMode {
                HStack(alignment: .center, spacing: 7) {
                    Text(model.menuBarState.text)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(statusColor: model.menuBarState.color))
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
                    model.openOverlayDetails()
                }
        }
        .padding(model.overlayCompactMode ? EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6) : EdgeInsets(top: 4, leading: 12, bottom: 12, trailing: 12))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .frame(minWidth: model.overlayCompactMode ? 150 : 190, minHeight: model.overlayCompactMode ? 48 : 78)
        .contextMenu {
            Button(model.overlayCompactMode ? "Exit Compact Graph" : "Compact Graph") {
                AppDelegate.shared?.toggleOverlayCompactMode()
            }
            if model.snapshot.hosts.count > 1 {
                Button(model.overlayShowsAllHosts ? "Show Primary Host" : "Show All Hosts") {
                    model.overlayShowsAllHosts.toggle()
                }
                Button(model.overlayShowsLegend ? "Hide Legend" : "Show Legend") {
                    model.overlayShowsLegend.toggle()
                }
                .disabled(!model.overlayShowsAllHosts)
            }
            Button("Open Popover") {
                model.openOverlayDetails()
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
        if model.overlayShowsAllHosts {
            MultiHostLatencyGraph(series: model.allHostGraphSeries, showsLegend: model.overlayShowsLegend)
        } else {
            LatencyGraph(samples: model.visibleSamples)
        }
    }

    @ViewBuilder
    private var overlayHostSelector: some View {
        if model.snapshot.hosts.count > 1 {
            Menu {
                Button("All Hosts") {
                    model.overlayShowsAllHosts = true
                }
                Divider()
                ForEach(model.snapshot.hosts) { host in
                    Button(host.displayName) {
                        model.overlayShowsAllHosts = false
                        model.selectHost(host.id)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.overlayShowsAllHosts ? "All Hosts" : (model.primaryHost?.displayName ?? "No Host"))
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
            Text(model.primaryHost?.displayName ?? "No Host")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

import PingScopeCore
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var viewModel: StatusPopoverPresentationViewModel
    var onSettings: () -> Void = {}
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var isShareOptionsPresented = false
    @State private var shareOptions = PingScopeShareGraphOptions()

    var body: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Graph range")
                    .font(.headline)
                Picker("Graph range", selection: Binding(
                    get: { presentation.selectedRange },
                    set: { viewModel.setSelectedRange($0) }
                )) {
                    ForEach(TimeRange.displayCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Graph range")
            }

            graph
                .frame(
                    minHeight: MenuBarPresentationMode.statusGraphMinimumHeight,
                    idealHeight: MenuBarPresentationMode.statusGraphMinimumHeight,
                    maxHeight: .infinity
                )
                .layoutPriority(1)

            stats
            if let telemetry = presentation.displayPresentation.latestStarlinkTelemetry {
                StarlinkTelemetrySummary(telemetry: telemetry)
            }
            if let degradationReason {
                CompactDiagnosisReasonRow(diagnosis: degradationReason)
            }

            RecentSamplesView(samples: presentation.displayPresentation.recentVisibleSamples, range: presentation.selectedRange)
        }
        .padding(16)
        .frame(
            minWidth: MenuBarPresentationMode.statusContentMinimumSize.width,
            idealWidth: MenuBarPresentationMode.statusContentSize.width,
            maxWidth: MenuBarPresentationMode.statusContentSize.width,
            minHeight: MenuBarPresentationMode.statusContentMinimumSize.height,
            idealHeight: MenuBarPresentationMode.statusContentSize.height,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .popover(isPresented: $isShareOptionsPresented, arrowEdge: .top) {
            ShareGraphOptionsPopover(
                options: $shareOptions,
                hasMultipleHosts: presentation.snapshot.hosts.count > 1,
                onShare: {
                    isShareOptionsPresented = false
                    viewModel.shareGraph(options: shareOptions)
                },
                onCancel: {
                    isShareOptionsPresented = false
                }
            )
        }
    }

    private var header: some View {
        let presentation = viewModel.presentation
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if presentation.snapshot.hosts.count > 1 {
                        Picker("Host", selection: Binding(
                            get: { presentation.popoverShowsAllHosts ? Self.allHostsSelectionID : (presentation.primaryHost?.id.uuidString ?? presentation.snapshot.hosts.first?.id.uuidString ?? "") },
                            set: { selection in
                                if selection == Self.allHostsSelectionID {
                                    viewModel.selectAllHosts()
                                } else if let id = UUID(uuidString: selection) {
                                    viewModel.selectHost(id)
                                }
                            }
                        )) {
                            Text("All Hosts").tag(Self.allHostsSelectionID)
                            Divider()
                            ForEach(presentation.snapshot.hosts) { host in
                                Text(host.displayName).tag(host.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.headline)
                        .fixedSize()
                        .accessibilityHint(monitoredHostsAccessibilitySummary)
                    } else {
                        Text(presentation.primaryHost?.displayName ?? "No Host")
                            .font(.headline)
                    }
                    Text(hostSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(presentation.selectedRangeState.text)
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                        Label(presentation.selectedRangeStatusLabel, systemImage: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color(statusColor: presentation.selectedRangeState.color))
                    }
                    .padding(.trailing, 10)
                    Button {
                        shareOptions = viewModel.defaultShareOptions()
                        isShareOptionsPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .frame(
                                width: MenuBarPresentationMode.statusCompactControlHitSize,
                                height: MenuBarPresentationMode.statusCompactControlHitSize
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Share graph")
                    .accessibilityLabel("Share graph")
                    Button {
                        onSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .medium))
                            .frame(
                                width: MenuBarPresentationMode.statusCompactControlHitSize,
                                height: MenuBarPresentationMode.statusCompactControlHitSize
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Open settings")
                    .accessibilityLabel("Open settings")
                }
            }
            pingIntervalControl
        }
    }

    private static let allHostsSelectionID = "__all_hosts__"

    private var hostSubtitle: String {
        let presentation = viewModel.presentation
        if presentation.popoverShowsAllHosts {
            let enabledCount = presentation.snapshot.hosts.reduce(0) { count, host in
                count + (host.isEnabled ? 1 : 0)
            }
            return "\(enabledCount) enabled hosts"
        }
        return "\(presentation.primaryHost?.method.displayName ?? "TCP") \(presentation.primaryHost?.address ?? "")"
    }

    private var monitoredHostsAccessibilitySummary: String {
        let presentation = viewModel.presentation
        guard presentation.displayPresentation.hostStatusSummaries.count > 1 else {
            return hostSubtitle
        }
        return presentation.displayPresentation.hostStatusSummaries
            .map(\.accessibilityLabel)
            .joined(separator: ". ")
    }

    @ViewBuilder
    private var pingIntervalControl: some View {
        let presentation = viewModel.presentation
        if !presentation.popoverShowsAllHosts, let host = presentation.primaryHost {
            let selectedMilliseconds = PingIntervalPresentation.selection(for: host.interval)
            HStack(spacing: 8) {
                Text("Ping interval")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Ping interval", selection: Binding(
                    get: { selectedMilliseconds },
                    set: { milliseconds in viewModel.setPingInterval(milliseconds, for: host.id) }
                )) {
                    ForEach(PingIntervalPresentation.options(including: selectedMilliseconds)) { option in
                        Text(option.label).tag(option.milliseconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Ping interval")
                .help("Change how often PingScope checks this host")
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var graph: some View {
        let presentation = viewModel.presentation
        if presentation.popoverShowsAllHosts {
            MultiHostLatencyGraph(
                series: presentation.displayPresentation.allHostGraphSeries,
                graphData: presentation.displayPresentation.allHostsGraphData,
                showsAxes: true
            )
        } else {
            LatencyGraph(graphData: presentation.displayPresentation.primaryGraphData, showsAxes: true)
        }
    }

    private var stats: some View {
        let stats = viewModel.presentation.displayPresentation.primaryStats
        return HStack(alignment: .top, spacing: 16) {
            stat("TX", "\(stats.transmitted)")
            stat("RX", "\(stats.received)")
            stat("Loss", "\(Int(stats.lossPercent.rounded()))%")
            stat("Min", latency(stats.minimumMilliseconds))
            stat("Avg", latency(stats.averageMilliseconds))
            stat("Max", latency(stats.maximumMilliseconds))
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced))
        }
    }

    private func latency(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))ms"
    }

    private struct ShareGraphOptionsPopover: View {
        @Binding var options: PingScopeShareGraphOptions
        let hasMultipleHosts: Bool
        let onShare: () -> Void
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Share Graph")
                    .font(.headline)

                Picker("Hosts", selection: $options.scope) {
                    Text(PingScopeShareGraphScope.currentView.displayName).tag(PingScopeShareGraphScope.currentView)
                    Text(PingScopeShareGraphScope.singleHost.displayName).tag(PingScopeShareGraphScope.singleHost)
                    if hasMultipleHosts {
                        Text(PingScopeShareGraphScope.allHosts.displayName).tag(PingScopeShareGraphScope.allHosts)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Range", selection: $options.range) {
                    ForEach(TimeRange.displayCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Include sample table", isOn: $options.includesTable)

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Share", action: onShare)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(width: 340)
        }
    }

    private var allHostStatusSummary: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.presentation.displayPresentation.hostStatusSummaries, id: \.id) { summary in
                AllHostStatusRow(summary: summary)
            }
        }
    }

    private var degradationReason: NetworkPerspectiveDiagnosis? {
        let diagnosis = viewModel.presentation.networkDiagnosis
        switch diagnosis.scope {
        case .localNetwork, .upstream, .remoteService, .partialDegradation:
            return diagnosis
        case .noData, .allReachable:
            return nil
        }
    }
}

private struct AllHostStatusRow: View {
    let summary: HostStatusSummary

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color(statusColor: summary.color))
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
            VStack(alignment: .trailing, spacing: 1) {
                Text(summary.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(statusColor: summary.color))
                    .lineLimit(1)
                Text(summary.latencyText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.accessibilityLabel)
        .help(summary.accessibilityLabel)
    }
}

private struct CompactDiagnosisReasonRow: View {
    let diagnosis: NetworkPerspectiveDiagnosis

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnosis.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(reasonText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }

    private var reasonText: String {
        if let evidenceNote = diagnosis.evidenceNote, !evidenceNote.isEmpty {
            "\(diagnosis.detail) \(evidenceNote)."
        } else {
            diagnosis.detail
        }
    }

    private var accessibilityText: String {
        var parts = [diagnosis.title, diagnosis.detail]
        if let evidenceNote = diagnosis.evidenceNote {
            parts.append(evidenceNote)
        }
        if diagnosis.confidence == .tentative {
            parts.append(diagnosis.confidence.displayName)
        }
        return parts.joined(separator: ". ")
    }

    private var iconName: String {
        switch diagnosis.scope {
        case .localNetwork:
            "network.slash"
        case .upstream:
            "wifi.exclamationmark"
        case .remoteService:
            "exclamationmark.triangle.fill"
        case .partialDegradation:
            "speedometer"
        case .noData:
            "circle"
        case .allReachable:
            "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch diagnosis.scope {
        case .localNetwork:
            .red
        case .upstream:
            .orange
        case .remoteService, .partialDegradation:
            .yellow
        case .noData:
            .secondary
        case .allReachable:
            .green
        }
    }
}

private struct StarlinkTelemetrySummary: View {
    let telemetry: StarlinkTelemetry

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
                item("State", telemetry.state ?? "--")
                item("Drop", percent(telemetry.popPingDropRate))
                item("Obstructed", percent(telemetry.fractionObstructed))
                item("Down", throughput(telemetry.downlinkThroughputBps))
                item("Up", throughput(telemetry.uplinkThroughputBps))
                item("Uptime", uptime(telemetry.uptimeSeconds))
            }
            if !telemetry.activeAlerts.isEmpty {
                Text(telemetry.activeAlerts.joined(separator: ", "))
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

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func throughput(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value / 1_000_000).rounded())) Mbps"
    }

    private func uptime(_ value: Double?) -> String {
        guard let value else { return "--" }
        let hours = Int(value / 3_600)
        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h"
    }
}

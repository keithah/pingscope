import PingScopeCore
import SwiftUI

struct StatusPopoverView: View {
    private enum DisplayMode {
        case pulse
        case ring
    }

    @ObservedObject var viewModel: StatusPopoverPresentationViewModel
    var onSettings: () -> Void = {}
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var isShareOptionsPresented = false
    @State private var shareOptions = PingScopeShareGraphOptions()
    @State private var displayMode: DisplayMode = .pulse

    var body: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: 13) {
            header

            pulseDisplay

            sparkline
                .frame(height: 58)

            rangePicker

            if presentation.popoverShowsAllHosts {
                allHostStatusSummary
            }
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
            minHeight: 430,
            idealHeight: 500,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(Color(hex: "#1c1c1e"))
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
        HStack(alignment: .center, spacing: 10) {
            hostChip
                .accessibilityHint(monitoredHostsAccessibilitySummary)
            Spacer()
            Button {
                shareOptions = viewModel.defaultShareOptions()
                isShareOptionsPresented = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "#2c2c2e"), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Share graph")
            .accessibilityLabel("Share graph")
            settingsMenu
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

    private var hostChip: some View {
        let presentation = viewModel.presentation
        return Menu {
            if presentation.snapshot.hosts.count > 1 {
                Button("All Hosts") {
                    viewModel.selectAllHosts()
                }
                Divider()
            }
            ForEach(presentation.snapshot.hosts) { host in
                Button(host.displayName) {
                    viewModel.selectHost(host.id)
                }
            }
        } label: {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.popoverShowsAllHosts ? "All Hosts" : (presentation.primaryHost?.displayName ?? "No Host"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(hostSubtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "#2c2c2e"), in: Capsule())
        }
        .buttonStyle(.plain)
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
    private var settingsMenu: some View {
        let presentation = viewModel.presentation
        Menu {
            if !presentation.popoverShowsAllHosts, let host = presentation.primaryHost {
                let selectedMilliseconds = PingIntervalPresentation.selection(for: host.interval)
                Picker("Ping interval", selection: Binding(
                    get: { selectedMilliseconds },
                    set: { milliseconds in viewModel.setPingInterval(milliseconds, for: host.id) }
                )) {
                    ForEach(PingIntervalPresentation.options(including: selectedMilliseconds)) { option in
                        Text(option.label).tag(option.milliseconds)
                    }
                }
                Divider()
            }
            Button("Open Settings", action: onSettings)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#2c2c2e"), in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private var pulseDisplay: some View {
        let presentation = viewModel.presentation
        switch displayMode {
        case .pulse:
            HStack(alignment: .center, spacing: 18) {
                PulseHealthRing(progress: ringProgress, color: ringColor, lineWidth: 13)
                    .frame(width: 150, height: 150)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(latencyNumberText)
                                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                                .minimumScaleFactor(0.7)
                            Text(presentation.selectedRangeStatusLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(ringColor)
                                .lineLimit(1)
                        }
                    }

                VStack(alignment: .leading, spacing: 13) {
                    Text(hostSubtitle.replacingOccurrences(of: " ", with: " · ", options: [], range: hostSubtitle.range(of: " ")))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    statRow(["Min", "Avg", "Max"], [
                        latency(presentation.displayPresentation.primaryStats.minimumMilliseconds),
                        latency(presentation.displayPresentation.primaryStats.averageMilliseconds),
                        latency(presentation.displayPresentation.primaryStats.maximumMilliseconds)
                    ])
                    statRow(["Loss"], ["\(Int(presentation.displayPresentation.primaryStats.lossPercent.rounded()))%"])
                    statRow(["TX", "RX"], [
                        "\(presentation.displayPresentation.primaryStats.transmitted)",
                        "\(presentation.displayPresentation.primaryStats.received)"
                    ])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .ring:
            EmptyView()
        }
    }

    private var sparkline: some View {
        VStack(spacing: 4) {
            LatencySparkline(graphData: viewModel.presentation.displayPresentation.primaryGraphData, color: ringColor)
            HStack {
                Text(viewModel.presentation.selectedRange.rawValue)
                Spacer()
                Text("now")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private var rangePicker: some View {
        Picker("Graph range", selection: Binding(
            get: { viewModel.presentation.selectedRange },
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

    private func statRow(_ labels: [String], _ values: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Text(values[index])
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
    }

    private var ringColor: Color {
        Color(statusColor: viewModel.presentation.selectedRangeState.color)
    }

    private var latencyNumberText: String {
        viewModel.presentation.selectedRangeState.text.replacingOccurrences(of: "ms", with: "")
    }

    private var ringProgress: Double {
        guard let threshold = viewModel.presentation.primaryHost?.thresholds.degradedMilliseconds,
              threshold > 0,
              let latency = viewModel.presentation.displayPresentation.visibleSamples.last?.latency?.milliseconds else {
            return 0
        }
        return min(max(latency / threshold, 0), 1)
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

                Picker("Appearance", selection: $options.appearance) {
                    ForEach(PingScopeShareGraphAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
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

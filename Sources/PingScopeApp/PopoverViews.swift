import AppKit
import PingScopeCore
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var model: PingScopeModel
    var onSettings: () -> Void = {}
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 12) {
                Picker("Range", selection: $model.selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            graph
                .frame(height: 150)

            stats
            if let telemetry = latestStarlinkTelemetry {
                StarlinkTelemetrySummary(telemetry: telemetry)
            }
            if let degradationReason {
                CompactDiagnosisReasonRow(diagnosis: degradationReason)
            }

            RecentSamplesView(samples: Array(model.visibleSamples.suffix(8)).reversed(), range: model.selectedRange)
        }
        .padding(16)
        .frame(width: 430, height: 540, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if model.snapshot.hosts.count > 1 {
                    Picker("Host", selection: Binding(
                        get: { model.popoverShowsAllHosts ? Self.allHostsSelectionID : (model.primaryHost?.id.uuidString ?? model.snapshot.hosts.first?.id.uuidString ?? "") },
                        set: { selection in
                            if selection == Self.allHostsSelectionID {
                                model.popoverShowsAllHosts = true
                            } else if let id = UUID(uuidString: selection) {
                                model.popoverShowsAllHosts = false
                                model.selectHost(id)
                            }
                        }
                    )) {
                        Text("All Hosts").tag(Self.allHostsSelectionID)
                        Divider()
                        ForEach(model.snapshot.hosts) { host in
                            Text(host.displayName).tag(host.id.uuidString)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.headline)
                    .fixedSize()
                } else {
                    Text(model.primaryHost?.displayName ?? "No Host")
                        .font(.headline)
                }
                Text(hostSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.selectedRangeState.text)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    Label(model.selectedRangeStatusLabel, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(statusColor: model.selectedRangeState.color))
                }
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open settings")
                .accessibilityLabel("Open settings")
            }
        }
    }

    private static let allHostsSelectionID = "__all_hosts__"

    private var hostSubtitle: String {
        if model.popoverShowsAllHosts {
            return "\(model.snapshot.hosts.filter(\.isEnabled).count) enabled hosts"
        }
        return "\(model.primaryHost?.method.displayName ?? "TCP") \(model.primaryHost?.address ?? "")"
    }

    @ViewBuilder
    private var graph: some View {
        if model.popoverShowsAllHosts {
            MultiHostLatencyGraph(series: multiHostGraphSeries, showsAxes: true)
        } else {
            LatencyGraph(samples: model.visibleSamples, showsAxes: true)
        }
    }

    private var multiHostGraphSeries: [HostLatencyGraphSeries] {
        let cutoff = Date().addingTimeInterval(-model.selectedRange.duration)
        return model.snapshot.hosts.enumerated().compactMap { index, host in
            guard host.isEnabled else { return nil }
            let samples = model.snapshot.samplesByHost[host.id]?.samples(since: cutoff) ?? []
            return HostLatencyGraphSeries(
                host: host,
                samples: samples,
                color: HostLatencyGraphSeries.palette[index % HostLatencyGraphSeries.palette.count],
                isPrimary: host.id == model.primaryHost?.id
            )
        }
    }

    private var stats: some View {
        let stats = model.primaryStats
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                stat("TX", "\(stats.transmitted)")
                stat("RX", "\(stats.received)")
                stat("Loss", "\(Int(stats.lossPercent.rounded()))%")
            }
            GridRow {
                stat("Min", latency(stats.minimumMilliseconds))
                stat("Avg", latency(stats.averageMilliseconds))
                stat("Max", latency(stats.maximumMilliseconds))
            }
        }
        .font(.caption)
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

    private var latestStarlinkTelemetry: StarlinkTelemetry? {
        guard !model.popoverShowsAllHosts,
              model.primaryHost?.method == .starlink else {
            return nil
        }
        return model.visibleSamples.reversed().compactMap(\.metadata.starlink).first
    }

    private var degradationReason: NetworkPerspectiveDiagnosis? {
        let diagnosis = model.networkDiagnosis
        switch diagnosis.scope {
        case .localNetwork, .upstream, .remoteService, .partialDegradation:
            return diagnosis
        case .noData, .allReachable:
            return nil
        }
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


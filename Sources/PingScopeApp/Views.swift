import AppKit
import PingScopeCore
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var model: PingScopeModel
    var onSettings: () -> Void = {}
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var graphMode: PopoverGraphMode = .primary

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
            NetworkDiagnosisRow(diagnosis: model.networkDiagnosis)

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
                        get: { graphMode == .all ? Self.allHostsSelectionID : (model.primaryHost?.id.uuidString ?? model.snapshot.hosts.first?.id.uuidString ?? "") },
                        set: { selection in
                            if selection == Self.allHostsSelectionID {
                                graphMode = .all
                            } else if let id = UUID(uuidString: selection) {
                                graphMode = .primary
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
        if graphMode == .all {
            return "\(model.snapshot.hosts.filter(\.isEnabled).count) enabled hosts"
        }
        return "\(model.primaryHost?.method.displayName ?? "TCP") \(model.primaryHost?.address ?? "")"
    }

    @ViewBuilder
    private var graph: some View {
        switch graphMode {
        case .primary:
            LatencyGraph(samples: model.visibleSamples, showsAxes: true)
        case .all:
            MultiHostLatencyGraph(series: multiHostGraphSeries, showsAxes: true)
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
        guard graphMode == .primary,
              model.primaryHost?.method == .starlink else {
            return nil
        }
        return model.visibleSamples.reversed().compactMap(\.metadata.starlink).first
    }
}

private enum PopoverGraphMode: String, CaseIterable, Identifiable {
    case primary
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: "Primary"
        case .all: "All"
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

struct NetworkDiagnosisRow: View {
    let diagnosis: NetworkPerspectiveDiagnosis

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(diagnosis.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if diagnosis.confidence == .tentative {
                        Text("Tentative")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(diagnosis.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let evidenceNote = diagnosis.evidenceNote {
                    Text(evidenceNote)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.82))
                        .lineLimit(1)
                }
                if !diagnosis.tierEvidence.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(diagnosis.tierEvidence, id: \.tier) { evidence in
                            NetworkTierEvidenceChip(evidence: evidence, isFault: diagnosis.faultTier == evidence.tier)
                        }
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(chainAccessibilityText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch diagnosis.scope {
        case .noData: "circle"
        case .allReachable: "checkmark.circle.fill"
        case .localNetwork: "network.slash"
        case .upstream: "wifi.exclamationmark"
        case .remoteService: "exclamationmark.triangle.fill"
        case .partialDegradation: "speedometer"
        }
    }

    private var tint: Color {
        switch diagnosis.scope {
        case .noData: .secondary
        case .allReachable: .green
        case .localNetwork: .red
        case .upstream: .orange
        case .remoteService: .yellow
        case .partialDegradation: .yellow
        }
    }

    private var accessibilityText: String {
        var parts = [diagnosis.title, diagnosis.detail]
        if diagnosis.confidence == .tentative {
            parts.append(diagnosis.confidence.displayName)
        }
        if let evidenceNote = diagnosis.evidenceNote {
            parts.append(evidenceNote)
        }
        if !diagnosis.tierEvidence.isEmpty {
            parts.append(chainAccessibilityText)
        }
        return parts.joined(separator: ". ")
    }

    private var chainAccessibilityText: String {
        diagnosis.tierEvidence
            .map { "\($0.tier.shortName): \($0.summary)" }
            .joined(separator: ", ")
    }
}

private struct NetworkTierEvidenceChip: View {
    let evidence: NetworkPerspectiveDiagnosis.TierEvidence
    let isFault: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(statusColor: evidence.status.statusColor))
                .frame(width: 6, height: 6)
            Text(evidence.tier.shortName)
                .lineLimit(1)
            Text("\(evidence.healthyCount)/\(evidence.totalCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption2.weight(isFault ? .bold : .semibold))
        .foregroundStyle(isFault ? .primary : .secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(statusColor: evidence.status.statusColor).opacity(isFault ? 0.18 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(statusColor: evidence.status.statusColor).opacity(isFault ? 0.42 : 0.16), lineWidth: 1)
        )
        .help("\(evidence.tier.settingsName): \(evidence.summary)")
    }
}

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
            MultiHostLatencyGraph(series: overlayGraphSeries, showsLegend: model.overlayShowsLegend)
        } else {
            LatencyGraph(samples: model.visibleSamples)
        }
    }

    private var overlayGraphSeries: [HostLatencyGraphSeries] {
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

struct SettingsRootView: View {
    @ObservedObject var model: PingScopeModel
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var selectedSettingsTab: String

    init(model: PingScopeModel) {
        self.model = model
        _selectedSettingsTab = State(initialValue: UserDefaults.standard.string(forKey: "selectedSettingsTab") ?? "hosts")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 158)
                    .padding(.horizontal, 10)
                    .padding(.top, 24)
                    .padding(.bottom, 14)

                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    selectedSettingsHeader

                    if selectedTab == .display {
                        selectedSettingsContent
                            .padding(.bottom, 20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            selectedSettingsContent
                                .padding(.bottom, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            settingsFooter
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Color.black.opacity(0.08))
        }
        .frame(minWidth: 680, minHeight: 500)
        .onChange(of: selectedSettingsTab) { _, tab in
            UserDefaults.standard.set(tab, forKey: "selectedSettingsTab")
        }
    }

    private var selectedTab: SettingsTab {
        SettingsTab(rawValue: selectedSettingsTab) ?? .hosts
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PingScope")
                    .font(.system(size: 22, weight: .bold))
                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsSidebarButton(tab)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func settingsSidebarButton(_ tab: SettingsTab) -> some View {
        Button {
            selectedSettingsTab = tab.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 19)
                Text(tab.title)
                    .font(.system(size: 13, weight: selectedSettingsTab == tab.id ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSettingsTab == tab.id ? Color.white : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedSettingsTab == tab.id ? Color.accentColor : Color.clear)
        )
    }

    private var selectedSettingsHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: selectedTab.systemImage)
                .font(.system(size: 23, weight: .semibold))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTab.title)
                    .font(.system(size: 24, weight: .bold))
                Text(selectedTab.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSettingsTab {
        case SettingsTab.display.id:
            display
        case SettingsTab.notifications.id:
            notifications
        case SettingsTab.history.id:
            history
        case SettingsTab.diagnostics.id:
            diagnostics
        case SettingsTab.advanced.id:
            advanced
        case SettingsTab.about.id:
            about
        default:
            hosts
        }
    }

    private var settingsFooter: some View {
        HStack {
            Button("Reset to Defaults", role: .destructive) {
                model.resetToDefaults()
            }
            Spacer()
            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var hosts: some View {
        SettingsPane {
            SettingsSection("Monitored Hosts") {
                HStack(spacing: 10) {
                    Text("\(model.snapshot.hosts.count) configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.addDefaultGatewayHost()
                    } label: {
                        Label("Default Gateway", systemImage: "network")
                    }
                    .disabled(model.gatewayDetectionText == "Detecting...")
                    Button {
                        model.useStarlinkDishPreset()
                    } label: {
                        Label("Starlink", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button {
                        model.beginAddingHost()
                    } label: {
                        Label("Add Host", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                }
                .controlSize(.small)

                if let gateway = model.gatewayDetectionText {
                    Text(gateway)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    ForEach(model.snapshot.hosts) { host in
                        HostSettingsRow(
                            host: host,
                            isSelected: model.editingHostID == host.id,
                            isPrimary: host.id == model.primaryHost?.id,
                            statusColor: Color(statusColor: model.snapshot.healthByHost[host.id]?.status.statusColor ?? .gray),
                            onSelect: { model.selectHostForEditing(host.id) },
                            onMakePrimary: { model.setPrimaryHost(host.id) },
                            onDelete: {
                                model.deleteHost(host.id)
                                if model.editingHostID == host.id {
                                    model.clearDraftHost()
                                }
                            }
                        )
                    }
                }
            }

            if model.isCreatingHost || model.editingHostID != nil {
                SettingsSection(model.editingHostID == nil ? "Add Host" : "Edit Host") {
                    hostEditor
                }
            }
        }
    }

    private var hostEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    SettingsField("Name") {
                        TextField("Name", text: $model.draftHostName)
                            .frame(maxWidth: .infinity)
                    }
                    SettingsField("Address") {
                        TextField("Address", text: $model.draftHostAddress)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    SettingsField("Method") {
                        Picker("Method", selection: Binding(
                            get: { model.draftMethod },
                            set: { model.applyDraftMethod($0) }
                        )) {
                            ForEach(model.methodsForCurrentBuild, id: \.self) { method in
                                Text(method.rawValue.uppercased()).tag(method)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    SettingsField("Port") {
                        TextField("Port", value: $model.draftPort, format: .number)
                            .frame(width: 84)
                            .disabled(model.draftMethod == .icmp)
                    }
                    Toggle("Enabled", isOn: $model.draftIsEnabled)
                        .toggleStyle(.checkbox)
                        .padding(.top, 18)
                    Spacer(minLength: 0)
                }

                Button {
                    model.showsAdvancedHostFields.toggle()
                } label: {
                    Label(model.showsAdvancedHostFields ? "Hide Advanced" : "Show Advanced", systemImage: model.showsAdvancedHostFields ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if model.showsAdvancedHostFields {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsField("Notifications") {
                            Picker("Notifications", selection: $model.draftNotificationPolicy) {
                                ForEach(HostNotificationPolicy.allCases, id: \.self) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }

                        SettingsField("Network role") {
                            Picker("Network role", selection: Binding(
                                get: { model.draftNetworkTier?.rawValue ?? Self.autoNetworkTierSelection },
                                set: { selection in
                                    model.draftNetworkTier = selection == Self.autoNetworkTierSelection ? nil : NetworkTier(rawValue: selection)
                            }
                        )) {
                            Text("Auto (\(model.draftHost.effectiveNetworkTier.settingsName))").tag(Self.autoNetworkTierSelection)
                            Divider()
                            ForEach(NetworkTier.allCases, id: \.self) { tier in
                                Text(tier.settingsName).tag(tier.rawValue)
                            }
                        }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                        }

                        HStack(alignment: .top, spacing: 14) {
                            SettingsField("Interval") {
                                UnitNumberField(value: $model.draftIntervalMilliseconds, unit: "ms", width: 78)
                            }
                            SettingsField("Timeout") {
                                UnitNumberField(value: $model.draftTimeoutMilliseconds, unit: "ms", width: 78)
                            }
                            SettingsField("Degraded at") {
                                UnitNumberField(value: $model.draftDegradedThresholdMilliseconds, unit: "ms", width: 78)
                            }
                        }

                        Stepper("Down after \(model.draftDownAfterFailures) failures", value: $model.draftDownAfterFailures, in: 1...10)
                            .frame(width: 190, alignment: .leading)
                    }
                }
            }

            HStack(spacing: 10) {
                if let result = model.draftTestResultText {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Failed") ? .red : .secondary)
                }
                Spacer()
                Button {
                    model.testDraftHost()
                } label: {
                    Label("Test", systemImage: "bolt")
                }
                .disabled(!model.canAddDraftHost || model.isTestingDraftHost)
                Button {
                    model.addDraftHost()
                } label: {
                    Label(model.draftActionTitle, systemImage: model.editingHostID == nil ? "plus" : "checkmark")
                }
                .disabled(!model.canAddDraftHost)
                Button {
                    model.clearDraftHost()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
            .controlSize(.small)
        }
    }

    private static let autoNetworkTierSelection = "__auto_network_tier__"

    private var display: some View {
        SettingsPane {
            SettingsSection("Menu Bar") {
                SettingsRow(systemImage: "chart.xyaxis.line", tint: .blue, title: "Graph range") {
                    Picker("Menu bar range", selection: $model.selectedRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            SettingsSection("Overlay") {
                SettingsToggleRow(systemImage: "rectangle.on.rectangle", tint: .blue, title: "Show overlay", isOn: Binding(
                    get: { model.overlayVisible },
                    set: { isVisible in
                        DebugLog.write("settings overlay show changed visible=\(isVisible)")
                        if isVisible {
                            AppDelegate.shared?.showOverlay()
                        } else {
                            AppDelegate.shared?.hideOverlay()
                        }
                    }
                ))
                SettingsToggleRow(systemImage: "pin.fill", tint: .orange, title: "Always on top", isOn: Binding(
                    get: { model.overlayAlwaysOnTop },
                    set: {
                        DebugLog.write("settings overlay alwaysOnTop changed value=\($0)")
                        model.overlayAlwaysOnTop = $0
                        AppDelegate.shared?.applyOverlayBehavior()
                    }
                ))
                SettingsToggleRow(systemImage: "arrow.up.left.and.arrow.down.right", tint: .purple, title: "Compact graph mode", isOn: Binding(
                    get: { model.overlayCompactMode },
                    set: {
                        DebugLog.write("settings overlay compact changed value=\($0)")
                        AppDelegate.shared?.setOverlayCompactMode($0)
                    }
                ))
                SettingsRow(systemImage: "slider.horizontal.3", tint: .teal, title: "Opacity") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.overlayOpacity },
                            set: {
                                DebugLog.write("settings overlay opacity changed value=\($0)")
                                model.overlayOpacity = $0
                                AppDelegate.shared?.applyOverlayBehavior()
                            }
                        ), in: 0.55...1)
                        .frame(width: 160)
                        Text("\(Int((model.overlayOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                SettingsRow(systemImage: "aspectratio", tint: .gray, title: "Saved size") {
                    Text("\(Int(model.overlayFrame.width)) x \(Int(model.overlayFrame.height))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                SettingsRow(systemImage: "scope", tint: .gray, title: "Position") {
                    Button("Reset Overlay Position") {
                        model.resetOverlayFrame()
                        AppDelegate.shared?.resetOverlayFrame()
                    }
                }
            }
        }
    }

    private var notifications: some View {
        SettingsPane {
            SettingsSection("Global Alerts") {
                SettingsRow(systemImage: "bell.badge", tint: .red, title: "Permission") {
                    HStack(spacing: 10) {
                        Text(model.notificationPermissionState.displayName)
                            .foregroundStyle(model.notificationPermissionState == .denied ? .red : .secondary)
                        Button("Request Permission") {
                            model.requestNotificationPermission()
                        }
                        .disabled([
                            .authorized,
                            .provisional,
                            .requesting,
                            .unavailable
                        ].contains(model.notificationPermissionState))
                        Button("Send Test") {
                            model.sendTestNotification()
                        }
                        .disabled(model.notificationPermissionState == .requesting || model.notificationPermissionState == .unavailable)
                        Button("Open Settings") {
                            model.openNotificationSettings()
                        }
                    }
                }
                if let message = model.notificationRequestMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
                SettingsToggleRow(systemImage: "bell.fill", tint: .red, title: "Enable notifications", isOn: Binding(
                    get: { model.notificationRules.isEnabled },
                    set: { model.setNotificationsEnabled($0) }
                ))
                SettingsToggleRow(systemImage: "xmark.octagon.fill", tint: .red, title: "Host down", isOn: alertBinding(.hostDown))
                SettingsToggleRow(systemImage: "checkmark.circle.fill", tint: .green, title: "Recovery", isOn: Binding(
                    get: { model.notificationRules.notifyOnRecovery && model.notificationRules.alertTypes.contains(.recovered) },
                    set: {
                        model.notificationRules.notifyOnRecovery = $0
                        model.setAlertType(.recovered, enabled: $0)
                    }
                ))
                SettingsToggleRow(systemImage: "speedometer", tint: .yellow, title: "High latency", isOn: alertBinding(.highLatency))
                SettingsToggleRow(systemImage: "network", tint: .blue, title: "Network change", isOn: alertBinding(.networkChange))
                SettingsToggleRow(systemImage: "wifi.slash", tint: .orange, title: "Internet loss", isOn: alertBinding(.internetLoss))
                SettingsToggleRow(systemImage: "network.slash", tint: .red, title: "Local network down", isOn: alertBinding(.localNetworkDown))
                SettingsToggleRow(systemImage: "cable.connector.slash", tint: .orange, title: "ISP path down", isOn: alertBinding(.ispPathDown))
                SettingsToggleRow(systemImage: "wifi.exclamationmark", tint: .orange, title: "Internet path down", isOn: alertBinding(.upstreamDown))
                SettingsToggleRow(systemImage: "exclamationmark.triangle.fill", tint: .yellow, title: "Remote service down", isOn: alertBinding(.remoteServiceDown))
                SettingsToggleRow(systemImage: "waveform.path.ecg", tint: .yellow, title: "Path degraded", isOn: alertBinding(.pathDegraded))
            }

            SettingsSection("Network Status Alerts") {
                NetworkStatusBadge(status: model.currentNetworkStatus)
                ForEach(NetworkConnectivityStatus.allCases, id: \.self) { status in
                    NetworkStatusToggleRow(
                        status: status,
                        isEnabled: Binding(
                            get: { model.enabledNetworkStatusAlerts.contains(status) },
                            set: { model.setNetworkStatusAlert(status, enabled: $0) }
                        )
                    )
                }
            }

            SettingsSection("Thresholds") {
                SettingsRow(systemImage: "speedometer", tint: .yellow, title: "High latency") {
                    UnitNumberField(value: Binding(
                        get: { model.notificationRules.latencyThreshold.milliseconds },
                        set: { model.notificationRules.latencyThreshold = .milliseconds($0) }
                    ), unit: "ms", width: 82)
                }
                SettingsRow(systemImage: "timer", tint: .blue, title: "Cooldown") {
                    UnitNumberField(value: Binding(
                        get: { model.notificationRules.cooldown.seconds },
                        set: { model.notificationRules.cooldown = .seconds($0) }
                    ), unit: "sec", width: 82)
                }
            }
        }
    }

    private func alertBinding(_ type: AlertType) -> Binding<Bool> {
        Binding(
            get: { model.notificationRules.alertTypes.contains(type) },
            set: { model.setAlertType(type, enabled: $0) }
        )
    }

    private var advanced: some View {
        SettingsPane {
            SettingsSection("App") {
                SettingsRow(systemImage: "shippingbox", tint: .blue, title: "Build flavor") {
                    Text(BuildFlavor.current == .appStore ? "App Store" : "Developer ID")
                        .foregroundStyle(.secondary)
                }
                #if !APPSTORE
                    if BuildFlavor.current != .appStore {
                        SettingsRow(systemImage: "arrow.triangle.2.circlepath", tint: .blue, title: "Software updates") {
                            HStack(spacing: 10) {
                                Text(softwareUpdateController.statusMessage)
                                    .foregroundStyle(.secondary)
                                Button("Check Now") {
                                    softwareUpdateController.checkForUpdates()
                                }
                                .disabled(!softwareUpdateController.canCheckForUpdates)
                            }
                        }
                        SettingsRow(systemImage: "link", tint: .teal, title: "Update feed") {
                            Text(softwareUpdateController.feedURL ?? "Not configured")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        SettingsRow(systemImage: "key.fill", tint: .orange, title: "Sparkle key") {
                            Text(softwareUpdateController.publicKeyConfigured ? "Configured" : "Missing")
                                .foregroundStyle(softwareUpdateController.publicKeyConfigured ? Color.secondary : Color.red)
                        }
                        SettingsRow(systemImage: "clock.arrow.circlepath", tint: .purple, title: "Last check") {
                            if let date = softwareUpdateController.lastCheckRequestedAt {
                                Text(date, style: .time)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not requested this session")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                #endif
                SettingsRow(systemImage: "waveform.path.ecg", tint: .green, title: "ICMP") {
                    Text(model.methodsForCurrentBuild.contains(.icmp) ? "Available" : "Hidden")
                        .foregroundStyle(.secondary)
                }
                SettingsToggleRow(systemImage: "power.circle.fill", tint: .green, title: "Start on login", isOn: $model.startsAtLogin)
                SettingsToggleRow(systemImage: "rectangle.inset.filled.and.person.filled", tint: .purple, title: "Share data with widgets", isOn: $model.widgetsEnabled)
            }

            SettingsSection("Network") {
                SettingsRow(systemImage: "wifi", tint: .blue, title: "Current status") {
                    NetworkStatusBadge(status: model.currentNetworkStatus)
                }
                SettingsToggleRow(systemImage: "network", tint: .purple, title: "Monitor local network hosts", isOn: $model.allowsLocalNetworkProbes)
            }
        }
    }

    private var about: some View {
        SettingsPane {
            SettingsSection("PingScope") {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PingScope")
                            .font(.title2.weight(.semibold))
                        Text("Native latency monitoring for macOS.")
                            .foregroundStyle(.secondary)
                        Text("Version \(model.appVersionText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                SettingsRow(systemImage: "shippingbox", tint: .blue, title: "Build") {
                    Text(BuildFlavor.current == .appStore ? "App Store" : "Developer ID")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "number", tint: .gray, title: "Bundle ID") {
                    Text(model.bundleIdentifierText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "doc.text", tint: .purple, title: "License") {
                    Text("AGPLv3")
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection("First Run Checklist") {
                VStack(spacing: 8) {
                    ForEach(model.setupChecklistItems) { item in
                        SetupChecklistRow(item: item)
                    }
                }
            }

            SettingsSection("Links") {
                SettingsRow(systemImage: "globe", tint: .blue, title: "GitHub") {
                    Button("Open Repository") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/keithah/pingscope")!)
                    }
                }
                SettingsRow(systemImage: "lock.shield", tint: .green, title: "Privacy") {
                    Text("Settings, history, exports, and widget snapshots stay local.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var history: some View {
        SettingsPane {
            SettingsSection("Export") {
                SettingsRow(systemImage: "server.rack", tint: .blue, title: "Host") {
                    Picker("Host", selection: Binding(
                        get: { model.historyExportHost?.id ?? model.primaryHost?.id ?? model.snapshot.hosts.first?.id ?? UUID() },
                        set: { model.historyExportHostID = $0 }
                    )) {
                        ForEach(model.snapshot.hosts) { host in
                            Text(host.displayName).tag(host.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsRow(systemImage: "clock", tint: .purple, title: "Range") {
                    Picker("Range", selection: $model.historyExportRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                SettingsRow(systemImage: "square.and.arrow.down", tint: .green, title: "Export") {
                    HStack(spacing: 10) {
                        ForEach(HistoryExportFormat.allCases) { format in
                            Button(format.displayName) {
                                model.exportHistory(format: format)
                            }
                            .disabled(model.isExportingHistory || model.snapshot.hosts.isEmpty)
                        }
                    }
                }

                if let message = model.historyExportMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }

            SettingsSection("Storage") {
                SettingsRow(systemImage: "externaldrive", tint: .gray, title: "Retention") {
                    Text("7 days")
                        .foregroundStyle(.secondary)
                }
                Text("History is stored locally and pruned automatically. Export uses the selected host and range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        }
    }

    private var diagnostics: some View {
        SettingsPane {
            SettingsSection("Current State") {
                SettingsRow(systemImage: "server.rack", tint: .blue, title: "Primary host") {
                    Text(model.primaryHost?.displayName ?? "None")
                        .foregroundStyle(.secondary)
                }
                SettingsRow(systemImage: "wifi", tint: .blue, title: "Network status") {
                    NetworkStatusBadge(status: model.currentNetworkStatus)
                }
                SettingsRow(systemImage: "waveform.path.ecg", tint: Color(statusColor: model.primaryHealth.status.statusColor), title: "Latest result") {
                    Text(diagnosticsLatestResult)
                        .foregroundStyle(model.primaryHealth.latestResult?.failureReason == nil ? Color.secondary : Color.red)
                }
            }

            SettingsSection("Debug Log") {
                SettingsRow(systemImage: "doc.text", tint: .gray, title: "Path") {
                    Text(model.diagnosticsLogURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                SettingsRow(systemImage: "wrench.and.screwdriver", tint: .orange, title: "Actions") {
                    HStack(spacing: 10) {
                        Button("Reveal Log") {
                            model.revealDiagnosticsLog()
                        }
                        Button("Copy Summary") {
                            model.copyDiagnosticsSummary()
                        }
                        Button("Clear Log", role: .destructive) {
                            model.clearDiagnosticsLog()
                        }
                    }
                }
                if let message = model.diagnosticsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }

            SettingsSection("Recent Failures") {
                if model.recentDiagnosticFailures.isEmpty {
                    Text("No failures in the selected graph range.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.recentDiagnosticFailures) { result in
                            DiagnosticFailureRow(result: result)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsLatestResult: String {
        guard let result = model.primaryHealth.latestResult else { return "No samples yet" }
        if let latency = result.latency {
            return "\(Int(latency.milliseconds.rounded()))ms"
        }
        return result.failureReason?.userMessage ?? "Failed"
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case hosts
    case display
    case notifications
    case history
    case diagnostics
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hosts: "Hosts"
        case .display: "Display"
        case .notifications: "Notifications"
        case .history: "History"
        case .diagnostics: "Diagnostics"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .hosts: "Manage monitored endpoints, methods, thresholds, and primary selection."
        case .display: "Tune the menu bar indicator, overlay behavior, and graph range."
        case .notifications: "Control alert types, network status colors, and notification permission."
        case .history: "Export retained samples and review local storage behavior."
        case .diagnostics: "Inspect current state, failures, and debug log actions."
        case .advanced: "Configure local network probing, widgets, login, and update status."
        case .about: "Version, licensing, setup checklist, and project links."
        }
    }

    var systemImage: String {
        switch self {
        case .hosts: "server.rack"
        case .display: "display"
        case .notifications: "bell.badge"
        case .history: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct DiagnosticFailureRow: View {
    let result: PingResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(result.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(result.failureReason?.userMessage ?? "Failed")
                .foregroundStyle(.red)
                .frame(width: 150, alignment: .leading)
            Text("\(result.method.rawValue.uppercased()) \(result.address)\(result.port.map { ":\($0)" } ?? "")")
                .foregroundStyle(.secondary)
            if let note = result.metadata.note {
                Text(note)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct SetupChecklistRow: View {
    let item: SetupChecklistItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isComplete ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let actionTitle = item.actionTitle, let action = item.action, !item.isComplete {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct NetworkStatusBadge: View {
    let status: NetworkConnectivityStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: status.defaultColorHex))
                .frame(width: 10, height: 10)
            Text(status.displayName)
                .foregroundStyle(.secondary)
        }
    }
}

struct OverlayVisibilityToggle: View {
    @ObservedObject var model: PingScopeModel

    var body: some View {
        Toggle("Show overlay", isOn: Binding(
            get: { model.overlayVisible },
            set: { isVisible in
                if isVisible {
                    AppDelegate.shared?.showOverlay()
                } else {
                    AppDelegate.shared?.hideOverlay()
                }
            }
        ))
        .toggleStyle(.checkbox)
    }
}

struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SettingsRow<Content: View>: View {
    var systemImage: String?
    var tint: Color
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = nil
        self.tint = .secondary
        self.title = title
        self.content = content()
    }

    init(systemImage: String, tint: Color, title: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            Text(title)
                .frame(width: systemImage == nil ? 130 : 150, alignment: .leading)
                .foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
    }
}

struct SettingsToggleRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.checkbox)
        }
    }
}

struct HostSettingsRow: View {
    let host: HostConfig
    let isSelected: Bool
    let isPrimary: Bool
    let statusColor: Color
    let onSelect: () -> Void
    let onMakePrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.green)
                    }
                    if !host.isEnabled {
                        Text("OFF")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(host.method.rawValue.uppercased()) \(host.address)\(host.port.map { ":\($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Edit") {
                onSelect()
            }
            .buttonStyle(.bordered)
            if !isPrimary {
                Button("Primary") {
                    onMakePrimary()
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)
    }
}

struct SettingsField<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct UnitNumberField: View {
    @Binding var value: Double
    let unit: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            TextField(unit, value: $value, format: .number)
                .frame(width: width)
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

struct NetworkStatusToggleRow: View {
    let status: NetworkConnectivityStatus
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 10) {
                Text(status.displayName)
                    .frame(width: 120, alignment: .leading)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: status.defaultColorHex))
                    .frame(width: 82, height: 18)
            }
        }
        .toggleStyle(.checkbox)
    }
}

struct RecentSamplesView<Samples: Sequence<PingResult>>: View {
    let samples: Samples
    var range: TimeRange? = nil

    var body: some View {
        let sampleArray = Array(samples)

        ZStack {
            Table(sampleArray) {
                TableColumn("Time") { result in
                    Text(result.timestamp, style: .time)
                }
                TableColumn("Result") { result in
                    if let latency = result.latency {
                        Text("\(Int(latency.milliseconds.rounded()))ms")
                    } else {
                        Text(result.failureReason?.userMessage ?? "Failed")
                            .foregroundStyle(.red)
                    }
                }
                TableColumn("Status") { result in
                    Text(result.isSuccess ? "OK" : "Failed")
                }
            }

            if sampleArray.isEmpty {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 140)
    }

    private var emptyMessage: String {
        if let range {
            return "No samples in the last \(range.rawValue)."
        }
        return "No samples yet."
    }
}

struct LatencyGraph: View {
    let samples: [PingResult]
    var showsAxes = false

    var body: some View {
        let latencies = samples.compactMap { $0.latency?.milliseconds }
        let scale = LatencyGraphScale(latencies: latencies)

        HStack(spacing: showsAxes ? 6 : 0) {
            if showsAxes {
                axisLabels(scale: scale, hasData: !latencies.isEmpty)
            }

            ZStack {
                graphCanvas(scale: scale)

                if latencies.isEmpty {
                    Text("No samples in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if showsAxes {
                rightTicks(scale: scale)
            }
        }
        .accessibilityLabel("Latency graph")
    }

    private func graphCanvas(scale: LatencyGraphScale) -> some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let latencies = samples.compactMap { $0.latency?.milliseconds }
                guard latencies.count > 1 else {
                    let rect = CGRect(origin: .zero, size: size)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.secondary.opacity(0.25)))
                    return
                }

                if showsAxes {
                    drawGrid(in: size, context: context, scale: scale)
                }

                let maxValue = scale.axisMaximumMilliseconds
                var path = Path()
                var isDrawingSegment = false
                let plotTop: CGFloat = showsAxes ? 6 : 0
                let plotBottom: CGFloat = showsAxes ? 6 : 0
                let plotHeight = max(size.height - plotTop - plotBottom, 1)

                for (index, sample) in samples.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                    guard let value = sample.latency?.milliseconds else {
                        let failureMark = Path { mark in
                            mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                            mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                        }
                        context.stroke(failureMark, with: .color(.red.opacity(0.72)), lineWidth: 1.5)
                        isDrawingSegment = false
                        continue
                    }

                    let normalized = min(value / maxValue, 1)
                    let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
                    let point = CGPoint(x: x, y: y)
                    if !isDrawingSegment {
                        path.move(to: point)
                        isDrawingSegment = true
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 2)

            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func axisLabels(scale: LatencyGraphScale, hasData: Bool) -> some View {
        VStack(alignment: .trailing) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Text(hasData ? scale.label(for: value) : (value == 0 ? "0ms" : "--"))
                    .frame(height: 12, alignment: .center)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 34)
    }

    private func rightTicks(scale: LatencyGraphScale) -> some View {
        VStack(alignment: .leading) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 6, height: 1)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 6)
        .padding(.vertical, 6)
    }

    private func drawGrid(in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let plotTop: CGFloat = 6
        let plotHeight = max(size.height - 12, 1)
        for tick in scale.tickMilliseconds {
            let normalized = min(max(tick / scale.axisMaximumMilliseconds, 0), 1)
            let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.secondary.opacity(tick == 0 ? 0.24 : 0.14)), lineWidth: 1)
        }
    }
}

struct HostLatencyGraphSeries: Identifiable {
    let host: HostConfig
    let samples: [PingResult]
    let color: Color
    let isPrimary: Bool

    var id: UUID { host.id }

    static let palette: [Color] = [
        .blue,
        .green,
        .orange,
        .purple,
        .pink,
        .cyan
    ]
}

struct MultiHostLatencyGraph: View {
    let series: [HostLatencyGraphSeries]
    var showsAxes = false
    var showsLegend = true

    var body: some View {
        let latencies = series.flatMap { hostSeries in
            hostSeries.samples.compactMap { $0.latency?.milliseconds }
        }
        let scale = LatencyGraphScale(latencies: latencies)

        HStack(spacing: showsAxes ? 6 : 0) {
            if showsAxes {
                axisLabels(scale: scale, hasData: !latencies.isEmpty)
            }

            ZStack(alignment: .bottomLeading) {
                graphCanvas(scale: scale)

                if latencies.isEmpty {
                    Text("No samples in range")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showsLegend {
                    legend
                        .padding(8)
                }
            }

            if showsAxes {
                rightTicks(scale: scale)
            }
        }
        .accessibilityLabel("All hosts latency graph")
    }

    private var legend: some View {
        let visibleSeries = series.filter { !$0.samples.isEmpty }.prefix(4)

        return HStack(spacing: 8) {
            ForEach(Array(visibleSeries)) { hostSeries in
                HStack(spacing: 4) {
                    Circle()
                        .fill(hostSeries.color)
                        .frame(width: 6, height: 6)
                    Text(hostSeries.host.displayName)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: hostSeries.isPrimary ? .semibold : .regular))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func graphCanvas(scale: LatencyGraphScale) -> some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard series.contains(where: { $0.samples.count > 1 }) else {
                    let rect = CGRect(origin: .zero, size: size)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.secondary.opacity(0.25)))
                    return
                }

                if showsAxes {
                    drawGrid(in: size, context: context, scale: scale)
                }

                for hostSeries in series where hostSeries.samples.count > 1 {
                    draw(hostSeries, in: size, context: context, scale: scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func draw(_ hostSeries: HostLatencyGraphSeries, in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let maxValue = scale.axisMaximumMilliseconds
        let plotTop: CGFloat = showsAxes ? 6 : 0
        let plotBottom: CGFloat = showsAxes ? 6 : 0
        let plotHeight = max(size.height - plotTop - plotBottom, 1)
        var path = Path()
        var isDrawingSegment = false

        for (index, sample) in hostSeries.samples.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(max(hostSeries.samples.count - 1, 1))
            guard let value = sample.latency?.milliseconds else {
                if hostSeries.isPrimary {
                    let failureMark = Path { mark in
                        mark.move(to: CGPoint(x: x, y: plotTop + plotHeight * 0.2))
                        mark.addLine(to: CGPoint(x: x, y: plotTop + plotHeight))
                    }
                    context.stroke(failureMark, with: .color(.red.opacity(0.55)), lineWidth: 1.2)
                }
                isDrawingSegment = false
                continue
            }

            let normalized = min(value / maxValue, 1)
            let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
            let point = CGPoint(x: x, y: y)
            if !isDrawingSegment {
                path.move(to: point)
                isDrawingSegment = true
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(
            path,
            with: .color(hostSeries.color.opacity(hostSeries.isPrimary ? 1 : 0.72)),
            lineWidth: hostSeries.isPrimary ? 2.2 : 1.5
        )
    }

    private func axisLabels(scale: LatencyGraphScale, hasData: Bool) -> some View {
        VStack(alignment: .trailing) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Text(hasData ? scale.label(for: value) : (value == 0 ? "0ms" : "--"))
                    .frame(height: 12, alignment: .center)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 34)
    }

    private func rightTicks(scale: LatencyGraphScale) -> some View {
        VStack(alignment: .leading) {
            ForEach(Array(scale.tickMilliseconds.enumerated()), id: \.offset) { _, value in
                Rectangle()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 6, height: 1)
                if value != scale.tickMilliseconds.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 6)
        .padding(.vertical, 6)
    }

    private func drawGrid(in size: CGSize, context: GraphicsContext, scale: LatencyGraphScale) {
        let plotTop: CGFloat = 6
        let plotHeight = max(size.height - 12, 1)
        for tick in scale.tickMilliseconds {
            let normalized = min(max(tick / scale.axisMaximumMilliseconds, 0), 1)
            let y = plotTop + plotHeight - (plotHeight * CGFloat(normalized))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.secondary.opacity(tick == 0 ? 0.24 : 0.14)), lineWidth: 1)
        }
    }
}

private extension Color {
    init(statusColor: StatusColor) {
        switch statusColor {
        case .gray: self = .gray
        case .green: self = .green
        case .yellow: self = .yellow
        case .red: self = .red
        }
    }

    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(trimmed, radix: 16), trimmed.count == 6 else {
            self = .secondary
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }
}

private extension HealthStatus {
    var statusColor: StatusColor {
        switch self {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }
}

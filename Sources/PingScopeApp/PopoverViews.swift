import PingScopeCore
import PingScopeHistoryKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var viewModel: StatusPopoverPresentationViewModel
    @ObservedObject var liveDisplay: LiveDisplayModel
    var onHistory: () -> Void = {}
    var onSettings: () -> Void = {}
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var isShareOptionsPresented = false
    @State private var shareOptions = PingScopeShareGraphOptions()

    var body: some View {
        let presentation = viewModel.presentation
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 13) {
                header

                switch presentation.displayMode {
                case .signal:
                    signalDisplay
                case .ring:
                    ringDisplay
                    sparkline
                        .frame(height: 58)
                    rangePicker
                }

                if let telemetry = presentation.displayPresentation.latestStarlinkTelemetry {
                    StarlinkTelemetrySummary(
                        presentation: StarlinkTelemetryPresentation(telemetry: telemetry)
                    )
                }
                if presentation.popoverShowsAllHosts {
                    allHostStatusSummary
                }
                RecentSamplesView(samples: presentation.displayPresentation.recentVisibleSamples, range: presentation.selectedRange)
            }
            .padding(MenuBarPresentationMode.statusContentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: MenuBarPresentationMode.statusContentMinimumSize.width,
            idealWidth: MenuBarPresentationMode.statusContentSize.width,
            maxWidth: .infinity,
            minHeight: 430,
            idealHeight: 500,
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
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Share graph")
            .accessibilityLabel("Share graph")
            Button(action: onHistory) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open History")
            .accessibilityLabel("Open History")
            settingsMenu
        }
    }

    private static let allHostsSelectionID = "__all_hosts__"

    private var hostSubtitle: String {
        let presentation = viewModel.presentation
        if presentation.popoverShowsAllHosts {
            return ""
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
                        .foregroundStyle(presentation.popoverShowsAllHosts ? Color.primary : identityColor)
                        .lineLimit(1)
                    if !presentation.popoverShowsAllHosts, presentation.displayMode == .ring {
                        Text(hostSubtitle)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
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
            Picker("Display style", selection: Binding(
                get: { presentation.displayMode },
                set: { viewModel.setDisplayMode($0) }
            )) {
                ForEach(PingScopeDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Divider()
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
            Button("Open History", action: onHistory)
            Button("Open Settings", action: onSettings)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.thinMaterial, in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    @ViewBuilder
    private var signalDisplay: some View {
        let presentation = viewModel.presentation
        VStack(alignment: .leading, spacing: 12) {
            if !presentation.popoverShowsAllHosts {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        latencyReading(size: 44)
                        Text(endpointCaption)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    latencyStatusBadge
                }
            }

            HStack(alignment: .center, spacing: 10) {
                rangePicker
                    .frame(maxWidth: .infinity)
                pingIntervalPicker
                    .frame(width: 92)
            }

            signalGraphCard
                .frame(height: 130)

            HStack(spacing: 0) {
                compactStat("TX", "\(presentation.displayPresentation.primaryStats.transmitted)")
                compactStat("RX", "\(presentation.displayPresentation.primaryStats.received)")
                compactStat("Loss", "\(Int(presentation.displayPresentation.primaryStats.lossPercent.rounded()))%")
                compactStat("Min", latencyNumber(presentation.displayPresentation.primaryStats.minimumMilliseconds))
                compactStat("Avg", latencyNumber(presentation.displayPresentation.primaryStats.averageMilliseconds))
                compactStat("Max", latencyNumber(presentation.displayPresentation.primaryStats.maximumMilliseconds))
            }

            Divider()
        }
    }

    private var ringDisplay: some View {
        let presentation = viewModel.presentation
        return HStack(alignment: .center, spacing: 18) {
            PulseHealthRing(progress: ringProgress, color: ringColor, lineWidth: 13)
                .frame(width: 150, height: 150)
                .overlay {
                    VStack(spacing: 2) {
                        Text(latencyNumberText)
                            .font(.system(size: 44, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ringColor)
                            .minimumScaleFactor(0.7)
                        Text(presentation.selectedRangeStatusLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(healthColor)
                            .lineLimit(1)
                    }
                }

            VStack(alignment: .leading, spacing: 13) {
                Text(endpointCaption)
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
    }

    private var signalGraphCard: some View {
        VStack(spacing: 6) {
            signalGraph
            HStack {
                Text(viewModel.presentation.selectedRange.rawValue)
                Spacer()
                Text("now")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [PingScopeSurfaceColors.graphCardTop.swiftUIColor, PingScopeSurfaceColors.graphCardBottom.swiftUIColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private var signalGraph: some View {
        let presentation = viewModel.presentation
        if presentation.popoverShowsAllHosts {
            MultiHostLatencyGraph(
                series: presentation.displayPresentation.allHostGraphSeries,
                graphData: presentation.displayPresentation.allHostsGraphData,
                showsAxes: true,
                showsLegend: false
            )
        } else {
            LatencyGraph(
                graphData: presentation.displayPresentation.primaryGraphData,
                showsAxes: true,
                color: presentation.displayPresentation.focusedGraphColor?.swiftUIColor ?? .accentColor
            )
        }
    }

    private var pingIntervalPicker: some View {
        let presentation = viewModel.presentation
        return Group {
            if presentation.popoverShowsAllHosts {
                let selectedMilliseconds = allHostsPingIntervalSelection
                Picker("Ping interval", selection: Binding(
                    get: { selectedMilliseconds },
                    set: { milliseconds in
                        guard let milliseconds else { return }
                        viewModel.setPingIntervalForAllHosts(milliseconds)
                    }
                )) {
                    if selectedMilliseconds == nil {
                        Text("Mixed").tag(Optional<Int>.none)
                    }
                    ForEach(PingIntervalPresentation.options(including: allHostsPingIntervalOptionFallback)) { option in
                        Text(option.label).tag(Optional(option.milliseconds))
                    }
                }
                .labelsHidden()
            } else if let host = presentation.primaryHost {
                let selectedMilliseconds = PingIntervalPresentation.selection(for: host.interval)
                Picker("Ping interval", selection: Binding(
                    get: { selectedMilliseconds },
                    set: { milliseconds in viewModel.setPingInterval(milliseconds, for: host.id) }
                )) {
                    ForEach(PingIntervalPresentation.options(including: selectedMilliseconds)) { option in
                        Text(option.label).tag(option.milliseconds)
                    }
                }
                .labelsHidden()
            }
        }
        .accessibilityLabel("Ping interval")
    }

    private var allHostsPingIntervalSelection: Int? {
        let hosts = viewModel.presentation.snapshot.hosts.filter(\.isEnabled)
        let targetHosts = hosts.isEmpty ? viewModel.presentation.snapshot.hosts : hosts
        return PingIntervalPresentation.commonSelection(for: targetHosts.map(\.interval))
    }

    private var allHostsPingIntervalOptionFallback: Int {
        allHostsPingIntervalSelection
            ?? PingIntervalPresentation.selection(for: viewModel.presentation.primaryHost?.interval ?? .seconds(2))
    }

    private var latencyStatusBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
            Text(viewModel.presentation.selectedRangeState.text)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(healthColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(healthColor.opacity(0.16), in: Capsule())
        .accessibilityLabel(viewModel.presentation.selectedRangeState.accessibilityLabel)
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

    private func compactStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func latencyReading(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(latencyNumberText)
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .foregroundStyle(identityColor)
                .minimumScaleFactor(0.75)
            if viewModel.presentation.selectedRangeState.text.hasSuffix("ms") {
                Text("ms")
                    .font(.system(size: size * 0.38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var ringColor: Color {
        viewModel.presentation.displayPresentation.focusedRingColor?.swiftUIColor ?? healthColor
    }

    private var identityColor: Color {
        viewModel.presentation.displayPresentation.focusedIdentityColor?.swiftUIColor ?? .accentColor
    }

    private var healthColor: Color {
        Color(statusColor: viewModel.presentation.selectedRangeState.color)
    }

    private var endpointCaption: String {
        hostSubtitle.replacingOccurrences(of: " ", with: " · ", options: [], range: hostSubtitle.range(of: " "))
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

    private func latencyNumber(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
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
        let presentation = viewModel.presentation
        return VStack(spacing: 0) {
            ForEach(Array(presentation.displayPresentation.hostStatusSummaries.enumerated()), id: \.element.id) { index, summary in
                AllHostStatusRow(
                    summary: summary,
                    graphSeries: presentation.displayPresentation.allHostGraphSeries.first { $0.id == summary.id }
                )
                if index < presentation.displayPresentation.hostStatusSummaries.count - 1 {
                    Divider()
                        .padding(.leading, 36)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

}

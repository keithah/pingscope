import Foundation
import PingScopeCore
import SwiftUI

#if os(iOS)
public struct PingScopeIOSRootView: View {
    @State private var editingHost: HostConfig?
    private static let defaultGatewayMenuID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    public var hosts: [HostConfig]
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth
    public var samples: [PingResult]
    public var graphPresentation: PingScopeIOSGraphPresentation
    public var historySamples: [PingResult]
    public var selectedGraphRange: TimeRange
    public var gatewayDetectionText: String?
    public var backgroundKeepAliveEnabled: Bool
    public var backgroundKeepAliveStatus: String
    public var selectedHostID: UUID
    public var onSelectHost: (UUID) -> Void
    public var onSaveHost: (HostConfig) -> Void
    public var onDeleteHost: (UUID) -> Void
    public var onSelectGraphRange: (TimeRange) -> Void
    public var onUseDefaultGateway: () -> Void
    public var onSetBackgroundKeepAlive: (Bool) -> Void
    public var onRequestBackgroundKeepAlivePermission: () -> Void
    public var onStart: (MonitorSessionDuration) -> Void
    public var onStop: () -> Void

    public init(
        hosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts,
        host: HostConfig = .defaultInternet,
        session: MonitorSessionState? = nil,
        health: HostHealth = HostHealth(hostID: HostConfig.defaultInternet.id, thresholds: HostConfig.defaultInternet.thresholds),
        samples: [PingResult] = [],
        graphPresentation: PingScopeIOSGraphPresentation? = nil,
        historySamples: [PingResult] = [],
        selectedGraphRange: TimeRange = .fiveMinutes,
        gatewayDetectionText: String? = nil,
        backgroundKeepAliveEnabled: Bool = false,
        backgroundKeepAliveStatus: String = "Disabled",
        selectedHostID: UUID? = nil,
        onSelectHost: @escaping (UUID) -> Void = { _ in },
        onSaveHost: @escaping (HostConfig) -> Void = { _ in },
        onDeleteHost: @escaping (UUID) -> Void = { _ in },
        onSelectGraphRange: @escaping (TimeRange) -> Void = { _ in },
        onUseDefaultGateway: @escaping () -> Void = {},
        onSetBackgroundKeepAlive: @escaping (Bool) -> Void = { _ in },
        onRequestBackgroundKeepAlivePermission: @escaping () -> Void = {},
        onStart: @escaping (MonitorSessionDuration) -> Void = { _ in },
        onStop: @escaping () -> Void = {}
    ) {
        self.hosts = hosts
        self.host = host
        self.session = session
        self.health = health
        self.samples = samples
        self.graphPresentation = graphPresentation ?? PingScopeIOSGraphPresentation(samples: samples, range: selectedGraphRange)
        self.historySamples = historySamples
        self.selectedGraphRange = selectedGraphRange
        self.gatewayDetectionText = gatewayDetectionText
        self.backgroundKeepAliveEnabled = backgroundKeepAliveEnabled
        self.backgroundKeepAliveStatus = backgroundKeepAliveStatus
        self.selectedHostID = selectedHostID ?? host.id
        self.onSelectHost = onSelectHost
        self.onSaveHost = onSaveHost
        self.onDeleteHost = onDeleteHost
        self.onSelectGraphRange = onSelectGraphRange
        self.onUseDefaultGateway = onUseDefaultGateway
        self.onSetBackgroundKeepAlive = onSetBackgroundKeepAlive
        self.onRequestBackgroundKeepAlivePermission = onRequestBackgroundKeepAlivePermission
        self.onStart = onStart
        self.onStop = onStop
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appHeader
                        .fixedSize(horizontal: false, vertical: true)
                    fixedMonitorContent
                    history
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .navigationBarHidden(true)
            .sheet(item: $editingHost) { draft in
                PingScopeIOSHostEditor(
                    host: draft,
                    canDelete: hosts.count > 1 && hosts.contains(where: { $0.id == draft.id }),
                    onSave: { updated in
                        onSaveHost(updated)
                        editingHost = nil
                    },
                    onDelete: {
                        onDeleteHost(draft.id)
                        editingHost = nil
                    },
                    onCancel: {
                        editingHost = nil
                    }
                )
            }
        }
    }

    private var fixedMonitorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            hostSummary
                .fixedSize(horizontal: false, vertical: true)
            sessionSummary
                .fixedSize(horizontal: false, vertical: true)
            graphRangePicker
                .fixedSize(horizontal: false, vertical: true)
            PingScopeIOSLatencyGraph(renderData: graphPresentation.renderData, range: selectedGraphRange)
                .frame(height: 170)
                .fixedSize(horizontal: false, vertical: true)
            controls
                .fixedSize(horizontal: false, vertical: true)
            backgroundKeepAlive
                .fixedSize(horizontal: false, vertical: true)
            stats
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    private var appHeader: some View {
        HStack(alignment: .center) {
            Text("PingScope")
                .font(.system(size: 42, weight: .bold, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            HStack(spacing: 10) {
                Button("Edit") {
                    editingHost = host
                }
                Button {
                    editingHost = HostConfig(displayName: "", address: "")
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                }
                .accessibilityLabel("Add host")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hostSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Host", selection: Binding(
                get: { selectedHostID },
                set: { selection in
                    if selection == Self.defaultGatewayMenuID {
                        onUseDefaultGateway()
                    } else {
                        onSelectHost(selection)
                    }
                }
            )) {
                ForEach(hosts) { host in
                    Text(host.displayName).tag(host.id)
                }
                Divider()
                Label("Default Gateway", systemImage: "network")
                    .tag(Self.defaultGatewayMenuID)
            }
            .pickerStyle(.menu)

            Text("\(host.method.rawValue.uppercased()) \(host.address)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let gatewayDetectionText {
                Text(gatewayDetectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    private var sessionSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)

            Text(latencyText)
                .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session?.phase().rawValue.capitalized ?? "Ready")
                    .font(.headline)
                Text(remainingText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                durationButton("Live", duration: .continuous)
                durationButton("30s", duration: .thirtySeconds)
                durationButton("1m", duration: .oneMinute)

                Button("Stop") {
                    onStop()
                }
                .buttonStyle(.bordered)
                .disabled(session == nil)
            }
        }
    }

    private var graphRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Graph")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                graphRangeButton(.oneMinute)
                graphRangeButton(.fiveMinutes)
                graphRangeButton(.tenMinutes)
            }
        }
    }

    @ViewBuilder
    private func graphRangeButton(_ range: TimeRange) -> some View {
        if selectedGraphRange == range {
            Button(range.rawValue) {
                onSelectGraphRange(range)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(range.rawValue) {
                onSelectGraphRange(range)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func durationButton(_ title: String, duration: MonitorSessionDuration) -> some View {
        let isSelected = session?.duration == duration
        if isSelected {
            Button(title) {
                onStart(duration)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                onStart(duration)
            }
            .buttonStyle(.bordered)
        }
    }

    private var stats: some View {
        let stats = graphPresentation.stats
        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                statCell("TX", "\(stats.transmitted)")
                statCell("RX", "\(stats.received)")
                statCell("Loss", "\(Int(stats.lossPercent.rounded()))%")
            }
            GridRow {
                statCell("Min", latencyValue(stats.minimumMilliseconds))
                statCell("Avg", latencyValue(stats.averageMilliseconds))
                statCell("Max", latencyValue(stats.maximumMilliseconds))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var backgroundKeepAlive: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { backgroundKeepAliveEnabled },
                set: { onSetBackgroundKeepAlive($0) }
            )) {
                Label("Background Keep Alive", systemImage: "location.fill")
                    .font(.headline)
            }

            Text("Optional. Uses Always Location permission only while monitoring is active so iOS can keep PingScope running after you leave the app. This may reduce battery life.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(backgroundKeepAliveStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Request Always") {
                    onRequestBackgroundKeepAlivePermission()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
    }

    private var latencyText: String {
        guard let milliseconds = health.latestResult?.latency?.milliseconds else { return "--ms" }
        return "\(Int(milliseconds.rounded()))ms"
    }

    private var remainingText: String {
        guard let session else { return "Starting..." }
        if session.phase() == .ended { return "Ended" }
        if session.duration == .continuous { return "App open" }
        return "\(Int(ceil(session.remainingDuration().seconds)))s left"
    }

    private var statusColor: Color {
        switch health.status {
        case .noData: .gray
        case .healthy: .green
        case .degraded: .yellow
        case .down: .red
        }
    }

    private func latencyValue(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "--" }
        return "\(Int(milliseconds.rounded()))ms"
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent History")
                    .font(.headline)
                Spacer()
                Text(historySamples.isEmpty ? "No samples" : "\(historySamples.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if historySamples.isEmpty {
                Text("Samples appear here after monitoring starts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(historySamples) { sample in
                        historyRow(sample)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func historyRow(_ sample: PingResult) -> some View {
        HStack {
            Text(sample.timestamp, style: .time)
                .font(.subheadline.monospacedDigit())
            Spacer()
            Text(sample.latency.map { "\(Int($0.milliseconds.rounded()))ms" } ?? sample.failureReason?.userMessage ?? "Failed")
                .font(.subheadline.monospacedDigit())
            Text(sample.failureReason == nil ? "OK" : "Fail")
                .font(.caption.weight(.semibold))
                .foregroundStyle(sample.failureReason == nil ? .green : .red)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PingScopeIOSHostEditor: View {
    @State private var draft: PingScopeIOSHostDraft

    let canDelete: Bool
    let onSave: (HostConfig) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        host: HostConfig,
        canDelete: Bool,
        onSave: @escaping (HostConfig) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: PingScopeIOSHostDraft(host: host))
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $draft.displayName)
                    TextField("Address", text: $draft.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Probe") {
                    Picker("Method", selection: methodBinding) {
                        ForEach(PingMethod.appStoreAvailableCases, id: \.self) { method in
                            Text(method.rawValue.uppercased()).tag(method)
                        }
                    }

                    TextField("Port", text: portText)
                        .keyboardType(.numberPad)
                        .disabled(draft.method == .icmp)
                }

                Section("Timing") {
                    Stepper(value: $draft.intervalMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Interval", value: "\(Int(draft.intervalMilliseconds))ms")
                    }
                    Stepper(value: $draft.timeoutMilliseconds, in: 250...10_000, step: 250) {
                        LabeledContent("Timeout", value: "\(Int(draft.timeoutMilliseconds))ms")
                    }
                }

                Section("Health") {
                    Stepper(value: $draft.degradedMilliseconds, in: 1...2_000, step: 25) {
                        LabeledContent("Degraded", value: "\(Int(draft.degradedMilliseconds))ms")
                    }
                    Stepper(value: $draft.downAfterFailures, in: 1...10) {
                        LabeledContent("Down after", value: "\(draft.downAfterFailures) failures")
                    }
                }

                if canDelete {
                    Section {
                        Button("Delete Host", role: .destructive) {
                            onDelete()
                        }
                    }
                }
            }
            .navigationTitle(draft.displayName.isEmpty ? "New Host" : "Edit Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.finalizedHost)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var methodBinding: Binding<PingMethod> {
        Binding(
            get: { draft.method },
            set: { method in
                draft.apply(method: method)
            }
        )
    }

    private var portText: Binding<String> {
        Binding(
            get: { draft.portText },
            set: { draft.portText = $0.filter(\.isNumber) }
        )
    }

    private var canSave: Bool {
        draft.canSave
    }
}

private struct PingScopeIOSLatencyGraph: View {
    let renderData: PingScopeIOSLatencyGraphData
    let range: TimeRange

    private let yAxisWidth: CGFloat = 48
    private let xAxisHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                yAxisLabels(renderData: renderData)
                    .frame(width: yAxisWidth)

                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawLine(renderData: renderData, context: &context, size: size)
                }
            }

            HStack {
                Color.clear
                    .frame(width: yAxisWidth + 8)
                Text(renderData.startDate, style: .time)
                Spacer()
                Text(renderData.endDate, style: .time)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(height: xAxisHeight)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func yAxisLabels(renderData: PingScopeIOSLatencyGraphData) -> some View {
        VStack(alignment: .trailing) {
            ForEach(renderData.scale.tickMilliseconds, id: \.self) { tick in
                Text(renderData.scale.label(for: tick))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: tick == renderData.scale.tickMilliseconds.first ? .top : tick == 0 ? .bottom : .center)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        for ratio in [0.0, 0.5, 1.0] {
            let y = size.height * ratio
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
    }

    private func drawLine(renderData: PingScopeIOSLatencyGraphData, context: inout GraphicsContext, size: CGSize) {
        guard renderData.points.count > 1 else { return }
        var path = Path()
        let axisMax = max(renderData.scale.axisMaximumMilliseconds, 1)

        for (index, pointValue) in renderData.points.enumerated() {
            let elapsed = pointValue.timestamp.timeIntervalSince(renderData.startDate)
            let x = size.width * CGFloat(min(max(elapsed / range.duration, 0), 1))
            let latency = pointValue.latencyMilliseconds
            let y = size.height - (size.height * CGFloat(min(latency / axisMax, 1)))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(.blue), lineWidth: 3)
    }
}

#endif

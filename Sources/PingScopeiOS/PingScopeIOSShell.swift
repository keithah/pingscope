import Foundation
import PingScopeCore
import SwiftUI

#if os(iOS)
public struct PingScopeIOSRootView: View {
    @State private var editingHost: HostConfig?

    public var hosts: [HostConfig]
    public var host: HostConfig
    public var session: MonitorSessionState?
    public var health: HostHealth
    public var samples: [PingResult]
    public var historySamples: [PingResult]
    public var selectedHostID: UUID
    public var onSelectHost: (UUID) -> Void
    public var onSaveHost: (HostConfig) -> Void
    public var onDeleteHost: (UUID) -> Void
    public var onStart: (MonitorSessionDuration) -> Void
    public var onStop: () -> Void

    public init(
        hosts: [HostConfig] = PingScopeIOSHostStore.defaultHosts,
        host: HostConfig = .defaultInternet,
        session: MonitorSessionState? = nil,
        health: HostHealth = HostHealth(hostID: HostConfig.defaultInternet.id, thresholds: HostConfig.defaultInternet.thresholds),
        samples: [PingResult] = [],
        historySamples: [PingResult] = [],
        selectedHostID: UUID? = nil,
        onSelectHost: @escaping (UUID) -> Void = { _ in },
        onSaveHost: @escaping (HostConfig) -> Void = { _ in },
        onDeleteHost: @escaping (UUID) -> Void = { _ in },
        onStart: @escaping (MonitorSessionDuration) -> Void = { _ in },
        onStop: @escaping () -> Void = {}
    ) {
        self.hosts = hosts
        self.host = host
        self.session = session
        self.health = health
        self.samples = samples
        self.historySamples = historySamples
        self.selectedHostID = selectedHostID ?? host.id
        self.onSelectHost = onSelectHost
        self.onSaveHost = onSaveHost
        self.onDeleteHost = onDeleteHost
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
            PingScopeIOSLatencyGraph(samples: samples)
                .frame(height: 170)
                .fixedSize(horizontal: false, vertical: true)
            controls
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
                set: { onSelectHost($0) }
            )) {
                ForEach(hosts) { host in
                    Text(host.displayName).tag(host.id)
                }
            }
            .pickerStyle(.menu)

            Text("\(host.method.rawValue.uppercased()) \(host.address)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        let stats = SampleStats(samples: samples)
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
                Text("Start a session to store local samples.")
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
    let samples: [PingResult]

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)
            drawLine(context: &context, size: size)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            Text(axisLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var latencies: [Double] {
        samples.compactMap { $0.latency?.milliseconds }
    }

    private var scale: LatencyGraphScale {
        LatencyGraphScale(latencies: latencies)
    }

    private var axisLabel: String {
        latencies.isEmpty ? "--" : scale.label(for: scale.axisMaximumMilliseconds)
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

    private func drawLine(context: inout GraphicsContext, size: CGSize) {
        guard latencies.count > 1 else { return }
        var path = Path()
        let axisMax = max(scale.axisMaximumMilliseconds, 1)

        for (index, latency) in latencies.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(max(latencies.count - 1, 1))
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
#else
public enum PingScopeIOSBuildMarker {
    public static let isAvailableOnThisPlatform = false
}
#endif

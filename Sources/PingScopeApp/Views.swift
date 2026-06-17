import PingScopeCore
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var model: PingScopeModel
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("Range", selection: $model.selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            LatencyGraph(samples: model.visibleSamples, showsAxes: true)
                .frame(height: 150)

            stats

            RecentSamplesView(samples: Array(model.visibleSamples.suffix(8)).reversed())
        }
        .padding(16)
        .frame(width: 430, height: 540, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if model.snapshot.hosts.count > 1 {
                    Picker("Host", selection: Binding(
                        get: { model.primaryHost?.id ?? model.snapshot.hosts.first?.id ?? UUID() },
                        set: { model.selectHost($0) }
                    )) {
                        ForEach(model.snapshot.hosts) { host in
                            Text(host.displayName).tag(host.id)
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
                Text("\(model.primaryHost?.method.rawValue.uppercased() ?? "TCP") \(model.primaryHost?.address ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.menuBarState.text)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    Label(model.primaryHealth.status.rawValue.capitalized, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(statusColor: model.menuBarState.color))
                }
                Button {
                    (NSApp.delegate as? AppDelegate)?.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open settings")
                .accessibilityLabel("Open settings")
            }
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
            LatencyGraph(samples: model.visibleSamples)
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
                (NSApp.delegate as? AppDelegate)?.toggleOverlayCompactMode()
            }
            Button("Open Popover") {
                model.openOverlayDetails()
            }
            Button("Settings...") {
                (NSApp.delegate as? AppDelegate)?.openSettings()
            }
            Divider()
            Button("Close Overlay") {
                (NSApp.delegate as? AppDelegate)?.hideOverlay()
            }
        }
    }

    @ViewBuilder
    private var overlayHostSelector: some View {
        if model.snapshot.hosts.count > 1 {
            Menu {
                ForEach(model.snapshot.hosts) { host in
                    Button(host.displayName) {
                        model.selectHost(host.id)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.primaryHost?.displayName ?? "No Host")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader

            TabView {
                ScrollView { hosts.padding(.top, 8) }
                    .tabItem { Label("Hosts", systemImage: "server.rack") }
                ScrollView { display.padding(.top, 8) }
                    .tabItem { Label("Display", systemImage: "display") }
                ScrollView { notifications.padding(.top, 8) }
                    .tabItem { Label("Notifications", systemImage: "bell.badge") }
                ScrollView { history.padding(.top, 8) }
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                ScrollView { advanced.padding(.top, 8) }
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            }

            settingsFooter
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 620)
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PingScope Settings")
                .font(.system(size: 22, weight: .semibold))
            Text("Manage hosts, display behavior, notifications, and network probing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                HStack {
                    Text("\(model.snapshot.hosts.count) configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.clearDraftHost()
                    } label: {
                        Label("New Host", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
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

            SettingsSection(model.editingHostID == nil ? "New Host" : "Host Details") {
                hostEditor
            }
        }
    }

    private var hostEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    SettingsField("Name") {
                        TextField("Name", text: $model.draftHostName)
                            .frame(width: 220)
                    }
                    SettingsField("Address") {
                        TextField("Address", text: $model.draftHostAddress)
                            .frame(width: 220)
                    }
                    Toggle("Enabled", isOn: $model.draftIsEnabled)
                        .toggleStyle(.checkbox)
                }
                GridRow {
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
                        .frame(width: 110)
                    }
                    SettingsField("Port") {
                        TextField("Port", value: $model.draftPort, format: .number)
                            .frame(width: 90)
                            .disabled(model.draftMethod == .icmp)
                    }
                    SettingsField("Notifications") {
                        Picker("Notifications", selection: $model.draftNotificationPolicy) {
                            ForEach(HostNotificationPolicy.allCases, id: \.self) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
                GridRow {
                    SettingsField("Interval") {
                        UnitNumberField(value: $model.draftIntervalMilliseconds, unit: "ms", width: 90)
                    }
                    SettingsField("Timeout") {
                        UnitNumberField(value: $model.draftTimeoutMilliseconds, unit: "ms", width: 90)
                    }
                    SettingsField("Degraded at") {
                        UnitNumberField(value: $model.draftDegradedThresholdMilliseconds, unit: "ms", width: 90)
                    }
                }
            }

            HStack(spacing: 12) {
                Stepper("Down after \(model.draftDownAfterFailures) failures", value: $model.draftDownAfterFailures, in: 1...10)
                    .frame(width: 205, alignment: .leading)
                Spacer()
                if let result = model.draftTestResultText {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Failed") ? .red : .secondary)
                }
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
                    Label("New", systemImage: "square.and.pencil")
                }
                .disabled(model.editingHostID == nil && model.draftHostName.isEmpty && model.draftHostAddress.isEmpty)
            }

            HStack(spacing: 12) {
                Button {
                    model.addDefaultGatewayHost()
                } label: {
                    Label("Use Default Gateway", systemImage: "network")
                }
                if let gateway = model.gatewayDetectionText {
                    Text(gateway)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

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
                        if isVisible {
                            (NSApp.delegate as? AppDelegate)?.showOverlay()
                        } else {
                            (NSApp.delegate as? AppDelegate)?.hideOverlay()
                        }
                    }
                ))
                SettingsToggleRow(systemImage: "pin.fill", tint: .orange, title: "Always on top", isOn: Binding(
                    get: { model.overlayAlwaysOnTop },
                    set: {
                        model.overlayAlwaysOnTop = $0
                        (NSApp.delegate as? AppDelegate)?.applyOverlayBehavior()
                    }
                ))
                SettingsToggleRow(systemImage: "arrow.up.left.and.arrow.down.right", tint: .purple, title: "Compact graph mode", isOn: Binding(
                    get: { model.overlayCompactMode },
                    set: {
                        (NSApp.delegate as? AppDelegate)?.setOverlayCompactMode($0)
                    }
                ))
                SettingsRow(systemImage: "slider.horizontal.3", tint: .teal, title: "Opacity") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.overlayOpacity },
                            set: {
                                model.overlayOpacity = $0
                                (NSApp.delegate as? AppDelegate)?.applyOverlayBehavior()
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
                        (NSApp.delegate as? AppDelegate)?.resetOverlayFrame()
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
                    (NSApp.delegate as? AppDelegate)?.showOverlay()
                } else {
                    (NSApp.delegate as? AppDelegate)?.hideOverlay()
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
        .frame(maxWidth: 660, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
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
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.displayName)
                        .font(.system(size: 14, weight: .semibold))
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
            }
            Spacer()
            Button("Edit") {
                onSelect()
            }
            .buttonStyle(.bordered)
            Button("Primary") {
                onMakePrimary()
            }
            .buttonStyle(.bordered)
            .disabled(isPrimary)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

    var body: some View {
        Table(Array(samples)) {
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
        .frame(height: 140)
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

            graphCanvas(scale: scale)

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

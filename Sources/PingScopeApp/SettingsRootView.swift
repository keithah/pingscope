import AppKit
import PingScopeCore
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: PingScopeModel
    @EnvironmentObject private var softwareUpdateController: SoftwareUpdateController
    @State private var selectedSettingsTab: String
    @State private var showsAdvancedNotificationThresholds = false

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
            Button("Quit PingScope") {
                NSApp.terminate(nil)
            }
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

                LazyVStack(spacing: 8) {
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
                            Text("Auto: \(model.draftHost.effectiveNetworkTier.settingsName)").tag(Self.autoNetworkTierSelection)
                            Divider()
                            ForEach(NetworkTier.allCases, id: \.self) { tier in
                                Text(tier.settingsName).tag(tier.rawValue)
                            }
                        }
                            .labelsHidden()
                            .frame(maxWidth: 220)
                            Text(model.draftHost.effectiveNetworkTier.helpText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 340, alignment: .leading)
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
                SettingsRow(systemImage: "slider.horizontal.3", tint: .teal, title: "Window opacity") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.overlayOpacity },
                            set: {
                                model.overlayOpacity = $0
                                AppDelegate.shared?.applyWindowOpacity()
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
            SettingsSection("Delivery") {
                SettingsRow(systemImage: "bell.badge", tint: .red, title: "Permission") {
                    HStack(spacing: 10) {
                        Text(model.notificationPermissionState.displayName)
                            .foregroundStyle(model.notificationPermissionState == .denied ? .red : .secondary)
                        Button("Request") {
                            model.requestNotificationPermission()
                        }
                        .help("Request notification permission")
                        .disabled([
                            .authorized,
                            .provisional,
                            .requesting,
                            .unavailable
                        ].contains(model.notificationPermissionState))
                        Button("Test") {
                            model.sendTestNotification()
                        }
                        .help("Send a test notification")
                        .disabled(model.notificationPermissionState == .requesting || model.notificationPermissionState == .unavailable)
                        Button("Settings") {
                            model.openNotificationSettings()
                        }
                        .help("Open macOS notification settings")
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
            }

            SettingsSection("Alert Style") {
                HStack(spacing: 10) {
                    Picker("Alert Style", selection: notificationAlertStyleBinding) {
                        ForEach(NotificationAlertStyle.presetCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                    if model.notificationRules.alertStyle == .custom {
                        Text("Custom")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(model.notificationRules.alertStyle.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }

            SettingsSection("What Triggers Alerts") {
                alertTriggerGroup(
                    title: "Availability",
                    detail: "Host down and recovery.",
                    rows: [
                        ("Host down", alertBinding(.hostDown)),
                        ("Recovery", recoveryAlertBinding)
                    ]
                )
                alertTriggerGroup(
                    title: "Network path",
                    detail: "Router, ISP, internet, and remote service failures.",
                    rows: [
                        ("Local network down", alertBinding(.localNetworkDown)),
                        ("ISP path down", alertBinding(.ispPathDown)),
                        ("Internet path down", alertBinding(.upstreamDown)),
                        ("Remote service down", alertBinding(.remoteServiceDown))
                    ]
                )
                alertTriggerGroup(
                    title: "Performance",
                    detail: "Sustained latency, total internet loss, and degraded paths.",
                    rows: [
                        ("High latency", alertBinding(.highLatency)),
                        ("Internet loss", alertBinding(.internetLoss)),
                        ("Path degraded", alertBinding(.pathDegraded))
                    ]
                )
                alertTriggerGroup(
                    title: "Network changes",
                    detail: "Interface, gateway, and connectivity state changes.",
                    rows: [
                        ("Network change", alertBinding(.networkChange))
                    ]
                )
            }

            SettingsSection("Network Status Colors") {
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

            SettingsSection("Advanced") {
                DisclosureGroup(isExpanded: $showsAdvancedNotificationThresholds) {
                    VStack(alignment: .leading, spacing: 8) {
                        notificationThresholdRows
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Thresholds")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(thresholdSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var notificationAlertStyleBinding: Binding<NotificationAlertStyle> {
        Binding(
            get: { model.notificationRules.alertStyle },
            set: { style in model.notificationRules.apply(style: style) }
        )
    }

    private var recoveryAlertBinding: Binding<Bool> {
        Binding(
            get: { model.notificationRules.notifyOnRecovery && model.notificationRules.alertTypes.contains(.recovered) },
            set: {
                model.notificationRules.notifyOnRecovery = $0
                model.setAlertType(.recovered, enabled: $0)
            }
        )
    }

    private var thresholdSummary: String {
        "\(Int(model.notificationRules.latencyThreshold.milliseconds.rounded()))ms x \(model.notificationRules.highLatencyConsecutiveSamples) pings"
    }

    private var notificationThresholdRows: some View {
        Group {
            SettingsRow(systemImage: "speedometer", tint: .yellow, title: "High latency") {
                UnitNumberField(value: Binding(
                    get: { model.notificationRules.latencyThreshold.milliseconds },
                    set: { model.notificationRules.latencyThreshold = .milliseconds($0) }
                ), unit: "ms", width: 82)
            }
            SettingsRow(systemImage: "number", tint: .yellow, title: "High latency after") {
                Stepper(
                    "\(model.notificationRules.highLatencyConsecutiveSamples) pings",
                    value: Binding(
                        get: { model.notificationRules.highLatencyConsecutiveSamples },
                        set: { model.notificationRules.highLatencyConsecutiveSamples = max(1, $0) }
                    ),
                    in: 1...20
                )
                .frame(width: 150, alignment: .trailing)
            }
            SettingsRow(systemImage: "timer", tint: .blue, title: "Cooldown") {
                UnitNumberField(value: Binding(
                    get: { model.notificationRules.cooldown.seconds },
                    set: { model.notificationRules.cooldown = .seconds($0) }
                ), unit: "sec", width: 82)
            }
            SettingsRow(systemImage: "wifi.slash", tint: .orange, title: "Internet loss at") {
                Stepper(
                    "\(Int(model.notificationRules.internetLossFailureRatio * 100))% failed",
                    value: Binding(
                        get: { model.notificationRules.internetLossFailureRatio },
                        set: { model.notificationRules.internetLossFailureRatio = min(max($0, 0.1), 1.0) }
                    ),
                    in: 0.5...1.0,
                    step: 0.25
                )
                .frame(width: 160, alignment: .trailing)
            }
            SettingsRow(systemImage: "point.3.connected.trianglepath.dotted", tint: .orange, title: "Path confidence") {
                Picker("Path confidence", selection: $model.notificationRules.diagnosisSensitivity) {
                    ForEach(DiagnosisAlertSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.displayName).tag(sensitivity)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            SettingsRow(systemImage: "waveform.path.ecg", tint: .yellow, title: "Path degraded after") {
                Stepper(
                    "\(model.notificationRules.pathDegradedConsecutiveSamples) diagnoses",
                    value: Binding(
                        get: { model.notificationRules.pathDegradedConsecutiveSamples },
                        set: { model.notificationRules.pathDegradedConsecutiveSamples = max(1, $0) }
                    ),
                    in: 1...20
                )
                .frame(width: 170, alignment: .trailing)
            }
        }
    }

    private func alertTriggerGroup(
        title: String,
        detail: String,
        rows: [(String, Binding<Bool>)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("\(rows.filter { $0.1.wrappedValue }.count)/\(rows.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    Toggle(row.0, isOn: row.1)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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


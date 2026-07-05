import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var notifications: some View {
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
        let selectedCount = rows.reduce(0) { count, row in
            count + (row.1.wrappedValue ? 1 : 0)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("\(selectedCount)/\(rows.count)")
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

}

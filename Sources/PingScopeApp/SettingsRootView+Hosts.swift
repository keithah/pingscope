import AppKit
import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var hosts: some View {
        SettingsPane {
            SettingsSection("Monitored Hosts") {
                HStack(spacing: 10) {
                    Text("\(model.configuredHosts.count) configured")
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

                LiveHostSettingsList(
                    liveDisplay: model.liveDisplay,
                    hosts: model.configuredHosts,
                    selectedHostID: model.editingHostID,
                    primaryHostID: model.configuredPrimaryHostID,
                    onSelect: model.selectHostForEditing,
                    onMakePrimary: model.setPrimaryHost,
                    onDelete: { hostID in
                        model.deleteHost(hostID)
                        if model.editingHostID == hostID {
                            model.clearDraftHost()
                        }
                    }
                )
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

                SettingsField("Appearance") {
                    HStack(spacing: 10) {
                        ColorPicker("Host Color", selection: displayColorSelection, supportsOpacity: false)
                            .labelsHidden()
                        Circle()
                            .fill(resolvedDraftDisplayColor)
                            .frame(width: 16, height: 16)
                        Text(model.draftDisplayColor == nil ? "Automatic Color" : "Custom Color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Use Automatic Color") {
                            model.draftDisplayColor = nil
                        }
                        .disabled(model.draftDisplayColor == nil)
                    }
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
                            SettingsField("Ping interval") {
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
                    NSApp.keyWindow?.makeFirstResponder(nil)
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

    private var displayColorSelection: Binding<Color> {
        Binding(
            get: { resolvedDraftDisplayColor },
            set: { color in
                if let displayColor = color.opaqueSRGBHostDisplayColor {
                    model.draftDisplayColor = displayColor
                }
            }
        )
    }

    private var resolvedDraftDisplayColor: Color {
        ResolvedHostDisplayColor(
            hostID: model.draftHostID,
            displayColor: model.draftDisplayColor
        ).swiftUIColor
    }

}

private extension Color {
    var opaqueSRGBHostDisplayColor: HostDisplayColor? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return HostDisplayColor(
            red: min(max(Double(converted.redComponent), 0), 1),
            green: min(max(Double(converted.greenComponent), 0), 1),
            blue: min(max(Double(converted.blueComponent), 0), 1)
        )
    }
}

private struct LiveHostSettingsList: View {
    @ObservedObject var liveDisplay: LiveDisplayModel
    let hosts: [HostConfig]
    let selectedHostID: UUID?
    let primaryHostID: UUID?
    let onSelect: (UUID) -> Void
    let onMakePrimary: (UUID) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(hosts) { host in
                HostSettingsRow(
                    host: host,
                    isSelected: selectedHostID == host.id,
                    isPrimary: primaryHostID == host.id,
                    statusColor: Color(
                        statusColor: liveDisplay.snapshot.healthByHost[host.id]?.status.statusColor ?? .gray
                    ),
                    onSelect: { onSelect(host.id) },
                    onMakePrimary: { onMakePrimary(host.id) },
                    onDelete: { onDelete(host.id) }
                )
            }
        }
    }
}

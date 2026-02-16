import SwiftUI

struct HostNotificationOverrideEditorView: View {
    let host: Host

    @Environment(\.dismiss) private var dismiss

    private let store: NotificationPreferencesStore

    @State private var state: HostNotificationOverrideState
    @State private var usesAlertTypeOverride: Bool
    @State private var globalAlertTypes: Set<AlertType>

    init(host: Host, store: NotificationPreferencesStore) {
        self.host = host
        self.store = store

        let initialState = store.hostOverrideState(for: host.id)
        let globalTypes = store.loadPreferences().enabledAlertTypes

        _state = State(initialValue: initialState)
        _usesAlertTypeOverride = State(initialValue: initialState.enabledAlertTypes != nil)
        _globalAlertTypes = State(initialValue: globalTypes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notification Overrides")
                .font(.title3.weight(.semibold))

            Text("\(host.name) (\(host.address))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Form {
                inheritanceSection

                if state.isUsingOverride {
                    hostSection
                    alertTypesSection
                }
            }
            .formStyle(.grouped)

            footer
        }
        .padding(16)
    }

    private var inheritanceSection: some View {
        Section("Mode") {
            Toggle("Use host-specific notification override", isOn: $state.isUsingOverride)
                .onChange(of: state.isUsingOverride) { isUsingOverride in
                    if !isUsingOverride {
                        usesAlertTypeOverride = false
                        state.enabledAlertTypes = nil
                    }
                }

            if !state.isUsingOverride {
                Text("This host inherits global notification enabled state and alert types.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hostSection: some View {
        Section("Host") {
            Toggle("Enable notifications for this host", isOn: $state.notificationsEnabled)
        }
    }

    private var alertTypesSection: some View {
        Section("Alert Types") {
            Toggle("Override alert types for this host", isOn: $usesAlertTypeOverride)
                .onChange(of: usesAlertTypeOverride) { isUsingOverride in
                    if isUsingOverride {
                        if state.enabledAlertTypes == nil {
                            state.enabledAlertTypes = globalAlertTypes
                        }
                    } else {
                        state.enabledAlertTypes = nil
                    }
                }

            if usesAlertTypeOverride {
                ForEach(AlertType.allCases, id: \.self) { alertType in
                    Toggle(alertType.displayName, isOn: alertTypeBinding(for: alertType))
                        .disabled(!globalAlertTypes.contains(alertType))
                }

                if globalAlertTypes.count < AlertType.allCases.count {
                    Text("Globally disabled alert types cannot be enabled at host level.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("This host uses global alert type selections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!state.notificationsEnabled)
    }

    private var footer: some View {
        HStack {
            Button("Reset to Global") {
                store.clearHostOverride(for: host.id)
                dismiss()
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }

            Button("Save") {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        guard state.isUsingOverride else {
            store.clearHostOverride(for: host.id)
            return
        }

        var stateToSave = state
        if !usesAlertTypeOverride {
            stateToSave.enabledAlertTypes = nil
        }
        stateToSave.hostID = host.id

        store.saveHostOverrideState(stateToSave)
    }

    private func alertTypeBinding(for alertType: AlertType) -> Binding<Bool> {
        Binding(
            get: {
                state.enabledAlertTypes?.contains(alertType) ?? false
            },
            set: { isEnabled in
                var enabledAlertTypes = state.enabledAlertTypes ?? []
                if isEnabled {
                    enabledAlertTypes.insert(alertType)
                } else {
                    enabledAlertTypes.remove(alertType)
                }
                state.enabledAlertTypes = enabledAlertTypes
            }
        )
    }
}

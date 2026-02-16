import SwiftUI

struct NotificationSettingsView: View {
    @State private var preferences: NotificationPreferences
    private let store: NotificationPreferencesStore

    init(store: NotificationPreferencesStore = NotificationPreferencesStore()) {
        self.store = store
        _preferences = State(initialValue: store.loadPreferences())
    }

    var body: some View {
        Form {
            generalSection
            alertTypesSection
            thresholdsSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: preferences) { newValue in
            store.savePreferences(newValue)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Enable Notifications", isOn: binding(for: \NotificationPreferences.globalEnabled))

            if preferences.globalEnabled {
                HStack {
                    Text("Cooldown Period")
                    Spacer()
                    Picker("", selection: binding(for: \NotificationPreferences.cooldownSeconds)) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var alertTypesSection: some View {
        Section("Alert Types") {
            ForEach(AlertType.allCases, id: \.self) { alertType in
                Toggle(alertType.displayName, isOn: bindingForAlertType(alertType))
            }
        }
        .disabled(!preferences.globalEnabled)
    }

    private var thresholdsSection: some View {
        Section("Thresholds") {
            HStack {
                Text("High Latency Threshold")
                Spacer()
                TextField("ms", value: binding(for: \NotificationPreferences.highLatencyThresholdMS), format: .number)
                    .frame(width: 60)
                Text("ms")
            }

            HStack {
                Text("Degradation Threshold")
                Spacer()
                TextField("%", value: binding(for: \NotificationPreferences.degradationPercentage), format: .number)
                    .frame(width: 60)
                Text("%")
            }

            Stepper(
                "Intermittent: \(preferences.intermittentFailureCount) failures in \(preferences.intermittentWindowSize) seconds",
                value: binding(for: \NotificationPreferences.intermittentFailureCount),
                in: 2 ... 10
            )

            Stepper(
                "Intermittent Window: \(preferences.intermittentWindowSize) seconds",
                value: binding(for: \NotificationPreferences.intermittentWindowSize),
                in: 30 ... 600,
                step: 10
            )
        }
        .disabled(!preferences.globalEnabled)
    }

    private func binding<Value>(for keyPath: WritableKeyPath<NotificationPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { newValue in
                preferences[keyPath: keyPath] = newValue
            }
        )
    }

    private func bindingForAlertType(_ alertType: AlertType) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledAlertTypes.contains(alertType) },
            set: { isEnabled in
                if isEnabled {
                    preferences.enabledAlertTypes.insert(alertType)
                } else {
                    preferences.enabledAlertTypes.remove(alertType)
                }
            }
        )
    }
}

import Foundation

struct HostNotificationOverrideState: Sendable, Equatable {
    var hostID: UUID
    var isUsingOverride: Bool
    var notificationsEnabled: Bool
    var enabledAlertTypes: Set<AlertType>?

    init(
        hostID: UUID,
        isUsingOverride: Bool,
        notificationsEnabled: Bool,
        enabledAlertTypes: Set<AlertType>?
    ) {
        self.hostID = hostID
        self.isUsingOverride = isUsingOverride
        self.notificationsEnabled = notificationsEnabled
        self.enabledAlertTypes = enabledAlertTypes
    }
}

final class NotificationPreferencesStore {
    private let userDefaults: UserDefaults
    private let preferencesKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "notifications.preferences",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        preferencesKey = key
        self.encoder = encoder
        self.decoder = decoder
    }

    func loadPreferences() -> NotificationPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? decoder.decode(NotificationPreferences.self, from: data)
        else {
            return NotificationPreferences()
        }

        return preferences
    }

    func savePreferences(_ preferences: NotificationPreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }

        userDefaults.set(data, forKey: preferencesKey)
    }

    func reset() {
        userDefaults.removeObject(forKey: preferencesKey)
    }

    var globalEnabled: Bool {
        get { loadPreferences().globalEnabled }
        set {
            updatePreferences { preferences in
                preferences.globalEnabled = newValue
            }
        }
    }

    var cooldownSeconds: TimeInterval {
        get { loadPreferences().cooldownSeconds }
        set {
            updatePreferences { preferences in
                preferences.cooldownSeconds = newValue
            }
        }
    }

    func updatePreferences(_ transform: (inout NotificationPreferences) -> Void) {
        var preferences = loadPreferences()
        transform(&preferences)
        savePreferences(preferences)
    }

    func hostOverride(for hostID: UUID) -> HostNotificationOverride? {
        loadPreferences().hostOverrides[hostID]
    }

    func hostOverrideState(for hostID: UUID) -> HostNotificationOverrideState {
        guard let override = hostOverride(for: hostID) else {
            return HostNotificationOverrideState(
                hostID: hostID,
                isUsingOverride: false,
                notificationsEnabled: true,
                enabledAlertTypes: nil
            )
        }

        return HostNotificationOverrideState(
            hostID: hostID,
            isUsingOverride: true,
            notificationsEnabled: override.enabled,
            enabledAlertTypes: override.enabledAlertTypes
        )
    }

    func saveHostOverrideState(_ state: HostNotificationOverrideState) {
        guard state.isUsingOverride else {
            clearHostOverride(for: state.hostID)
            return
        }

        let hostOverride = HostNotificationOverride(
            hostID: state.hostID,
            enabled: state.notificationsEnabled,
            enabledAlertTypes: state.enabledAlertTypes
        )
        setHostOverride(hostOverride)
    }

    func setHostOverride(_ override: HostNotificationOverride) {
        updatePreferences { preferences in
            preferences.hostOverrides[override.hostID] = override
        }
    }

    func clearHostOverride(for hostID: UUID) {
        removeHostOverride(for: hostID)
    }

    func removeHostOverride(for hostID: UUID) {
        updatePreferences { preferences in
            preferences.hostOverrides.removeValue(forKey: hostID)
        }
    }
}

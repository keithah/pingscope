import Foundation

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

    func setHostOverride(_ override: HostNotificationOverride) {
        updatePreferences { preferences in
            preferences.hostOverrides[override.hostID] = override
        }
    }

    func removeHostOverride(for hostID: UUID) {
        updatePreferences { preferences in
            preferences.hostOverrides.removeValue(forKey: hostID)
        }
    }
}

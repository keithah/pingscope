import Foundation

final class DisplayPreferencesStore {
    private let userDefaults: UserDefaults
    private let preferencesKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "display.preferences",
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        preferencesKey = "\(keyPrefix).payload"
        self.encoder = encoder
        self.decoder = decoder
    }

    func loadPreferences() -> DisplayPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey),
              let preferences = try? decoder.decode(DisplayPreferences.self, from: data)
        else {
            return DisplayPreferences()
        }

        return preferences
    }

    func savePreferences(_ preferences: DisplayPreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }

        userDefaults.set(data, forKey: preferencesKey)
    }

    var sharedState: DisplaySharedState {
        get { loadPreferences().shared }
        set {
            var preferences = loadPreferences()
            preferences.shared = newValue
            savePreferences(preferences)
        }
    }

    func updateSharedState(_ transform: (inout DisplaySharedState) -> Void) {
        var preferences = loadPreferences()
        transform(&preferences.shared)
        savePreferences(preferences)
    }

    func modeState(for mode: DisplayMode) -> DisplayModeState {
        loadPreferences().modeState(for: mode)
    }

    func setModeState(_ state: DisplayModeState, for mode: DisplayMode) {
        var preferences = loadPreferences()
        preferences.setModeState(state, for: mode)
        savePreferences(preferences)
    }

    func updateModeState(for mode: DisplayMode, _ transform: (inout DisplayModeState) -> Void) {
        var preferences = loadPreferences()
        var state = preferences.modeState(for: mode)
        transform(&state)
        preferences.setModeState(state, for: mode)
        savePreferences(preferences)
    }
}

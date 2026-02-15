import Foundation

final class ModePreferenceStore {
    private let userDefaults: UserDefaults
    private let compactModeKey: String
    private let stayOnTopKey: String

    init(userDefaults: UserDefaults = .standard, keyPrefix: String = "menuBar.mode") {
        self.userDefaults = userDefaults
        compactModeKey = "\(keyPrefix).compact"
        stayOnTopKey = "\(keyPrefix).stayOnTop"
    }

    var isCompactModeEnabled: Bool {
        get { userDefaults.bool(forKey: compactModeKey) }
        set { userDefaults.set(newValue, forKey: compactModeKey) }
    }

    var displayMode: DisplayMode {
        get { isCompactModeEnabled ? .compact : .full }
        set { isCompactModeEnabled = (newValue == .compact) }
    }

    var isStayOnTopEnabled: Bool {
        get { userDefaults.bool(forKey: stayOnTopKey) }
        set { userDefaults.set(newValue, forKey: stayOnTopKey) }
    }

    func setDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
    }

    func setStayOnTopEnabled(_ isEnabled: Bool) {
        isStayOnTopEnabled = isEnabled
    }
}

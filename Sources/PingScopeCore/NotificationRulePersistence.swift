import Foundation

public extension UserDefaults {
    var notificationRules: NotificationRuleSet? {
        get {
            guard let data = data(forKey: "notificationRules") else { return nil }
            return try? JSONDecoder().decode(NotificationRuleSet.self, from: data)
        }
        set {
            if let data = try? newValue.map(JSONEncoder().encode) {
                set(data, forKey: "notificationRules")
            } else {
                removeObject(forKey: "notificationRules")
            }
        }
    }
}

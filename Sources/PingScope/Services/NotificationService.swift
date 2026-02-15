import Foundation
import UserNotifications

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let preferencesStore: NotificationPreferencesStore
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init(preferencesStore: NotificationPreferencesStore) {
        self.preferencesStore = preferencesStore
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            _ = await checkAuthorizationStatus()
            return granted
        } catch {
            _ = await checkAuthorizationStatus()
            return false
        }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        return authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    func sendNotification(
        title: String,
        body: String,
        identifier: String,
        for alertType: AlertType
    ) async throws {
        let preferences = preferencesStore.loadPreferences()
        guard preferences.globalEnabled else {
            return
        }

        guard preferences.enabledAlertTypes.contains(alertType) else {
            return
        }

        let status = await checkAuthorizationStatus()
        guard status == .authorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func removeDeliveredNotification(identifier: String) async {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

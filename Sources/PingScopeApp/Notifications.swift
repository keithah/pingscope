import Foundation
import PingScopeCore
@preconcurrency import UserNotifications

enum NotificationPermissionState: String {
    case notDetermined
    case unavailable
    case requesting
    case authorized
    case denied
    case provisional
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined: "Not Requested"
        case .unavailable: "Unavailable"
        case .requesting: "Requesting..."
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .unknown: "Unknown"
        }
    }
}

final class MacNotificationDispatcher: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private var center: UNUserNotificationCenter?

    override init() {
        super.init()
    }

    func deliver(_ decision: AlertDecision, hosts: [HostConfig]) async {
        guard await ensureAuthorization() else { return }
        guard let center = notificationCenterIfAvailable() else { return }

        let content = UNMutableNotificationContent()
        let message = NotificationMessage(decision: decision, hosts: hosts)
        content.title = message.title
        content.body = message.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pingscope-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            return
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func permissionState() async -> NotificationPermissionState {
        guard let center = notificationCenterIfAvailable() else { return .unavailable }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            return .authorized
        case .provisional, .ephemeral:
            return .provisional
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    func requestAuthorization() async -> Bool {
        guard let center = notificationCenterIfAvailable() else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func sendTestNotification() async -> Bool {
        guard await ensureAuthorization() else { return false }
        guard let center = notificationCenterIfAvailable() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "PingScope Notifications"
        content.body = "This is a test notification from PingScope."
        content.sound = .default
        content.threadIdentifier = "pingscope-test"
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "pingscope-test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func ensureAuthorization() async -> Bool {
        guard let center = notificationCenterIfAvailable() else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationCenterIfAvailable() -> UNUserNotificationCenter? {
        if let center {
            return center
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }

        let created = UNUserNotificationCenter.current()
        created.delegate = self
        center = created
        return created
    }
}

private struct NotificationMessage {
    let title: String
    let body: String

    init(decision: AlertDecision, hosts: [HostConfig]) {
        switch decision {
        case let .hostDown(hostID):
            let name = Self.hostName(hostID, in: hosts)
            title = "\(name) is down"
            body = "PingScope has reached the configured failure threshold."
        case let .recovered(hostID):
            let name = Self.hostName(hostID, in: hosts)
            title = "\(name) recovered"
            body = "Latency measurements are receiving responses again."
        case let .highLatency(hostID):
            let name = Self.hostName(hostID, in: hosts)
            title = "High latency on \(name)"
            body = "Latency crossed the configured notification threshold."
        case let .networkChange(previousGateway, currentGateway):
            title = "Network changed"
            body = "Gateway changed from \(previousGateway ?? "none") to \(currentGateway ?? "none")."
        case .internetLoss:
            title = "Internet connection lost"
            body = "All enabled hosts are currently failing."
        case let .networkStatus(status):
            title = status.displayName
            body = "PingScope detected a network status change."
        }
    }

    private static func hostName(_ id: UUID, in hosts: [HostConfig]) -> String {
        hosts.first { $0.id == id }?.displayName ?? "Host"
    }
}

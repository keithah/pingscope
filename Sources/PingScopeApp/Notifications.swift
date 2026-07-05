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
    // The dispatcher's nonisolated async methods run concurrently; `center` is
    // the only mutable state, so the lock is what makes @unchecked Sendable true.
    private let centerLock = NSLock()
    private var center: UNUserNotificationCenter?
    private let logger: (@Sendable (String) -> Void)?

    init(logger: (@Sendable (String) -> Void)? = DebugLog.write) {
        self.logger = logger
        super.init()
    }

    func deliver(_ decision: AlertDecision, hosts: [HostConfig]) async {
        await deliver([decision], hosts: hosts)
    }

    func deliver(_ decisions: [AlertDecision], hosts: [HostConfig]) async {
        guard !decisions.isEmpty else { return }
        guard await ensureAuthorization() else { return }
        guard let center = notificationCenterIfAvailable() else { return }

        await withTaskGroup(of: Void.self) { group in
            for decision in decisions {
                group.addTask { [logger] in
                    do {
                        try await center.add(Self.notificationRequest(for: decision, hosts: hosts))
                    } catch {
                        logger?("notification delivery failed alert=\(decision) error=\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private static func notificationRequest(for decision: AlertDecision, hosts: [HostConfig]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let message = NotificationMessage(decision: decision, hosts: hosts)
        content.title = message.title
        content.body = message.body
        content.sound = .default

        return UNNotificationRequest(
            identifier: "pingscope-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
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
            logger?("test notification delivery failed error=\(error.localizedDescription)")
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
        centerLock.lock()
        defer { centerLock.unlock() }
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
        let hostNameByID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.id, $0.displayName) })
        func hostName(_ id: UUID) -> String {
            hostNameByID[id] ?? "Host"
        }

        switch decision {
        case let .hostDown(hostID):
            let name = hostName(hostID)
            title = "\(name) is down"
            body = "PingScope has reached the configured failure threshold."
        case let .recovered(hostID):
            let name = hostName(hostID)
            title = "\(name) recovered"
            body = "Latency measurements are receiving responses again."
        case let .highLatency(hostID):
            let name = hostName(hostID)
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
        case .localNetworkDown:
            title = "Local network down"
            body = "PingScope thinks the router or local gateway is the failing boundary."
        case .ispPathDown:
            title = "ISP path down"
            body = "The local gateway responds, but the ISP or modem path does not."
        case .upstreamDown:
            title = "Internet path down"
            body = "Local connectivity is available, but upstream internet checks are failing."
        case let .remoteServiceDown(hostIDs):
            let names = hostIDs.prefix(3).map(hostName).joined(separator: ", ")
            let extra = hostIDs.count > 3 ? ", +\(hostIDs.count - 3) more" : ""
            title = hostIDs.count == 1 ? "\(names) is unreachable" : "Remote services unreachable"
            body = "\(names)\(extra) failed while inner network checks were reachable."
        case let .pathDegraded(tier):
            title = "\(tier.settingsName) degraded"
            body = "PingScope detected slow or unreliable responses on this part of the path."
        case .pathRecovered:
            title = "Network path recovered"
            body = "PingScope measurements are reachable again."
        }
    }
}

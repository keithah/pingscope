import Foundation
import UserNotifications

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    private let preferencesStore: NotificationPreferencesStore
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var alertStates: [UUID: HostAlertState] = [:]
    private var previousGatewayIP: String? = nil
    private var lastNetworkChangeAlert: Date? = nil
    private var lastInternetLossAlert: Date? = nil

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

    func evaluateResult(_ result: PingResult, for host: Host, isHostUp: Bool) async {
        let preferences = preferencesStore.loadPreferences()
        guard preferences.globalEnabled else {
            return
        }

        let override = preferences.hostOverrides[host.id]
        guard override?.enabled ?? true else {
            return
        }

        let effectiveAlertTypes: Set<AlertType> = {
            guard let overrideTypes = override?.enabledAlertTypes else {
                return preferences.enabledAlertTypes
            }

            return preferences.enabledAlertTypes.intersection(overrideTypes)
        }()

        var state = alertStates[host.id] ?? HostAlertState()
        let detected = AlertDetector.evaluate(
            result: result,
            host: host,
            isHostUp: isHostUp,
            state: &state,
            preferences: preferences
        )

        let cooldown = preferences.cooldownSeconds
        let latencyMS = result.latency.map(Self.durationToMilliseconds)

        for alertType in detected {
            guard effectiveAlertTypes.contains(alertType) else {
                continue
            }

            guard state.canSendAlert(alertType, cooldown: cooldown) else {
                continue
            }

            let identifier = "host.\(host.id.uuidString).\(alertType.rawValue)"
            let title = alertType.displayName
            let body = alertBody(for: alertType, host: host, latencyMS: latencyMS)

            do {
                try await sendNotification(title: title, body: body, identifier: identifier, for: alertType)
                state.recordAlertSent(alertType)
            } catch {
                // Intentionally ignore delivery errors; detection state is still updated.
            }
        }

        alertStates[host.id] = state
    }

    func evaluateGatewayChange(from previous: String?, to current: String?) async {
        previousGatewayIP = current

        let preferences = preferencesStore.loadPreferences()
        guard preferences.globalEnabled else {
            return
        }

        guard preferences.enabledAlertTypes.contains(.networkChange) else {
            return
        }

        guard let alertType = AlertDetector.detectNetworkChange(previousGateway: previous, currentGateway: current) else {
            return
        }

        if let lastNetworkChangeAlert,
           Date().timeIntervalSince(lastNetworkChangeAlert) < preferences.cooldownSeconds
        {
            return
        }

        let title = alertType.displayName
        let body = "Gateway changed from \(previous ?? "unknown") to \(current ?? "unknown")."

        do {
            try await sendNotification(title: title, body: body, identifier: "network.gateway.change", for: alertType)
            lastNetworkChangeAlert = Date()
        } catch {
            // Ignore delivery errors; re-evaluation will occur on next gateway update.
        }
    }

    func evaluateInternetLoss(hostResults: [(Host, Bool)]) async {
        let preferences = preferencesStore.loadPreferences()
        guard preferences.globalEnabled else {
            return
        }

        guard preferences.enabledAlertTypes.contains(.internetLoss) else {
            return
        }

        let allHostResults = hostResults.map { (host: $0.0, isUp: $0.1) }
        guard let alertType = AlertDetector.detectInternetLoss(allHostResults: allHostResults) else {
            return
        }

        if let lastInternetLossAlert,
           Date().timeIntervalSince(lastInternetLossAlert) < preferences.cooldownSeconds
        {
            return
        }

        let title = alertType.displayName
        let body = "All monitored hosts are reporting failures."

        do {
            try await sendNotification(title: title, body: body, identifier: "internet.loss", for: alertType)
            lastInternetLossAlert = Date()
        } catch {
            // Ignore delivery errors; this is a best-effort user-facing alert.
        }
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

    private func alertBody(for alertType: AlertType, host: Host, latencyMS: Double?) -> String {
        switch alertType {
        case .noResponse:
            return "No response from \(host.name) (\(host.address))."
        case .highLatency:
            if let latencyMS {
                return "Latency \(Int(latencyMS.rounded()))ms for \(host.name)."
            }
            return "High latency detected for \(host.name)."
        case .recovery:
            return "\(host.name) is responding again."
        case .degradation:
            if let latencyMS {
                return "Latency degraded to \(Int(latencyMS.rounded()))ms for \(host.name)."
            }
            return "Latency degradation detected for \(host.name)."
        case .intermittent:
            return "Intermittent failures detected for \(host.name)."
        case .networkChange:
            return "Network configuration changed."
        case .internetLoss:
            return "Internet connectivity appears down."
        }
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
        let fractionalSeconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return (seconds + fractionalSeconds) * 1000
    }
}

import Foundation

struct HostNotificationOverride: Codable, Sendable, Equatable {
    var hostID: UUID
    var enabled: Bool
    var enabledAlertTypes: Set<AlertType>?

    init(
        hostID: UUID,
        enabled: Bool = true,
        enabledAlertTypes: Set<AlertType>? = nil
    ) {
        self.hostID = hostID
        self.enabled = enabled
        self.enabledAlertTypes = enabledAlertTypes
    }
}

struct NotificationPreferences: Codable, Sendable, Equatable {
    var globalEnabled: Bool
    var cooldownSeconds: TimeInterval
    var enabledAlertTypes: Set<AlertType>
    var highLatencyThresholdMS: Double
    var degradationPercentage: Double
    var intermittentFailureCount: Int
    var intermittentWindowSize: Int
    var hostOverrides: [UUID: HostNotificationOverride]

    init(
        globalEnabled: Bool = true,
        cooldownSeconds: TimeInterval = 60,
        enabledAlertTypes: Set<AlertType> = Set(AlertType.allCases),
        highLatencyThresholdMS: Double = 200,
        degradationPercentage: Double = 50,
        intermittentFailureCount: Int = 3,
        intermittentWindowSize: Int = 10,
        hostOverrides: [UUID: HostNotificationOverride] = [:]
    ) {
        self.globalEnabled = globalEnabled
        self.cooldownSeconds = cooldownSeconds
        self.enabledAlertTypes = enabledAlertTypes
        self.highLatencyThresholdMS = highLatencyThresholdMS
        self.degradationPercentage = degradationPercentage
        self.intermittentFailureCount = intermittentFailureCount
        self.intermittentWindowSize = intermittentWindowSize
        self.hostOverrides = hostOverrides
    }
}

import Foundation
import PingScopeCore

public struct PingScopeIOSHostDraft: Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var address: String
    public var method: PingMethod
    public var portText: String
    public var intervalMilliseconds: Double
    public var timeoutMilliseconds: Double
    public var degradedMilliseconds: Double
    public var downAfterFailures: Int
    public var isEnabled: Bool
    public var notifications: HostNotificationPolicy
    public var displayColor: HostDisplayColor?

    public init(host: HostConfig) {
        self.id = host.id
        self.displayName = host.displayName
        self.address = host.address
        self.method = host.method
        self.portText = host.port.map(String.init) ?? ""
        self.intervalMilliseconds = host.interval.seconds * 1_000
        self.timeoutMilliseconds = host.timeout.seconds * 1_000
        self.degradedMilliseconds = host.thresholds.degradedMilliseconds
        self.downAfterFailures = host.thresholds.downAfterFailures
        self.isEnabled = host.isEnabled
        self.notifications = host.notifications
        self.displayColor = host.displayColor?.validatedComponents
    }

    public var finalizedHost: HostConfig {
        HostConfig(
            id: id,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            method: method,
            port: UInt16(portText),
            interval: .milliseconds(intervalMilliseconds),
            timeout: .milliseconds(timeoutMilliseconds),
            thresholds: LatencyThresholds(
                degradedMilliseconds: degradedMilliseconds,
                downAfterFailures: downAfterFailures
            ),
            isEnabled: isEnabled,
            notifications: notifications,
            displayColor: displayColor?.validatedComponents
        )
    }

    public var validationErrors: [HostValidationError] {
        finalizedHost.validationErrors
    }

    public var canSave: Bool {
        validationErrors.isEmpty
    }

    public var usesAutomaticDisplayColor: Bool {
        displayColor == nil
    }

    public mutating func apply(method: PingMethod) {
        self.method = method
        self.portText = method.defaultPort.map(String.init) ?? ""
    }
}

import Foundation
import PingScopeCore

public protocol PingScopeCloudSyncControlling: Sendable {
    func setEnabled(_ enabled: Bool, hosts: [HostConfig]) async
    func status() async -> PingScopeCloudSyncStatus
}

extension PingScopeCloudSyncService: PingScopeCloudSyncControlling {}

public struct PingScopeCloudSyncActivationState: Equatable, Sendable {
    public let isEnabled: Bool
    public let statusText: String

    public init(isEnabled: Bool, statusText: String) {
        self.isEnabled = isEnabled
        self.statusText = statusText
    }
}

public actor PingScopeCloudSyncActivationController {
    public static let defaultMaximumAutomaticStartFailures = 3

    private let service: any PingScopeCloudSyncControlling
    private let defaults: UserDefaults
    private let maximumAutomaticStartFailures: Int

    public init(
        service: any PingScopeCloudSyncControlling,
        defaultsSuiteName: String? = nil,
        maximumAutomaticStartFailures: Int = defaultMaximumAutomaticStartFailures
    ) {
        self.service = service
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.maximumAutomaticStartFailures = max(1, maximumAutomaticStartFailures)
    }

    public func activatePersisted(hosts: [HostConfig]) async -> PingScopeCloudSyncActivationState {
        guard PingScopeCloudSyncPreference.isEnabled(in: defaults) else {
            await service.setEnabled(false, hosts: hosts)
            return PingScopeCloudSyncActivationState(isEnabled: false, statusText: "Off")
        }
        let failureCount = defaults.integer(
            forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey
        )
        guard failureCount < maximumAutomaticStartFailures else {
            defaults.set(false, forKey: PingScopeCloudSyncPreference.enabledKey)
            await service.setEnabled(false, hosts: hosts)
            return PingScopeCloudSyncActivationState(
                isEnabled: false,
                statusText: "iCloud sync stayed off after repeated startup failures. Turn it on again to retry."
            )
        }
        return await attemptEnable(hosts: hosts, recordsAutomaticFailure: true)
    }

    public func setEnabledByUser(
        _ enabled: Bool,
        hosts: [HostConfig]
    ) async -> PingScopeCloudSyncActivationState {
        guard enabled else {
            defaults.set(false, forKey: PingScopeCloudSyncPreference.enabledKey)
            await service.setEnabled(false, hosts: hosts)
            return PingScopeCloudSyncActivationState(isEnabled: false, statusText: "Off")
        }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        return await attemptEnable(hosts: hosts, recordsAutomaticFailure: false)
    }

    private func attemptEnable(
        hosts: [HostConfig],
        recordsAutomaticFailure: Bool
    ) async -> PingScopeCloudSyncActivationState {
        await service.setEnabled(true, hosts: hosts)
        let status = await service.status()
        switch status {
        case .idle, .syncing:
            defaults.set(0, forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey)
            defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
            return PingScopeCloudSyncActivationState(
                isEnabled: true,
                statusText: status == .syncing ? "Syncing…" : "Up to date"
            )
        case .accountUnavailable:
            return await parkDisabled(
                message: "Private iCloud account unavailable",
                hosts: hosts,
                recordsAutomaticFailure: recordsAutomaticFailure
            )
        case let .failed(message):
            return await parkDisabled(
                message: message,
                hosts: hosts,
                recordsAutomaticFailure: recordsAutomaticFailure
            )
        case .off, .checkingAccount:
            return await parkDisabled(
                message: "iCloud sync did not finish starting",
                hosts: hosts,
                recordsAutomaticFailure: recordsAutomaticFailure
            )
        }
    }

    private func parkDisabled(
        message: String,
        hosts: [HostConfig],
        recordsAutomaticFailure: Bool
    ) async -> PingScopeCloudSyncActivationState {
        if recordsAutomaticFailure {
            let current = defaults.integer(
                forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey
            )
            defaults.set(
                current + 1,
                forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey
            )
        }
        defaults.set(false, forKey: PingScopeCloudSyncPreference.enabledKey)
        await service.setEnabled(false, hosts: hosts)
        return PingScopeCloudSyncActivationState(
            isEnabled: false,
            statusText: "iCloud sync was turned off because it failed to start: \(message)"
        )
    }
}

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
    private var activationGeneration: UInt64 = 0

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
        activationGeneration &+= 1
        let generation = activationGeneration
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
        let prearmedFailureCount = failureCount + 1
        defaults.set(
            prearmedFailureCount,
            forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey
        )
        defaults.synchronize()
        return await attemptEnable(
            hosts: hosts,
            automaticFailureCount: prearmedFailureCount,
            generation: generation
        )
    }

    public func setEnabledByUser(
        _ enabled: Bool,
        hosts: [HostConfig]
    ) async -> PingScopeCloudSyncActivationState {
        activationGeneration &+= 1
        let generation = activationGeneration
        defaults.set(0, forKey: PingScopeCloudSyncPreference.automaticStartFailureCountKey)
        guard enabled else {
            defaults.set(false, forKey: PingScopeCloudSyncPreference.enabledKey)
            await service.setEnabled(false, hosts: hosts)
            return PingScopeCloudSyncActivationState(isEnabled: false, statusText: "Off")
        }
        defaults.set(true, forKey: PingScopeCloudSyncPreference.enabledKey)
        return await attemptEnable(
            hosts: hosts,
            automaticFailureCount: nil,
            generation: generation
        )
    }

    private func attemptEnable(
        hosts: [HostConfig],
        automaticFailureCount: Int?,
        generation: UInt64
    ) async -> PingScopeCloudSyncActivationState {
        await service.setEnabled(true, hosts: hosts)
        guard generation == activationGeneration else {
            return currentPersistedState()
        }
        let status = await service.status()
        guard generation == activationGeneration else {
            return currentPersistedState()
        }
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
                automaticFailureCount: automaticFailureCount,
                generation: generation
            )
        case let .failed(message):
            return await parkDisabled(
                message: message,
                hosts: hosts,
                automaticFailureCount: automaticFailureCount,
                generation: generation
            )
        case .off, .checkingAccount:
            return await parkDisabled(
                message: "iCloud sync did not finish starting",
                hosts: hosts,
                automaticFailureCount: automaticFailureCount,
                generation: generation
            )
        }
    }

    private func parkDisabled(
        message: String,
        hosts: [HostConfig],
        automaticFailureCount: Int?,
        generation: UInt64
    ) async -> PingScopeCloudSyncActivationState {
        guard generation == activationGeneration else {
            return currentPersistedState()
        }
        let reachedAutomaticFailureThreshold = automaticFailureCount.map {
            $0 >= maximumAutomaticStartFailures
        } ?? true
        defaults.set(
            !reachedAutomaticFailureThreshold,
            forKey: PingScopeCloudSyncPreference.enabledKey
        )
        await service.setEnabled(false, hosts: hosts)
        guard generation == activationGeneration else {
            return currentPersistedState()
        }
        let action = reachedAutomaticFailureThreshold
            ? "was turned off because it failed to start"
            : "is paused after a startup failure and will retry next launch"
        return PingScopeCloudSyncActivationState(
            isEnabled: false,
            statusText: "iCloud sync \(action): \(message)"
        )
    }

    private func currentPersistedState() -> PingScopeCloudSyncActivationState {
        let isEnabled = PingScopeCloudSyncPreference.isEnabled(in: defaults)
        return PingScopeCloudSyncActivationState(
            isEnabled: isEnabled,
            statusText: isEnabled ? "Checking iCloud account…" : "Off"
        )
    }
}

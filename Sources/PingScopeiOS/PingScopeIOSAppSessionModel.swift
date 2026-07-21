import Foundation
import PingScopeCore

public enum PingScopeIOSGatewayHostUpdateChange: Equatable, Sendable {
    case unavailable
    case unchanged
    case updated(index: Int, previousAddress: String)
    case created(index: Int)
}

public struct PingScopeIOSGatewayHostUpdate: Equatable, Sendable {
    public let hosts: [HostConfig]
    public let selectedHostID: UUID?
    public let change: PingScopeIOSGatewayHostUpdateChange

    public var affectedHost: HostConfig? {
        let index: Int? = switch change {
        case let .updated(index, _), let .created(index): index
        case .unavailable, .unchanged: nil
        }
        guard let index, hosts.indices.contains(index) else { return nil }
        return hosts[index]
    }
}

public enum PingScopeIOSAcceptedHostStateDisposition: Equatable, Sendable {
    case unavailable
    case focusedPreserved(LiveMonitorSessionSnapshot)
    case focusedRequiresReplacement(HostConfig)
    case allHosts([LiveMonitorSessionSnapshot])
}

public struct PingScopeIOSAcceptedHostStateReconciliation: Equatable, Sendable {
    public let hosts: [HostConfig]
    public let selectedHostID: UUID?
    public let disposition: PingScopeIOSAcceptedHostStateDisposition

    public init(
        hosts: [HostConfig],
        selectedHostID: UUID?,
        disposition: PingScopeIOSAcceptedHostStateDisposition
    ) {
        self.hosts = hosts
        self.selectedHostID = selectedHostID
        self.disposition = disposition
    }
}

/// The session-owning portion of the iOS app model. UIKit presentation state
/// passes through to this type so tests exercise the shipping lifecycle path.
@MainActor
public final class PingScopeIOSAppSessionModel {
    public let coordinator: PingScopeIOSMultiHostSessionCoordinator

    public init(coordinator: PingScopeIOSMultiHostSessionCoordinator) {
        self.coordinator = coordinator
    }

    /// Decides the persisted host-list mutation for a gateway detection while
    /// retaining the saved host identity, settings, order, and selection.
    public func gatewayHostUpdate(
        hosts: [HostConfig],
        selectedHostID: UUID?,
        detectedHost: HostConfig?,
        shouldCreateIfMissing: Bool,
        shouldSelect: Bool
    ) -> PingScopeIOSGatewayHostUpdate {
        guard let detectedHost else {
            return PingScopeIOSGatewayHostUpdate(
                hosts: hosts,
                selectedHostID: selectedHostID,
                change: .unavailable
            )
        }

        guard let index = hosts.firstIndex(where: \.isManagedDefaultGateway) else {
            guard shouldCreateIfMissing else {
                return PingScopeIOSGatewayHostUpdate(
                    hosts: hosts,
                    selectedHostID: selectedHostID,
                    change: .unchanged
                )
            }
            return PingScopeIOSGatewayHostUpdate(
                hosts: hosts + [detectedHost],
                selectedHostID: shouldSelect ? detectedHost.id : selectedHostID,
                change: .created(index: hosts.endIndex)
            )
        }

        let previousAddress = hosts[index].address
        guard previousAddress != detectedHost.address || shouldSelect else {
            return PingScopeIOSGatewayHostUpdate(
                hosts: hosts,
                selectedHostID: selectedHostID,
                change: .unchanged
            )
        }

        var updatedHosts = hosts
        updatedHosts[index].address = detectedHost.address
        return PingScopeIOSGatewayHostUpdate(
            hosts: updatedHosts,
            selectedHostID: shouldSelect ? updatedHosts[index].id : selectedHostID,
            change: .updated(index: index, previousAddress: previousAddress)
        )
    }

    @discardableResult
    public func switchToAllHosts(
        restartDuration: MonitorSessionDuration?,
        hosts: [HostConfig],
        beforeRestart: @MainActor () -> Void = {},
        isCurrentLifecycle: @MainActor () -> Bool = { true }
    ) async -> Bool {
        if restartDuration == nil {
            await coordinator.stop(reason: .completed)
            guard isCurrentLifecycle() else { return false }
        }
        await coordinator.reconcile(hosts: hosts)
        guard isCurrentLifecycle() else { return false }
        if let restartDuration {
            beforeRestart()
            await coordinator.start(duration: restartDuration)
            guard isCurrentLifecycle() else { return false }
        }
        return true
    }

    public func startMonitoring(
        scope: PingScopeIOSHostScope,
        duration: MonitorSessionDuration,
        hosts: [HostConfig],
        startFocusedController: @MainActor () async -> Void
    ) async {
        // An explicit Start always begins a fresh logical session, regardless
        // of the currently visible scope.
        await coordinator.stop(reason: .userStopped)
        if scope == .allHosts {
            await coordinator.reconcile(hosts: hosts)
            await coordinator.start(duration: duration)
        } else {
            await startFocusedController()
        }
    }

    public func stopMonitoring(
        scope: PingScopeIOSHostScope,
        reason: MonitorSessionEndReason,
        stopFocusedController: @MainActor () async -> Void
    ) async {
        if scope == .allHosts {
            await coordinator.stop(reason: reason)
        } else {
            await stopFocusedController()
            await coordinator.stop(reason: reason)
        }
    }

    /// Shipping focused-save seam: returns false when the caller must replace
    /// the controller because probe configuration changed.
    @discardableResult
    public func reconcileFocusedHostEdit(
        currentHost: HostConfig,
        updatedHost: HostConfig,
        controller: LiveMonitorSessionController
    ) async -> Bool {
        guard currentHost.id == updatedHost.id,
              currentHost.isEnabled == updatedHost.isEnabled,
              currentHost.hasSameProbeConfiguration(as: updatedHost) else {
            return false
        }
        return await controller.updatePresentationHost(updatedHost)
    }

    public func reconcileAcceptedHostState(
        _ state: SharedHostStoreState,
        currentHosts: [HostConfig],
        currentFocusedHostID: UUID,
        scope: PingScopeIOSHostScope,
        focusedController: LiveMonitorSessionController
    ) async -> PingScopeIOSAcceptedHostStateReconciliation {
        let acceptedHosts = HostConfig.sanitizedHosts(state.hosts)
        guard !acceptedHosts.isEmpty else {
            return PingScopeIOSAcceptedHostStateReconciliation(
                hosts: currentHosts,
                selectedHostID: currentFocusedHostID,
                disposition: .unavailable
            )
        }
        let selectedHost = acceptedHosts.first { $0.id == currentFocusedHostID }
            ?? state.selectedHostID.flatMap { selectedID in
                acceptedHosts.first { $0.id == selectedID }
            }
            ?? state.primaryHostID.flatMap { primaryID in
                acceptedHosts.first { $0.id == primaryID }
            }
            ?? acceptedHosts.first(where: \.isEnabled)
            ?? acceptedHosts[0]
        switch scope {
        case .focused:
            let currentSnapshot = await focusedController.snapshot()
            guard currentSnapshot.host.id == selectedHost.id,
                  currentSnapshot.host.isEnabled == selectedHost.isEnabled,
                  currentSnapshot.host.hasSameProbeConfiguration(as: selectedHost) else {
                return PingScopeIOSAcceptedHostStateReconciliation(
                    hosts: acceptedHosts,
                    selectedHostID: selectedHost.id,
                    disposition: .focusedRequiresReplacement(selectedHost)
                )
            }
            _ = await reconcileFocusedHostEdit(
                currentHost: currentSnapshot.host,
                updatedHost: selectedHost,
                controller: focusedController
            )
            return PingScopeIOSAcceptedHostStateReconciliation(
                hosts: acceptedHosts,
                selectedHostID: selectedHost.id,
                disposition: .focusedPreserved(await focusedController.snapshot())
            )
        case .allHosts:
            await coordinator.reconcile(hosts: acceptedHosts)
            return PingScopeIOSAcceptedHostStateReconciliation(
                hosts: acceptedHosts,
                selectedHostID: selectedHost.id,
                disposition: .allHosts(await coordinator.orderedSnapshots())
            )
        }
    }

    @discardableResult
    public func performLiveActivityScopeSwitch(
        isSessionActive: Bool,
        previousScope: PingScopeIOSHostScope,
        newScope: PingScopeIOSHostScope,
        previousFocusedHostID: UUID,
        newFocusedHostID: UUID,
        hasLiveActivity: Bool,
        prepareScopeSwitch: @MainActor () async -> Bool,
        endActivity: @MainActor () async -> Void,
        completeScopeSwitch: @MainActor () async -> Bool,
        resumeActivity: @MainActor () async -> Void
    ) async -> Bool {
        let decision = PingScopeIOSLiveActivityDecision.decide(
            isSessionActive: isSessionActive,
            previousScope: previousScope,
            newScope: newScope,
            previousFocusedHostID: previousFocusedHostID,
            newFocusedHostID: newFocusedHostID
        )
        guard await prepareScopeSwitch() else { return false }
        if decision != .update, hasLiveActivity {
            await endActivity()
        }
        guard await completeScopeSwitch() else { return false }
        if isSessionActive {
            await resumeActivity()
        }
        return true
    }
}

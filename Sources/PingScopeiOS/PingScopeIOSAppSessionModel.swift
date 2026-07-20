import Foundation
import PingScopeCore

/// The session-owning portion of the iOS app model. UIKit presentation state
/// passes through to this type so tests exercise the shipping lifecycle path.
@MainActor
public final class PingScopeIOSAppSessionModel {
    public let coordinator: PingScopeIOSMultiHostSessionCoordinator

    public init(coordinator: PingScopeIOSMultiHostSessionCoordinator) {
        self.coordinator = coordinator
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

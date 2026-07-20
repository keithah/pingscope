import PingScopeCore

/// Main-actor session decisions shared by `PingScopeIOSAppModel` and its
/// behavioral tests. Keeping these decisions here lets tests drive the exact
/// coordinator operations used by the shipping app without exposing UIKit.
@MainActor
public enum PingScopeIOSAppMonitoringOrchestration {
    public static func prepareAllHostsReturn(
        restartDuration: MonitorSessionDuration?,
        coordinator: PingScopeIOSMultiHostSessionCoordinator
    ) async {
        guard restartDuration == nil else { return }
        await coordinator.stop(reason: .completed)
    }

    public static func startMonitoring(
        scope: PingScopeIOSHostScope,
        duration: MonitorSessionDuration,
        hosts: [HostConfig],
        coordinator: PingScopeIOSMultiHostSessionCoordinator,
        startFocusedController: @MainActor () async -> Void
    ) async {
        if scope == .allHosts {
            await coordinator.reconcile(hosts: hosts)
            await coordinator.start(duration: duration)
        } else {
            await coordinator.stop(reason: .userStopped)
            await startFocusedController()
        }
    }

    public static func stopMonitoring(
        scope: PingScopeIOSHostScope,
        reason: MonitorSessionEndReason,
        coordinator: PingScopeIOSMultiHostSessionCoordinator,
        stopFocusedController: @MainActor () async -> Void
    ) async {
        if scope == .allHosts {
            await coordinator.stop(reason: reason)
        } else {
            await stopFocusedController()
            await coordinator.stop(reason: reason)
        }
    }
}

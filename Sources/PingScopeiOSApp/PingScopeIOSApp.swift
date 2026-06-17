import ActivityKit
import Combine
import PingScopeCore
import PingScopeiOS
import SwiftUI

@main
struct PingScopeIOSApp: App {
    @StateObject private var model = PingScopeIOSAppModel()

    var body: some Scene {
        WindowGroup {
            PingScopeIOSRootView(
                host: model.snapshot.host,
                session: model.snapshot.session,
                onStart: { duration in
                    model.start(duration: duration)
                },
                onStop: {
                    model.stop()
                }
            )
        }
    }
}

@MainActor
private final class PingScopeIOSAppModel: ObservableObject {
    @Published var snapshot: LiveMonitorSessionSnapshot

    private let controller: LiveMonitorSessionController
    private var refreshTask: Task<Void, Never>?
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?

    init() {
        let host = HostConfig.defaultInternet
        self.controller = LiveMonitorSessionController(host: host)
        self.snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
    }

    func start(duration: MonitorSessionDuration) {
        refreshTask?.cancel()
        Task {
            await controller.start(duration: duration)
            await refreshSnapshot()
            await startLiveActivity(duration: duration)
            startRefreshLoop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        Task {
            await controller.stop(reason: .userStopped)
            await refreshSnapshot()
            await endLiveActivity()
        }
    }

    private func startRefreshLoop() {
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshSnapshot()
                await updateLiveActivity()
                if snapshot.session?.phase() == .ended {
                    await endLiveActivity()
                    break
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshSnapshot() async {
        snapshot = await controller.snapshot()
    }

    private func startLiveActivity(duration: MonitorSessionDuration) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let session = snapshot.session else { return }

        do {
            let attributes = PingScopeLiveActivityAttributes(host: snapshot.host, duration: duration)
            let state = PingScopeLiveActivityAttributes.ContentState(
                session: session,
                health: snapshot.health
            )
            liveActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: session.scheduledEndAt),
                pushType: nil
            )
        } catch {
            liveActivity = nil
        }
    }

    private func updateLiveActivity() async {
        guard let liveActivity, let session = snapshot.session else { return }
        let state = PingScopeLiveActivityAttributes.ContentState(
            session: session,
            health: snapshot.health
        )
        await liveActivity.update(ActivityContent(state: state, staleDate: session.scheduledEndAt))
    }

    private func endLiveActivity() async {
        guard let liveActivity else { return }
        if let session = snapshot.session {
            let state = PingScopeLiveActivityAttributes.ContentState(
                session: session,
                health: snapshot.health
            )
            await liveActivity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        } else {
            await liveActivity.end(nil, dismissalPolicy: .immediate)
        }
        self.liveActivity = nil
    }
}

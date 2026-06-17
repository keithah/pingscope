import ActivityKit
import Combine
import PingScopeCore
import PingScopeiOS
import SwiftUI
import UIKit

@main
struct PingScopeIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = PingScopeIOSAppModel()

    var body: some Scene {
        WindowGroup {
            PingScopeIOSRootView(
                hosts: model.hosts,
                host: model.snapshot.host,
                session: model.snapshot.session,
                health: model.snapshot.health,
                samples: model.snapshot.series.samples,
                historySamples: model.historySamples,
                selectedHostID: model.snapshot.host.id,
                onSelectHost: { hostID in
                    model.selectHost(hostID)
                },
                onSaveHost: { host in
                    model.saveHost(host)
                },
                onDeleteHost: { hostID in
                    model.deleteHost(hostID)
                },
                onStart: { duration in
                    model.start(duration: duration)
                },
                onStop: {
                    model.stop()
                }
            )
            .onAppear {
                model.startInitialSessionIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                model.handleScenePhase(phase)
            }
        }
    }
}

@MainActor
private final class PingScopeIOSAppModel: ObservableObject {
    @Published var hosts: [HostConfig]
    @Published var snapshot: LiveMonitorSessionSnapshot
    @Published var historySamples: [PingResult] = []

    private let hostStore: PingScopeIOSHostStore
    private let historyStore: (any PingHistoryStore)?
    private let backgroundRuntime: LiveMonitorBackgroundRuntime
    private var controller: LiveMonitorSessionController
    private var refreshTask: Task<Void, Never>?
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?
    private var hasStartedInitialSession = false

    init() {
        self.hostStore = PingScopeIOSHostStore()
        self.historyStore = try? SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL(appName: "PingScope-iOS"))
        self.backgroundRuntime = LiveMonitorBackgroundRuntime(client: UIApplicationBackgroundTaskClient())
        let state = hostStore.load()
        let host = state.selectedHost
        self.hosts = state.hosts
        self.controller = LiveMonitorSessionController(host: host, historyStore: historyStore)
        self.snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
        Task {
            await refreshHistory()
        }
    }

    func selectHost(_ hostID: UUID) {
        guard let host = hosts.first(where: { $0.id == hostID }) else { return }
        refreshTask?.cancel()
        refreshTask = nil
        hostStore.save(hosts: hosts, selectedHostID: hostID)
        Task {
            await backgroundRuntime.end()
            await controller.stop(reason: .userStopped)
            await endLiveActivity()
            controller = LiveMonitorSessionController(host: host, historyStore: historyStore)
            snapshot = LiveMonitorSessionSnapshot(
                host: host,
                session: nil,
                health: HostHealth(hostID: host.id, thresholds: host.thresholds)
            )
            await refreshHistory()
        }
    }

    func saveHost(_ host: HostConfig) {
        let normalizedHost = BuildFlavor.appStore.normalizedHost(host)
        if let index = hosts.firstIndex(where: { $0.id == normalizedHost.id }) {
            hosts[index] = normalizedHost
        } else {
            hosts.append(normalizedHost)
        }
        hostStore.save(hosts: hosts, selectedHostID: normalizedHost.id)
        selectHost(normalizedHost.id)
    }

    func deleteHost(_ hostID: UUID) {
        guard hosts.count > 1 else { return }
        hosts.removeAll { $0.id == hostID }
        let replacementID = hosts.first?.id ?? HostConfig.defaultInternet.id
        hostStore.save(hosts: hosts, selectedHostID: replacementID)
        selectHost(replacementID)
    }

    func start(duration: MonitorSessionDuration) {
        refreshTask?.cancel()
        Task {
            await backgroundRuntime.end()
            await endLiveActivity()
            await controller.start(duration: duration)
            await refreshSnapshot()
            await startLiveActivity(duration: duration)
            startRefreshLoop()
        }
    }

    func startInitialSessionIfNeeded() {
        guard !hasStartedInitialSession else { return }
        hasStartedInitialSession = true
        start(duration: .continuous)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        Task {
            await backgroundRuntime.end()
            await controller.stop(reason: .userStopped)
            await refreshSnapshot()
            await refreshHistory()
            await endLiveActivity()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await backgroundRuntime.end()
                await restartContinuousSessionAfterBackgroundExpirationIfNeeded()
            }
        case .background:
            beginBackgroundRuntimeIfNeeded()
            Task {
                await ensureLiveActivityForCurrentSession()
            }
        case .inactive:
            Task {
                await ensureLiveActivityForCurrentSession()
            }
        @unknown default:
            break
        }
    }

    private func startRefreshLoop() {
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshSnapshot()
                if snapshot.session?.phase() == .ended {
                    await refreshHistory()
                    await backgroundRuntime.end()
                    await endLiveActivity()
                    break
                }
                await updateLiveActivity()
                await refreshHistory()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshSnapshot() async {
        snapshot = await controller.snapshot()
    }

    private func refreshHistory() async {
        guard let historyStore else {
            historySamples = []
            return
        }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let samples = await historyStore.samples(hostID: snapshot.host.id, since: cutoff, limit: 100)
        historySamples = samples.sorted { $0.timestamp > $1.timestamp }
    }

    private func beginBackgroundRuntimeIfNeeded() {
        guard let session = snapshot.session, session.phase() != .ended else { return }
        Task {
            await backgroundRuntime.begin { [weak self] in
                await self?.expireForBackgroundRuntime()
            }
        }
    }

    private func expireForBackgroundRuntime() async {
        refreshTask?.cancel()
        refreshTask = nil
        await controller.stop(reason: .backgroundRuntimeExpired)
        await refreshSnapshot()
        await refreshHistory()
        await endLiveActivity()
    }

    private func startLiveActivity(duration: MonitorSessionDuration) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let session = snapshot.session else { return }

        do {
            if liveActivity != nil {
                await updateLiveActivity()
                return
            }
            let attributes = PingScopeLiveActivityAttributes(host: snapshot.host, duration: duration)
            let state = PingScopeLiveActivityAttributes.ContentState(
                session: session,
                health: snapshot.health
            )
            let staleDate = session.scheduledEndAt
            liveActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate),
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

    private func ensureLiveActivityForCurrentSession() async {
        await refreshSnapshot()
        guard let session = snapshot.session, session.phase() != .ended else { return }
        if liveActivity == nil {
            await startLiveActivity(duration: session.duration)
        } else {
            await updateLiveActivity()
        }
    }

    private func restartContinuousSessionAfterBackgroundExpirationIfNeeded() async {
        await refreshSnapshot()
        guard let session = snapshot.session,
              session.duration == .continuous,
              session.phase() == .ended,
              session.endReason == .backgroundRuntimeExpired else {
            return
        }
        await endLiveActivity()
        await controller.start(duration: .continuous)
        await refreshSnapshot()
        await startLiveActivity(duration: .continuous)
        startRefreshLoop()
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

private struct UIApplicationBackgroundTaskClient: LiveMonitorBackgroundTaskClient {
    func beginBackgroundTask(named name: String, expirationHandler: @escaping @Sendable () -> Void) async -> LiveMonitorBackgroundTaskID? {
        await MainActor.run {
            let id = UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expirationHandler)
            guard id != .invalid else { return nil }
            return LiveMonitorBackgroundTaskID(rawValue: id.rawValue)
        }
    }

    func endBackgroundTask(_ id: LiveMonitorBackgroundTaskID) async {
        await MainActor.run {
            UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: id.rawValue))
        }
    }
}

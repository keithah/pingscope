import ActivityKit
import Combine
import CoreLocation
import Network
import PingScopeCore
import PingScopeiOS
import SwiftUI
import UIKit
import WidgetKit

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
                graphSamples: model.graphSamples,
                historySamples: model.historySamples,
                selectedGraphRange: model.selectedGraphRange,
                gatewayDetectionText: model.gatewayDetectionText,
                backgroundKeepAliveEnabled: model.backgroundKeepAliveEnabled,
                backgroundKeepAliveStatus: model.backgroundKeepAliveStatus,
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
                onSelectGraphRange: { range in
                    model.selectedGraphRange = range
                },
                onUseDefaultGateway: {
                    model.addDefaultGatewayHost()
                },
                onSetBackgroundKeepAlive: { isEnabled in
                    model.setBackgroundKeepAliveEnabled(isEnabled)
                },
                onRequestBackgroundKeepAlivePermission: {
                    model.requestBackgroundKeepAlivePermission()
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
    @Published var selectedGraphRange: TimeRange = .fiveMinutes
    @Published var gatewayDetectionText: String?
    @Published var backgroundKeepAliveEnabled: Bool
    @Published var backgroundKeepAliveStatus: String = "Disabled"

    private let hostStore: PingScopeIOSHostStore
    private let historyStore: (any PingHistoryStore)?
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let gatewayDetector = PingScopeIOSGatewayDetector()
    private let presenter = DisplayStatePresenter()
    private let backgroundRuntime: LiveMonitorBackgroundRuntime
    private let locationKeepAlive = BackgroundLocationKeepAliveController()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "PingScope.iOS.NetworkPath")
    private var controller: LiveMonitorSessionController
    private var refreshTask: Task<Void, Never>?
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?
    private var hasStartedInitialSession = false
    private var lastGatewayAddress: String?

    init() {
        self.hostStore = PingScopeIOSHostStore()
        self.historyStore = try? SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL(appName: "PingScope-iOS"))
        self.backgroundRuntime = LiveMonitorBackgroundRuntime(client: UIApplicationBackgroundTaskClient())
        self.backgroundKeepAliveEnabled = UserDefaults.standard.bool(forKey: Self.backgroundKeepAliveEnabledKey)
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
        locationKeepAlive.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.backgroundKeepAliveStatus = status
            if self.backgroundKeepAliveEnabled, self.isMonitoringActive {
                self.applyBackgroundKeepAlive()
            }
        }
        backgroundKeepAliveStatus = locationKeepAlive.statusText(isEnabled: backgroundKeepAliveEnabled, isMonitoring: false)
        startNetworkPathMonitoring()
    }

    deinit {
        pathMonitor.cancel()
    }

    var graphSamples: [PingResult] {
        presenter.mergedSamples(
            history: historySamples,
            live: snapshot.series.samples,
            range: selectedGraphRange
        )
    }

    func selectHost(_ hostID: UUID) {
        guard let host = hosts.first(where: { $0.id == hostID }) else { return }
        switchToHost(host, restartDuration: activeRestartDuration, saveSelection: true)
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

    func addDefaultGatewayHost() {
        gatewayDetectionText = "Detecting..."
        Task {
            await refreshDefaultGatewayHost(shouldCreateIfMissing: true, shouldSelect: true, statusVerb: "selected")
        }
    }

    func setBackgroundKeepAliveEnabled(_ isEnabled: Bool) {
        backgroundKeepAliveEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.backgroundKeepAliveEnabledKey)
        if isEnabled {
            locationKeepAlive.requestAlwaysAuthorization()
        }
        applyBackgroundKeepAlive()
    }

    func requestBackgroundKeepAlivePermission() {
        locationKeepAlive.requestAlwaysAuthorization()
        backgroundKeepAliveStatus = locationKeepAlive.statusText(
            isEnabled: backgroundKeepAliveEnabled,
            isMonitoring: isMonitoringActive
        )
    }

    func start(duration: MonitorSessionDuration) {
        refreshTask?.cancel()
        Task {
            await backgroundRuntime.end()
            await endLiveActivity()
            await controller.start(duration: duration)
            await refreshSnapshot()
            await startLiveActivity(duration: duration)
            applyBackgroundKeepAlive()
            startRefreshLoop()
        }
    }

    func startInitialSessionIfNeeded() {
        guard !hasStartedInitialSession else { return }
        hasStartedInitialSession = true
        Task {
            await refreshDefaultGatewayHost(shouldCreateIfMissing: false, shouldSelect: false, statusVerb: "updated")
            start(duration: .continuous)
        }
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
            applyBackgroundKeepAlive()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await backgroundRuntime.end()
                await refreshDefaultGatewayHost(shouldCreateIfMissing: false, shouldSelect: false, statusVerb: "updated")
                await restartContinuousSessionAfterBackgroundExpirationIfNeeded()
                applyBackgroundKeepAlive()
            }
        case .background:
            applyBackgroundKeepAlive()
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
                    applyBackgroundKeepAlive()
                    break
                }
                await updateLiveActivity()
                await refreshHistory()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var activeRestartDuration: MonitorSessionDuration? {
        guard let session = snapshot.session, session.phase() != .ended else { return nil }
        return session.duration
    }

    private var isMonitoringActive: Bool {
        activeRestartDuration != nil
    }

    private static let backgroundKeepAliveEnabledKey = "PingScope.iOS.backgroundKeepAliveEnabled"

    private func startNetworkPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.refreshDefaultGatewayHost(
                    shouldCreateIfMissing: false,
                    shouldSelect: false,
                    statusVerb: "updated"
                )
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func refreshDefaultGatewayHost(
        shouldCreateIfMissing: Bool,
        shouldSelect: Bool,
        statusVerb: String
    ) async {
        guard var detectedHost = await gatewayDetector.detect() else {
            if shouldCreateIfMissing || hasDefaultGatewayHost {
                gatewayDetectionText = "No default gateway exposed by iOS"
            }
            return
        }

        guard detectedHost.address != lastGatewayAddress || shouldCreateIfMissing else {
            return
        }
        lastGatewayAddress = detectedHost.address

        if let index = defaultGatewayHostIndex {
            var updatedHost = hosts[index]
            guard updatedHost.address != detectedHost.address || shouldSelect else {
                return
            }
            let previousAddress = updatedHost.address
            updatedHost.address = detectedHost.address
            hosts[index] = updatedHost
            hostStore.save(hosts: hosts, selectedHostID: snapshot.host.id)

            if snapshot.host.id == updatedHost.id || shouldSelect {
                await switchToHostAsync(updatedHost, restartDuration: activeRestartDuration, saveSelection: true)
            }

            gatewayDetectionText = "Default gateway \(statusVerb): \(previousAddress) -> \(updatedHost.address)"
            return
        }

        guard shouldCreateIfMissing else { return }
        detectedHost = BuildFlavor.appStore.normalizedHost(detectedHost)
        hosts.append(detectedHost)
        hostStore.save(hosts: hosts, selectedHostID: detectedHost.id)
        await switchToHostAsync(detectedHost, restartDuration: activeRestartDuration, saveSelection: true)
        gatewayDetectionText = "\(detectedHost.address) \(statusVerb)"
    }

    private var defaultGatewayHostIndex: Array<HostConfig>.Index? {
        hosts.firstIndex { $0.displayName == "Default Gateway" }
    }

    private var hasDefaultGatewayHost: Bool {
        defaultGatewayHostIndex != nil
    }

    private func switchToHost(_ host: HostConfig, restartDuration: MonitorSessionDuration?, saveSelection: Bool) {
        Task {
            await switchToHostAsync(host, restartDuration: restartDuration, saveSelection: saveSelection)
        }
    }

    private func switchToHostAsync(_ host: HostConfig, restartDuration: MonitorSessionDuration?, saveSelection: Bool) async {
        refreshTask?.cancel()
        refreshTask = nil
        if saveSelection {
            hostStore.save(hosts: hosts, selectedHostID: host.id)
        }

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
        if let restartDuration {
            await controller.start(duration: restartDuration)
            await refreshSnapshot()
            await startLiveActivity(duration: restartDuration)
            applyBackgroundKeepAlive()
            startRefreshLoop()
        } else {
            applyBackgroundKeepAlive()
        }
    }

    private func applyBackgroundKeepAlive() {
        if backgroundKeepAliveEnabled, isMonitoringActive {
            locationKeepAlive.start()
        } else {
            locationKeepAlive.stop()
        }
        backgroundKeepAliveStatus = locationKeepAlive.statusText(
            isEnabled: backgroundKeepAliveEnabled,
            isMonitoring: isMonitoringActive
        )
    }

    private func refreshSnapshot() async {
        snapshot = await controller.snapshot()
        await publishWidgetSnapshot()
    }

    private func refreshHistory() async {
        guard let historyStore else {
            historySamples = []
            await publishWidgetSnapshot()
            return
        }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let samples = await historyStore.samples(hostID: snapshot.host.id, since: cutoff, limit: 100)
        historySamples = samples.sorted { $0.timestamp > $1.timestamp }
        await publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() async {
        let host = snapshot.host
        let recentResults = presenter.mergedSamples(
            history: historySamples,
            live: snapshot.series.samples,
            range: .tenMinutes
        )
        .sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
        .suffix(60)

        let widgetSnapshot = WidgetSnapshot(
            primaryHostID: host.id,
            hosts: [
                WidgetHost(
                    id: host.id,
                    displayName: host.displayName,
                    address: host.address,
                    method: host.method,
                    port: host.port,
                    isPrimary: true
                )
            ],
            health: [
                WidgetHostHealth(
                    hostID: host.id,
                    status: snapshot.health.status,
                    latencyMilliseconds: snapshot.health.latestResult?.latency?.milliseconds,
                    consecutiveFailureCount: snapshot.health.consecutiveFailureCount,
                    failureReason: snapshot.health.latestResult?.failureReason,
                    latestResultAt: snapshot.health.latestResult?.timestamp
                )
            ],
            recentSamples: recentResults.map(WidgetSample.init(result:)),
            networkStatus: .connected,
            generatedAt: Date()
        )
        await widgetSnapshotStore.save(widgetSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
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
        applyBackgroundKeepAlive()
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
        applyBackgroundKeepAlive()
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

@MainActor
private final class BackgroundLocationKeepAliveController: NSObject, CLLocationManagerDelegate {
    var onStatusChange: ((String) -> Void)?

    private let manager = CLLocationManager()
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1_000
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAlwaysAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .restricted, .denied, .authorizedAlways:
            notify()
        @unknown default:
            notify()
        }
    }

    func start() {
        guard isAlwaysAuthorized else {
            notify()
            return
        }
        guard !isRunning else {
            return
        }
        isRunning = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        notify()
    }

    func stop() {
        guard isRunning else {
            notify()
            return
        }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        notify()
    }

    func statusText(isEnabled: Bool, isMonitoring: Bool) -> String {
        guard isEnabled else { return "Disabled" }
        guard isAlwaysAuthorized else { return authorizationStatusText }
        return isMonitoring && isRunning ? "Running while monitoring" : "Allowed; starts while monitoring"
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            notify()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            onStatusChange?("Location keep alive error: \(error.localizedDescription)")
        }
    }

    private var isAlwaysAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    private var authorizationStatusText: String {
        switch manager.authorizationStatus {
        case .notDetermined:
            "Location permission not requested"
        case .restricted:
            "Location permission restricted"
        case .denied:
            "Location permission denied"
        case .authorizedWhenInUse:
            "Allow Always Location in Settings"
        case .authorizedAlways:
            isRunning ? "Running while monitoring" : "Allowed; starts while monitoring"
        @unknown default:
            "Location permission unknown"
        }
    }

    private func notify() {
        onStatusChange?(authorizationStatusText)
    }
}

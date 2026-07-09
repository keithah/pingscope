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
                graphPresentation: model.graphPresentation,
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
                onMoveHosts: { offsets, destination in
                    model.moveHosts(fromOffsets: offsets, toOffset: destination)
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
    @Published var graphPresentation = PingScopeIOSGraphPresentation(samples: [], range: .fiveMinutes)
    @Published var selectedGraphRange: TimeRange = .fiveMinutes {
        didSet {
            rebuildGraphSamples()
        }
    }
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
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?
    private var hasStartedInitialSession = false
    private var lastGatewayAddress: String?
    private var lastHistoryRefreshAt: Date?
    private var lastPublishedWidgetSnapshot: WidgetSnapshot?
    private var lastWidgetTimelineReloadAt: Date?
    private let widgetPublishPolicy = WidgetSnapshotPublishPolicy()

    init() {
        self.hostStore = PingScopeIOSHostStore()
        do {
            self.historyStore = try SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL(appName: "PingScope-iOS"))
        } catch {
            NSLog("PingScope iOS history store unavailable: \(String(describing: error))")
            #if DEBUG
            print("PingScope iOS history store unavailable: \(error)")
            #endif
            self.historyStore = nil
        }
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
        self.graphPresentation = PingScopeIOSGraphPresentation(samples: snapshot.series.samples, range: selectedGraphRange)
        Task {
            await refreshHistory(force: true)
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
        refreshTask?.cancel()
        lifecycleTask?.cancel()
        pathMonitor.cancel()
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

    func moveHosts(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        hosts = PingScopeIOSHostOrdering.reordered(hosts: hosts, fromOffsets: offsets, toOffset: destination)
        hostStore.save(hosts: hosts, selectedHostID: snapshot.host.id)
    }

    func addDefaultGatewayHost() {
        gatewayDetectionText = "Detecting..."
        runLifecycleTask { model, context in
            guard await model.refreshDefaultGatewayHost(
                shouldCreateIfMissing: true,
                shouldSelect: true,
                statusVerb: "selected",
                context: context
            ) else {
                return
            }
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
        runLifecycleTask { model, context in
            await model.startSession(duration: duration, context: context)
        }
    }

    func startInitialSessionIfNeeded() {
        guard !hasStartedInitialSession else { return }
        hasStartedInitialSession = true
        runLifecycleTask { model, context in
            guard await model.refreshDefaultGatewayHost(
                shouldCreateIfMissing: false,
                shouldSelect: false,
                statusVerb: "updated",
                context: context
            ) else {
                return
            }
            guard model.isCurrentLifecycle(context) else { return }
            await model.startSession(duration: .continuous, context: context)
        }
    }

    func stop() {
        runLifecycleTask { model, context in
            model.cancelRefreshLoop()
            await model.backgroundRuntime.end()
            guard model.isCurrentLifecycle(context) else { return }
            await model.controller.stop(reason: .userStopped)
            guard model.isCurrentLifecycle(context) else { return }
            await model.refreshSnapshot()
            guard model.isCurrentLifecycle(context) else { return }
            await model.refreshHistory(force: true)
            guard model.isCurrentLifecycle(context) else { return }
            await model.endLiveActivity()
            guard model.isCurrentLifecycle(context) else { return }
            model.applyBackgroundKeepAlive()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            runLifecycleTask { model, context in
                await model.backgroundRuntime.end()
                guard model.isCurrentLifecycle(context) else { return }
                guard await model.refreshDefaultGatewayHost(
                    shouldCreateIfMissing: false,
                    shouldSelect: false,
                    statusVerb: "updated",
                    context: context
                ) else {
                    return
                }
                guard model.isCurrentLifecycle(context) else { return }
                await model.restartContinuousSessionAfterBackgroundExpirationIfNeeded(context: context)
                guard model.isCurrentLifecycle(context) else { return }
                model.applyBackgroundKeepAlive()
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

    private struct LifecycleContext {
        let generation: Int
    }

    private func runLifecycleTask(_ operation: @escaping @MainActor (PingScopeIOSAppModel, LifecycleContext) async -> Void) {
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        lifecycleTask?.cancel()
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await operation(self, LifecycleContext(generation: generation))
        }
    }

    private func isCurrentLifecycle(_ context: LifecycleContext) -> Bool {
        context.generation == lifecycleGeneration && !Task.isCancelled
    }

    private func isCurrentLifecycle(_ context: LifecycleContext?) -> Bool {
        guard let context else { return !Task.isCancelled }
        return isCurrentLifecycle(context)
    }

    private func cancelRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startSession(duration: MonitorSessionDuration, context: LifecycleContext) async {
        cancelRefreshLoop()
        await backgroundRuntime.end()
        guard isCurrentLifecycle(context) else { return }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        await controller.start(duration: duration)
        guard isCurrentLifecycle(context) else { return }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        await startLiveActivity(duration: duration)
        guard isCurrentLifecycle(context) else { return }
        applyBackgroundKeepAlive()
        startRefreshLoop()
    }

    private func startRefreshLoop() {
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshSnapshot()
                if snapshot.session?.phase() == .ended {
                    await refreshHistory(force: true)
                    await backgroundRuntime.end()
                    await endLiveActivity()
                    applyBackgroundKeepAlive()
                    break
                }
                await updateLiveActivity()
                await refreshHistoryIfStale()
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
        statusVerb: String,
        context: LifecycleContext? = nil
    ) async -> Bool {
        guard var detectedHost = await gatewayDetector.detect() else {
            guard isCurrentLifecycle(context) else { return false }
            if shouldCreateIfMissing || hasDefaultGatewayHost {
                gatewayDetectionText = "No default gateway exposed by iOS"
            }
            return true
        }
        guard isCurrentLifecycle(context) else { return false }

        guard detectedHost.address != lastGatewayAddress || shouldCreateIfMissing else {
            return true
        }
        lastGatewayAddress = detectedHost.address

        if let index = defaultGatewayHostIndex {
            var updatedHost = hosts[index]
            guard updatedHost.address != detectedHost.address || shouldSelect else {
                return true
            }
            let previousAddress = updatedHost.address
            updatedHost.address = detectedHost.address
            hosts[index] = updatedHost
            hostStore.save(hosts: hosts, selectedHostID: snapshot.host.id)

            if snapshot.host.id == updatedHost.id || shouldSelect {
                await switchToHostAsync(
                    updatedHost,
                    restartDuration: activeRestartDuration,
                    saveSelection: true,
                    context: context
                )
                guard isCurrentLifecycle(context) else { return false }
            }

            gatewayDetectionText = "Default gateway \(statusVerb): \(previousAddress) -> \(updatedHost.address)"
            return true
        }

        guard shouldCreateIfMissing else { return true }
        detectedHost = BuildFlavor.appStore.normalizedHost(detectedHost)
        hosts.append(detectedHost)
        hostStore.save(hosts: hosts, selectedHostID: detectedHost.id)
        await switchToHostAsync(detectedHost, restartDuration: activeRestartDuration, saveSelection: true, context: context)
        guard isCurrentLifecycle(context) else { return false }
        gatewayDetectionText = "\(detectedHost.address) \(statusVerb)"
        return true
    }

    private var defaultGatewayHostIndex: Array<HostConfig>.Index? {
        hosts.firstIndex { $0.displayName == "Default Gateway" }
    }

    private var hasDefaultGatewayHost: Bool {
        defaultGatewayHostIndex != nil
    }

    private func switchToHost(_ host: HostConfig, restartDuration: MonitorSessionDuration?, saveSelection: Bool) {
        runLifecycleTask { model, context in
            await model.switchToHostAsync(
                host,
                restartDuration: restartDuration,
                saveSelection: saveSelection,
                context: context
            )
        }
    }

    private func switchToHostAsync(
        _ host: HostConfig,
        restartDuration: MonitorSessionDuration?,
        saveSelection: Bool,
        context: LifecycleContext? = nil
    ) async {
        cancelRefreshLoop()
        if saveSelection {
            hostStore.save(hosts: hosts, selectedHostID: host.id)
        }

        await backgroundRuntime.end()
        guard isCurrentLifecycle(context) else { return }
        await controller.stop(reason: .userStopped)
        guard isCurrentLifecycle(context) else { return }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        controller = LiveMonitorSessionController(host: host, historyStore: historyStore)
        snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
        await refreshHistory(force: true)
        guard isCurrentLifecycle(context) else { return }
        if let restartDuration {
            await controller.start(duration: restartDuration)
            guard isCurrentLifecycle(context) else { return }
            await refreshSnapshot()
            guard isCurrentLifecycle(context) else { return }
            await startLiveActivity(duration: restartDuration)
            guard isCurrentLifecycle(context) else { return }
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
        rebuildGraphSamples()
        await publishWidgetSnapshot()
    }

    private func refreshHistory(force: Bool = false) async {
        if !force, let lastHistoryRefreshAt, Date().timeIntervalSince(lastHistoryRefreshAt) < 30 {
            return
        }
        lastHistoryRefreshAt = Date()
        guard let historyStore else {
            historySamples = []
            rebuildGraphSamples()
            await publishWidgetSnapshot()
            return
        }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        historySamples = await historyStore.latestSamples(hostID: snapshot.host.id, since: cutoff, limit: 100)
        rebuildGraphSamples()
        await publishWidgetSnapshot()
    }

    private func refreshHistoryIfStale() async {
        await refreshHistory(force: false)
    }

    private func rebuildGraphSamples() {
        let graphSamples = presenter.mergedSamples(
            history: historySamples,
            live: snapshot.series.samples,
            range: selectedGraphRange
        )
        graphPresentation = PingScopeIOSGraphPresentation(
            samples: graphSamples,
            range: selectedGraphRange,
            endDate: Date()
        )
    }

    private func publishWidgetSnapshot() async {
        let host = snapshot.host
        let recentResults = presenter.mergedSamples(
            history: historySamples,
            live: snapshot.series.samples,
            range: .tenMinutes
        )
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
        let publishDecision = widgetPublishPolicy.decision(
            for: widgetSnapshot,
            previousSnapshot: lastPublishedWidgetSnapshot,
            lastTimelineReloadAt: lastWidgetTimelineReloadAt
        )
        guard publishDecision.shouldSave else { return }
        lastPublishedWidgetSnapshot = widgetSnapshot
        guard await widgetSnapshotStore.save(widgetSnapshot) else { return }
        if publishDecision.shouldReloadTimeline {
            lastWidgetTimelineReloadAt = widgetSnapshot.generatedAt
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func beginBackgroundRuntimeIfNeeded() {
        guard let session = snapshot.session, session.phase() != .ended else { return }
        runLifecycleTask { model, context in
            await model.backgroundRuntime.begin { [weak model] in
                await model?.expireForBackgroundRuntime(context: context)
            }
        }
    }

    private func expireForBackgroundRuntime(context: LifecycleContext? = nil) async {
        cancelRefreshLoop()
        await controller.stop(reason: .backgroundRuntimeExpired)
        guard isCurrentLifecycle(context) else { return }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        await refreshHistory(force: true)
        guard isCurrentLifecycle(context) else { return }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
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
            NSLog("PingScope live activity request failed: \(String(describing: error))")
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

    private func restartContinuousSessionAfterBackgroundExpirationIfNeeded(context: LifecycleContext? = nil) async {
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        guard let session = snapshot.session,
              session.duration == .continuous,
              session.phase() == .ended,
              session.endReason == .backgroundRuntimeExpired else {
            return
        }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        await controller.start(duration: .continuous)
        guard isCurrentLifecycle(context) else { return }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        await startLiveActivity(duration: .continuous)
        guard isCurrentLifecycle(context) else { return }
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

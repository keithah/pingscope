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
                session: model.presentedSession,
                health: model.snapshot.health,
                samples: model.snapshot.series.samples,
                graphPresentation: model.graphPresentation,
                historySamples: model.historySamples,
                selectedGraphRange: model.selectedGraphRange,
                gatewayDetectionText: model.gatewayDetectionText,
                backgroundKeepAliveEnabled: model.backgroundKeepAliveEnabled,
                backgroundKeepAliveStatus: model.backgroundKeepAliveStatus,
                displayMode: model.displayMode.resolvedForHostScope(showsAllHosts: model.hostScope == .allHosts),
                hostScope: model.hostScope,
                allHostRows: model.allHostRows,
                allHostGraphSeries: model.allHostGraphSeries,
                allHostsPresentationEndDate: model.allHostsPresentationEndDate,
                selectedHostID: model.snapshot.host.id,
                onSelectDisplayMode: { mode in
                    model.displayMode = mode
                },
                onSelectAllHosts: {
                    model.selectAllHosts()
                },
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
    @Published var hostScope: PingScopeIOSHostScope
    @Published var allHostRows: [PingScopeIOSHostRowSnapshot] = []
    @Published var allHostGraphSeries: [PingScopeIOSHostGraphSeries] = []
    @Published var allHostsPresentationEndDate = Date()
    @Published private var allHostsSession: MonitorSessionState?
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
    @Published var displayMode: PingScopeIOSDisplayMode {
        didSet {
            UserDefaults.standard.pingScopeIOSDisplayMode = displayMode
        }
    }

    private let hostStore: PingScopeIOSHostStore
    private let historyStore: (any PingHistoryStore)?
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let gatewayDetector = PingScopeIOSGatewayDetector()
    private let presenter = DisplayStatePresenter()
    private let backgroundRuntime: LiveMonitorBackgroundRuntime
    private let multiHostCoordinator: PingScopeIOSMultiHostSessionCoordinator
    private let locationKeepAlive = BackgroundLocationKeepAliveController()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "PingScope.iOS.NetworkPath")
    private var controller: LiveMonitorSessionController
    private var refreshTask: Task<Void, Never>?
    private let lifecycleHarness = PingScopeIOSLifecycleHarness(
        promptBackgroundProtectionClient: UIApplicationPromptBackgroundProtectionClient()
    )
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?
    private var liveActivityLease: PingScopeIOSActivityOwnershipLease?
    private var initialSessionCoordinator = PingScopeIOSInitialSessionCoordinator()
    private var lastGatewayAddress: String?
    private var lastHistoryRefreshAt: Date?
    private var lastPublishedWidgetSnapshot: WidgetSnapshot?
    private var lastWidgetTimelineReloadAt: Date?
    private let widgetPublishPolicy = WidgetSnapshotPublishPolicy()

    init() {
        self.hostStore = PingScopeIOSHostStore()
        let loadedHistoryStore: (any PingHistoryStore)?
        do {
            loadedHistoryStore = try SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL(appName: "PingScope-iOS"))
        } catch {
            NSLog("PingScope iOS history store unavailable: \(String(describing: error))")
            #if DEBUG
            print("PingScope iOS history store unavailable: \(error)")
            #endif
            loadedHistoryStore = nil
        }
        self.historyStore = loadedHistoryStore
        self.multiHostCoordinator = PingScopeIOSMultiHostSessionCoordinator(historyStore: loadedHistoryStore)
        self.backgroundRuntime = LiveMonitorBackgroundRuntime(client: UIApplicationBackgroundTaskClient())
        self.backgroundKeepAliveEnabled = UserDefaults.standard.bool(forKey: Self.backgroundKeepAliveEnabledKey)
        self.displayMode = UserDefaults.standard.pingScopeIOSDisplayMode
        let state = hostStore.load()
        let host = state.selectedHost
        self.hosts = state.hosts
        self.hostScope = state.hostScope
        self.controller = LiveMonitorSessionController(host: host, historyStore: loadedHistoryStore)
        self.snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
        self.graphPresentation = PingScopeIOSGraphPresentation(samples: snapshot.series.samples, range: selectedGraphRange)
        Task { @MainActor [weak self] in
            self?.runLifecycleTask { model, context in
                if model.hostScope == .allHosts {
                    await model.multiHostCoordinator.reconcile(hosts: model.hosts)
                    guard model.isCurrentLifecycle(context) else { return }
                    await model.refreshSnapshot()
                } else {
                    await model.refreshHistory(force: true)
                }
            }
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

    var presentedSession: MonitorSessionState? {
        hostScope == .allHosts ? allHostsSession : snapshot.session
    }

    deinit {
        refreshTask?.cancel()
        pathMonitor.cancel()
    }

    func selectHost(_ hostID: UUID) {
        runLifecycleTask { model, context in
            guard let host = model.hosts.first(where: { $0.id == hostID }) else { return }
            await model.switchToHostAsync(
                host,
                restartDuration: model.activeRestartDuration,
                saveSelection: true,
                context: context
            )
        }
    }

    func selectAllHosts() {
        runLifecycleTask { model, context in
            guard model.hostScope != .allHosts else { return }
            await model.switchToAllHostsAsync(
                restartDuration: model.activeRestartDuration,
                context: context
            )
        }
    }

    func saveHost(_ host: HostConfig) {
        let normalizedHost = BuildFlavor.appStore.normalizedHost(host)
        if let index = hosts.firstIndex(where: { $0.id == normalizedHost.id }) {
            hosts[index] = normalizedHost
        } else {
            hosts.append(normalizedHost)
        }
        guard hostScope == .allHosts else {
            hostStore.save(hosts: hosts, selectedHostID: normalizedHost.id, hostScope: .focused)
            selectHost(normalizedHost.id)
            return
        }

        if snapshot.host.id == normalizedHost.id {
            replaceRememberedFocusedHost(normalizedHost)
        }
        persistHostSelection()
        reconcileAllHostsAfterMutation()
    }

    func deleteHost(_ hostID: UUID) {
        guard hosts.count > 1 else { return }
        hosts.removeAll { $0.id == hostID }
        let replacement = hosts.first ?? HostConfig.defaultInternet
        guard hostScope == .allHosts else {
            hostStore.save(hosts: hosts, selectedHostID: replacement.id, hostScope: .focused)
            selectHost(replacement.id)
            return
        }

        if snapshot.host.id == hostID {
            replaceRememberedFocusedHost(replacement)
        }
        persistHostSelection()
        reconcileAllHostsAfterMutation()
    }

    func moveHosts(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        hosts = PingScopeIOSHostOrdering.reordered(hosts: hosts, fromOffsets: offsets, toOffset: destination)
        persistHostSelection()
        if hostScope == .allHosts {
            reconcileAllHostsAfterMutation()
        }
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
        initialSessionCoordinator.markExplicitSessionAction()
        runLifecycleTask { model, context in
            await model.startSession(duration: duration, context: context)
        }
    }

    func startInitialSessionIfNeeded() {
        guard initialSessionCoordinator.shouldStartInitialSession else { return }
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
            guard model.isCurrentLifecycle(context) else { return }
            model.initialSessionCoordinator.markInitialSessionStarted()
        }
    }

    func stop() {
        initialSessionCoordinator.markExplicitSessionAction()
        runLifecycleTask { model, context in
            model.cancelRefreshLoop()
            await model.backgroundRuntime.end()
            guard model.isCurrentLifecycle(context) else { return }
            await model.stopMonitoring(reason: .userStopped)
            guard model.isCurrentLifecycle(context) else { return }
            await model.refreshSnapshot()
            guard model.isCurrentLifecycle(context) else { return }
            if model.hostScope == .focused {
                await model.refreshHistory(force: true)
            }
            guard model.isCurrentLifecycle(context) else { return }
            await model.endLiveActivity()
            guard model.isCurrentLifecycle(context) else { return }
            model.applyBackgroundKeepAlive()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        let lifecyclePhase: PingScopeIOSLifecycleScenePhase
        switch phase {
        case .active:
            lifecyclePhase = .active
        case .background:
            lifecyclePhase = .background
        case .inactive:
            lifecyclePhase = .inactive
        @unknown default:
            return
        }
        let sceneEpoch = lifecycleHarness.transitionScene(to: lifecyclePhase)

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
                model.startInitialSessionIfNeeded()
            }
        case .background:
            lifecycleHarness.enqueueBackgroundWork(originatingAt: sceneEpoch) { @MainActor [weak self] in
                guard let model = self else { return }
                let context = LifecycleContext()
                model.applyBackgroundKeepAlive()
                await model.beginBackgroundRuntimeIfNeeded(originatingAt: sceneEpoch)
                model.lifecycleHarness.finishPromptBackgroundProtection()
                guard model.lifecycleHarness.isCurrentBackground(sceneEpoch) else {
                    await model.backgroundRuntime.end()
                    return
                }
                guard model.isCurrentLifecycle(context) else { return }
                await model.ensureLiveActivityForCurrentSession()
            }
        case .inactive:
            runLifecycleTask { model, context in
                await model.ensureLiveActivityForCurrentSession()
                guard model.isCurrentLifecycle(context) else { return }
            }
        @unknown default:
            break
        }
    }

    private struct LifecycleContext {}

    private func runLifecycleTask(_ operation: @escaping @MainActor (PingScopeIOSAppModel, LifecycleContext) async -> Void) {
        lifecycleHarness.enqueue { @MainActor [weak self] in
            guard let self else { return }
            await operation(self, LifecycleContext())
        }
    }

    private func isCurrentLifecycle(_ context: LifecycleContext) -> Bool {
        !Task.isCancelled
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
        invalidateLifecycleSession()
        await startMonitoring(duration: duration)
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
                if presentedSession?.phase() == .ended,
                   let sessionIdentity = lifecycleHarness.currentSessionIdentity {
                    lifecycleHarness.enqueueFiniteCompletion(for: sessionIdentity) { @MainActor [weak self] in
                        await self?.completeFiniteSession()
                    }
                    break
                }
                await updateLiveActivity()
                if hostScope == .focused {
                    await refreshHistoryIfStale()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func completeFiniteSession() async {
        cancelRefreshLoop()
        if hostScope == .allHosts {
            await stopMonitoring(reason: .completed)
            await refreshSnapshot()
        } else {
            await refreshHistory(force: true)
        }
        await backgroundRuntime.end()
        await endLiveActivity()
        applyBackgroundKeepAlive()
    }

    private var activeRestartDuration: MonitorSessionDuration? {
        guard let session = presentedSession, session.phase() != .ended else { return nil }
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
                self?.runLifecycleTask { model, context in
                    _ = await model.refreshDefaultGatewayHost(
                        shouldCreateIfMissing: false,
                        shouldSelect: false,
                        statusVerb: "updated",
                        context: context
                    )
                }
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
            if hostScope == .allHosts, snapshot.host.id == updatedHost.id {
                replaceRememberedFocusedHost(updatedHost)
            }
            persistHostSelection()

            if hostScope == .allHosts {
                guard await reconcileAllHostsAndRestorePostconditions(context: context) else {
                    return false
                }
            } else if snapshot.host.id == updatedHost.id || shouldSelect {
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
        if hostScope == .allHosts {
            persistHostSelection()
            guard await reconcileAllHostsAndRestorePostconditions(context: context) else {
                return false
            }
        } else {
            hostStore.save(hosts: hosts, selectedHostID: detectedHost.id, hostScope: .focused)
            await switchToHostAsync(detectedHost, restartDuration: activeRestartDuration, saveSelection: true, context: context)
            guard isCurrentLifecycle(context) else { return false }
        }
        gatewayDetectionText = "\(detectedHost.address) \(statusVerb)"
        return true
    }

    private var defaultGatewayHostIndex: Array<HostConfig>.Index? {
        hosts.firstIndex { $0.displayName == "Default Gateway" }
    }

    private var hasDefaultGatewayHost: Bool {
        defaultGatewayHostIndex != nil
    }

    private func switchToHostAsync(
        _ host: HostConfig,
        restartDuration: MonitorSessionDuration?,
        saveSelection: Bool,
        context: LifecycleContext? = nil
    ) async {
        let previousScope = hostScope
        let activityDecision = PingScopeIOSLiveActivityDecision.decide(
            isSessionActive: restartDuration != nil,
            previousScope: previousScope,
            newScope: .focused,
            previousFocusedHostID: snapshot.host.id,
            newFocusedHostID: host.id
        )
        cancelRefreshLoop()
        await backgroundRuntime.end()
        guard isCurrentLifecycle(context) else { return }
        if previousScope == .allHosts {
            await multiHostCoordinator.stop(reason: .userStopped)
        } else {
            await controller.stop(reason: .userStopped)
        }
        guard isCurrentLifecycle(context) else { return }
        if activityDecision == .restart || liveActivity != nil {
            await endLiveActivity()
        }
        guard isCurrentLifecycle(context) else { return }

        hostScope = .focused
        if saveSelection {
            hostStore.save(hosts: hosts, selectedHostID: host.id, hostScope: .focused)
        }
        controller = LiveMonitorSessionController(host: host, historyStore: historyStore)
        snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
        await refreshHistory(force: true)
        guard isCurrentLifecycle(context) else { return }
        if let restartDuration {
            invalidateLifecycleSession()
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

    private func switchToAllHostsAsync(
        restartDuration: MonitorSessionDuration?,
        context: LifecycleContext
    ) async {
        let activityDecision = PingScopeIOSLiveActivityDecision.decide(
            isSessionActive: restartDuration != nil,
            previousScope: hostScope,
            newScope: .allHosts,
            previousFocusedHostID: snapshot.host.id,
            newFocusedHostID: snapshot.host.id
        )
        cancelRefreshLoop()
        await backgroundRuntime.end()
        guard isCurrentLifecycle(context) else { return }
        await controller.stop(reason: .userStopped)
        guard isCurrentLifecycle(context) else { return }
        if activityDecision == .restart || liveActivity != nil {
            await endLiveActivity()
        }
        guard isCurrentLifecycle(context) else { return }

        hostScope = .allHosts
        persistHostSelection()
        await multiHostCoordinator.reconcile(hosts: hosts)
        guard isCurrentLifecycle(context) else { return }
        if let restartDuration {
            invalidateLifecycleSession()
            await multiHostCoordinator.start(duration: restartDuration)
            guard isCurrentLifecycle(context) else { return }
        }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        if let restartDuration {
            await startLiveActivity(duration: restartDuration)
            guard isCurrentLifecycle(context) else { return }
            startRefreshLoop()
        }
        applyBackgroundKeepAlive()
    }

    private func persistHostSelection() {
        hostStore.save(hosts: hosts, selectedHostID: snapshot.host.id, hostScope: hostScope)
    }

    private func replaceRememberedFocusedHost(_ host: HostConfig) {
        controller = LiveMonitorSessionController(host: host, historyStore: historyStore)
        snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
    }

    private func reconcileAllHostsAfterMutation() {
        runLifecycleTask { model, context in
            _ = await model.reconcileAllHostsAndRestorePostconditions(context: context)
        }
    }

    private func reconcileAllHostsAndRestorePostconditions(context: LifecycleContext?) async -> Bool {
        await multiHostCoordinator.reconcile(hosts: hosts)
        guard isCurrentLifecycle(context) else { return false }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return false }
        await ensureLiveActivityForPresentedSession()
        guard isCurrentLifecycle(context) else { return false }
        applyBackgroundKeepAlive()
        if isMonitoringActive, refreshTask == nil {
            startRefreshLoop()
        }
        return true
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

    private func startMonitoring(duration: MonitorSessionDuration) async {
        if hostScope == .allHosts {
            await multiHostCoordinator.reconcile(hosts: hosts)
            await multiHostCoordinator.start(duration: duration)
        } else {
            await controller.start(duration: duration)
        }
    }

    private func stopMonitoring(reason: MonitorSessionEndReason) async {
        if hostScope == .allHosts {
            await multiHostCoordinator.stop(reason: reason)
        } else {
            await controller.stop(reason: reason)
        }
    }

    private func refreshSnapshot() async {
        if hostScope == .allHosts {
            await refreshAllHostsSnapshot()
        } else {
            snapshot = await controller.snapshot()
            rebuildGraphSamples()
            await publishWidgetSnapshot()
        }
        recordLifecycleRefresh()
    }

    private func recordLifecycleRefresh() {
        guard let session = presentedSession else {
            lifecycleHarness.recordRefresh(sessionIdentity: nil, coordinatorState: .idle)
            return
        }
        let focusedHostID = hostScope == .focused ? snapshot.host.id : nil
        let identity: PingScopeIOSLifecycleSessionIdentity
        if let currentIdentity = lifecycleHarness.currentSessionIdentity,
           currentIdentity.describes(
               scope: hostScope,
               focusedHostID: focusedHostID,
               startedAt: session.startedAt
           ) {
            identity = currentIdentity
        } else {
            identity = PingScopeIOSLifecycleSessionIdentity(
                scope: hostScope,
                focusedHostID: focusedHostID,
                startedAt: session.startedAt
            )
        }
        lifecycleHarness.recordRefresh(
            sessionIdentity: identity,
            coordinatorState: session.phase() == .ended ? .ended : .active
        )
    }

    private func invalidateLifecycleSession() {
        lifecycleHarness.recordRefresh(sessionIdentity: nil, coordinatorState: .idle)
    }

    private func refreshAllHostsSnapshot() async {
        let snapshots = await multiHostCoordinator.orderedSnapshots()
        let presentationEndDate = Date()
        allHostRows = snapshots.map { snapshot in
            PingScopeIOSHostRowSnapshot(
                host: snapshot.host,
                health: snapshot.health,
                samples: snapshot.series.samples,
                isStale: snapshot.session.map { $0.phase() != .live } ?? false
            )
        }
        allHostGraphSeries = snapshots.map { snapshot in
            PingScopeIOSHostGraphSeries(hostID: snapshot.host.id, samples: snapshot.series.samples)
        }
        allHostsPresentationEndDate = presentationEndDate

        guard let session = await multiHostCoordinator.session() else {
            allHostsSession = nil
            return
        }
        let latestResult = snapshots.compactMap(\.health.latestResult).max { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        let placeholderHostID = snapshots.first?.host.id ?? snapshot.host.id
        allHostsSession = MonitorSessionState(
            hostID: placeholderHostID,
            duration: session.duration,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            endReason: session.endReason,
            latestResult: latestResult
        )
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

    private func beginBackgroundRuntimeIfNeeded(originatingAt sceneEpoch: PingScopeIOSLifecycleSceneEpoch) async {
        guard let session = presentedSession, session.phase() != .ended else { return }
        await backgroundRuntime.begin { [weak self] in
            guard let self else { return }
            await self.lifecycleHarness.enqueueBackgroundExpiration(originatingAt: sceneEpoch) { [weak self] in
                await self?.expireForBackgroundRuntime()
            }.value
        }
    }

    private func expireForBackgroundRuntime(context: LifecycleContext? = nil) async {
        cancelRefreshLoop()
        await stopMonitoring(reason: .backgroundRuntimeExpired)
        guard isCurrentLifecycle(context) else { return }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        if hostScope == .focused {
            await refreshHistory(force: true)
            guard isCurrentLifecycle(context) else { return }
        }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        applyBackgroundKeepAlive()
    }

    private func startLiveActivity(duration: MonitorSessionDuration) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let session = presentedSession,
              let attributes = liveActivityAttributes(duration: duration) else { return }

        do {
            if liveActivity != nil {
                await updateLiveActivity()
                return
            }
            let state = liveActivityContentState(session: session)
            let staleDate = session.scheduledEndAt
            let requestedActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate),
                pushType: nil
            )
            let lease = await lifecycleHarness.claimActivity()
            liveActivity = requestedActivity
            liveActivityLease = lease
        } catch {
            NSLog("PingScope live activity request failed: \(String(describing: error))")
        }
    }

    private func updateLiveActivity() async {
        guard let liveActivity, let session = presentedSession else { return }
        let state = liveActivityContentState(session: session)
        await liveActivity.update(ActivityContent(state: state, staleDate: session.scheduledEndAt))
    }

    private func ensureLiveActivityForCurrentSession() async {
        await refreshSnapshot()
        await ensureLiveActivityForPresentedSession()
    }

    private func ensureLiveActivityForPresentedSession() async {
        let session = presentedSession
        let decision = PingScopeIOSLiveActivityAvailabilityDecision.decide(
            isSessionActive: session.map { $0.phase() != .ended } ?? false,
            hasPlaceholderHost: hostScope == .focused
                || !PingScopeIOSHostScopePresentation.enabledHosts(from: hosts).isEmpty,
            hasActivity: liveActivity != nil
        )
        switch decision {
        case .none:
            return
        case .request:
            guard let session else { return }
            await startLiveActivity(duration: session.duration)
        case .update:
            await updateLiveActivity()
        }
    }

    private func restartContinuousSessionAfterBackgroundExpirationIfNeeded(context: LifecycleContext? = nil) async {
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        guard let session = presentedSession,
              session.duration == .continuous,
              session.phase() == .ended,
              session.endReason == .backgroundRuntimeExpired else {
            return
        }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        invalidateLifecycleSession()
        await startMonitoring(duration: .continuous)
        guard isCurrentLifecycle(context) else { return }
        await refreshSnapshot()
        guard isCurrentLifecycle(context) else { return }
        await startLiveActivity(duration: .continuous)
        guard isCurrentLifecycle(context) else { return }
        applyBackgroundKeepAlive()
        startRefreshLoop()
    }

    private func endLiveActivity() async {
        guard let endingActivity = liveActivity else { return }
        let endingLease = liveActivityLease
        if let session = presentedSession {
            let state = liveActivityContentState(session: session)
            await endingActivity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        } else {
            await endingActivity.end(nil, dismissalPolicy: .immediate)
        }
        guard let endingLease else {
            if liveActivity?.id == endingActivity.id {
                liveActivity = nil
            }
            return
        }
        if await lifecycleHarness.clearActivity(ifCurrent: endingLease), liveActivityLease == endingLease {
            liveActivity = nil
            liveActivityLease = nil
        }
    }

    private func liveActivityAttributes(duration: MonitorSessionDuration) -> PingScopeLiveActivityAttributes? {
        guard hostScope == .allHosts else {
            return PingScopeLiveActivityAttributes(host: snapshot.host, duration: duration)
        }
        guard var placeholder = PingScopeIOSHostScopePresentation.enabledHosts(from: hosts).first else {
            return nil
        }
        // Activity attributes are immutable. All Hosts uses the first enabled
        // host only as a stable identity placeholder; mode and rows stay in state.
        placeholder.displayName = "All Hosts"
        return PingScopeLiveActivityAttributes(host: placeholder, duration: duration)
    }

    private func liveActivityContentState(
        session: MonitorSessionState,
        at date: Date = Date()
    ) -> PingScopeLiveActivityAttributes.ContentState {
        guard hostScope == .allHosts else {
            let latestResult = session.latestResult ?? snapshot.health.latestResult
            return PingScopeLiveActivityAttributes.ContentState(
                latencyMilliseconds: latestResult?.latency.map { Int($0.milliseconds.rounded()) },
                status: snapshot.health.status,
                lastUpdatedAt: latestResult?.timestamp,
                remainingSeconds: session.duration == .continuous
                    ? 0
                    : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
                isStale: session.phase(at: date) != .live,
                failureMessage: latestResult?.failureReason?.userMessage,
                mode: .focused
            )
        }

        let activityRows = PingScopeIOSHostScopePresentation.activityRows(from: allHostRows)
            .map(PingScopeLiveActivityHostRow.init(snapshot:))
        let latestResult = allHostGraphSeries
            .flatMap(\.samples)
            .max { lhs, rhs in lhs.timestamp < rhs.timestamp }
        return PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: nil,
            status: aggregateAllHostsStatus,
            lastUpdatedAt: latestResult?.timestamp,
            remainingSeconds: session.duration == .continuous
                ? 0
                : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
            isStale: session.phase(at: date) != .live,
            mode: .allHosts,
            hostRows: activityRows
        )
    }

    private var aggregateAllHostsStatus: HealthStatus {
        let statuses = allHostRows.map(\.status)
        if statuses.contains(.down) { return .down }
        if statuses.contains(.degraded) { return .degraded }
        if statuses.contains(.healthy) { return .healthy }
        return .noData
    }
}

@MainActor
private final class UIApplicationPromptBackgroundProtectionClient: PingScopeIOSPromptBackgroundProtectionClient {
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    func beginPromptBackgroundProtection() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "PingScope Lifecycle Handoff") { [weak self] in
            Task { @MainActor in
                self?.endPromptBackgroundProtection()
            }
        }
    }

    func endPromptBackgroundProtection() {
        guard taskID != .invalid else { return }
        let endingTaskID = taskID
        taskID = .invalid
        UIApplication.shared.endBackgroundTask(endingTaskID)
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

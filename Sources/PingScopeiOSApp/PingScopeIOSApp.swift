import ActivityKit
import Combine
import CoreLocation
import CoreTelephony
import Darwin
import Network
import NetworkExtension
import PingScopeCore
import PingScopeHistoryKit
import PingScopeiOS
import SwiftUI
import UIKit
import WidgetKit

@MainActor
private struct ActivityKitLiveActivityDirectory: PingScopeIOSLiveActivityDirectory {
    var currentActivities: [Activity<PingScopeLiveActivityAttributes>] {
        Activity<PingScopeLiveActivityAttributes>.activities
    }

    func end(_ activity: Activity<PingScopeLiveActivityAttributes>) async {
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}

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
                historyRange: model.historyRange,
                historyPresentationState: model.historyPresentationState,
                historyLens: model.historyLens,
                historyMapLens: model.effectiveHistoryMapLens,
                historyLocationAuthorization: model.historyLocationAuthorization,
                historyLocationTaggingOptIn: model.historyLocationTaggingEnabled,
                historyMapContent: { selection, presentation, lens in
                    AnyView(
                        PingScopeIOSHistoryMapView(
                            selection: selection,
                            resolvedPresentation: presentation,
                            selectedLens: lens,
                            onSelectLens: { selectedLens in
                                model.selectHistoryMapLens(selectedLens)
                            },
                            onShare: { format in
                                model.requestHistoryExport(format: format)
                            },
                            onShareReport: { format in
                                model.requestHistoryReport(format: format)
                            },
                            onShareMap: { presentation, lens, visibleRegion in
                                model.requestHistoryMapExport(
                                    presentation: presentation,
                                    lens: lens,
                                    visibleRegion: visibleRegion
                                )
                            }
                        )
                    )
                },
                selectedGraphRange: model.selectedGraphRange,
                gatewayDetectionText: model.gatewayDetectionText,
                backgroundKeepAliveEnabled: model.backgroundKeepAliveEnabled,
                backgroundKeepAliveStatus: model.backgroundKeepAliveStatus,
                // Pass the raw stored preference: the view derives the effective
                // mode itself (effectiveDisplayMode), and pre-resolving here made
                // the Display picker show the coerced mode in All Hosts scope.
                displayMode: model.displayMode,
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
                onSelectHistoryRange: { range in
                    model.selectHistoryRange(range)
                },
                onSelectHistoryLens: { lens in
                    model.selectHistoryLens(lens)
                },
                onSelectHistoryMapLens: { lens in
                    model.selectHistoryMapLens(lens)
                },
                onRequestHistoryMapPermission: {
                    model.requestHistoryMapPermission()
                },
                onShareHistory: { format in
                    model.requestHistoryExport(format: format)
                },
                onShareHistoryReport: { format in
                    model.requestHistoryReport(format: format)
                },
                onRefreshHistory: { hostID, range in
                    await model.refreshHistoryPresentation(hostID: hostID, range: range)
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
            .sheet(item: Binding(
                get: { model.historySharePayload },
                set: { payload in
                    if payload == nil { model.historyShareSheetDismissed() }
                }
            )) { payload in
                HistoryActivityViewController(files: payload.files) { completed in
                    model.historyShareActivityDidFinish(completed: completed)
                }
            }
            .alert(
                "Unable to Share History",
                isPresented: Binding(
                    get: { model.historyExportErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { model.dismissHistoryExportError() }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.dismissHistoryExportError()
                }
            } message: {
                Text(model.historyExportErrorMessage ?? "The export could not be created.")
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
    @Published var historyRange: HistoryRange {
        didSet {
            UserDefaults.standard.pingScopeIOSHistoryRange = historyRange
        }
    }
    @Published var historyLens: HistoryLens {
        didSet {
            UserDefaults.standard.pingScopeIOSHistoryLens = historyLens
        }
    }
    @Published var historyMapLensOverride: HistoryMapLens? {
        didSet {
            UserDefaults.standard.pingScopeIOSHistoryMapLensOverride = historyMapLensOverride
        }
    }
    @Published private(set) var historyLocationAuthorization: PingScopeIOSHistoryLocationAuthorization
    @Published var historyPresentationState = PingScopeIOSHistoryPresentationState.loading(
        selection: PingScopeIOSHistorySelection(hostID: HostConfig.defaultInternet.id, range: .defaultValue)
    )
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
    private let historyLoader = PingScopeIOSHistoryLoader()
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let gatewayDetector = PingScopeIOSGatewayDetector()
    private let presenter = DisplayStatePresenter()
    private let backgroundRuntime: LiveMonitorBackgroundRuntime
    private let multiHostCoordinator: PingScopeIOSMultiHostSessionCoordinator
    private let historyLocationService: HistoryLocationService
    private var historyExportCoordinator: HistoryExportCoordinator?
    private var historyExportObservation: AnyCancellable?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "PingScope.iOS.NetworkPath")
    private var controller: LiveMonitorSessionController
    private var refreshTask: Task<Void, Never>?
    private let lifecycleHarness = PingScopeIOSLifecycleHarness(
        promptBackgroundProtectionClient: UIApplicationPromptBackgroundProtectionClient()
    )
    private var liveActivity: Activity<PingScopeLiveActivityAttributes>?
    private var liveActivityLease: PingScopeIOSActivityOwnershipLease?
    private var liveActivityUpdatePolicy = PingScopeIOSLiveActivityUpdatePolicy()
    private var initialSessionCoordinator = PingScopeIOSInitialSessionCoordinator()
    private var lastGatewayAddress: String?
    @Published private(set) var historyLocationTaggingEnabled: Bool
    private var lastHistoryRefreshAt: Date?
    private var lastPublishedWidgetSnapshot: WidgetSnapshot?
    private var lastWidgetTimelineReloadAt: Date?
    private let widgetPublishPolicy = WidgetSnapshotPublishPolicy()

    init() {
        self.hostStore = PingScopeIOSHostStore()
        let locationService = HistoryLocationService()
        let historySampleEnricher = locationService.snapshotStore.makeHistorySampleEnricher()
        self.historyLocationService = locationService
        let loadedHistoryStore: (any PingHistoryStore)?
        do {
            loadedHistoryStore = try SQLiteHistoryStore(
                url: SQLiteHistoryStore.defaultURL(appName: "PingScope-iOS"),
                retention: PingHistoryRetention.maximumDuration
            )
        } catch {
            NSLog("PingScope iOS history store unavailable: \(String(describing: error))")
            #if DEBUG
            print("PingScope iOS history store unavailable: \(error)")
            #endif
            loadedHistoryStore = nil
        }
        self.historyStore = loadedHistoryStore
        self.multiHostCoordinator = PingScopeIOSMultiHostSessionCoordinator(
            historyStore: loadedHistoryStore,
            historySampleEnricher: historySampleEnricher
        )
        self.backgroundRuntime = LiveMonitorBackgroundRuntime(client: UIApplicationBackgroundTaskClient())
        self.backgroundKeepAliveEnabled = UserDefaults.standard.bool(forKey: Self.backgroundKeepAliveEnabledKey)
        self.displayMode = UserDefaults.standard.pingScopeIOSDisplayMode
        let loadedHistoryRange = UserDefaults.standard.pingScopeIOSHistoryRange
        self.historyRange = loadedHistoryRange
        self.historyLens = UserDefaults.standard.pingScopeIOSHistoryLens
        self.historyMapLensOverride = UserDefaults.standard.pingScopeIOSHistoryMapLensOverride
        self.historyLocationAuthorization = locationService.authorization
        self.historyLocationTaggingEnabled = UserDefaults.standard.bool(
            forKey: Self.historyLocationTaggingEnabledKey
        )
        let state = hostStore.load()
        let host = state.selectedHost
        self.hosts = state.hosts
        self.hostScope = state.hostScope
        self.historyPresentationState = .loading(
            selection: PingScopeIOSHistorySelection(hostID: host.id, range: loadedHistoryRange)
        )
        self.controller = LiveMonitorSessionController(
            host: host,
            historyStore: loadedHistoryStore,
            historySampleEnricher: historySampleEnricher
        )
        self.snapshot = LiveMonitorSessionSnapshot(
            host: host,
            session: nil,
            health: HostHealth(hostID: host.id, thresholds: host.thresholds)
        )
        self.graphPresentation = PingScopeIOSGraphPresentation(samples: snapshot.series.samples, range: selectedGraphRange)
        let exportCoordinator = HistoryExportCoordinator(
            store: loadedHistoryStore,
            service: HistoryExportService()
        )
        self.historyExportCoordinator = exportCoordinator
        self.historyExportObservation = exportCoordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        Task { @MainActor [weak self] in
            self?.runLifecycleTask { model, context in
                // Nothing owns an activity yet at launch, so anything the system
                // still shows is an orphan from a crashed or force-quit process;
                // left alone it lingers frozen for hours and a fresh request
                // would stack a second activity on the lock screen.
                await model.endOrphanedLiveActivities()
                guard model.isCurrentLifecycle(context) else { return }
                if model.hostScope == .allHosts {
                    await model.multiHostCoordinator.reconcile(hosts: model.hosts)
                    guard model.isCurrentLifecycle(context) else { return }
                    await model.refreshSnapshot()
                    guard model.isCurrentLifecycle(context) else { return }
                }
                await model.refreshHistory(force: true)
            }
        }
        locationService.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.backgroundKeepAliveStatus = status
        }
        locationService.onAuthorizationChange = { [weak self] authorization in
            guard let self else { return }
            self.historyLocationAuthorization = authorization
            self.applyBackgroundKeepAlive()
            self.refreshWiFiNameIfAuthorized()
        }
        applyBackgroundKeepAlive()
        startNetworkPathMonitoring()
    }

    var presentedSession: MonitorSessionState? {
        hostScope == .allHosts ? allHostsSession : snapshot.session
    }

    var effectiveHistoryMapLens: HistoryMapLens {
        HistoryMapLens.effective(for: historyRange, override: historyMapLensOverride)
    }

    var historySharePayload: HistorySharePayload? {
        historyExportCoordinator?.sharePayload
    }

    var historyExportErrorMessage: String? {
        historyExportCoordinator?.errorMessage
    }

    func selectHistoryRange(_ range: HistoryRange) {
        guard historyRange != range else { return }
        historyRange = range
        historyPresentationState = .loading(
            selection: PingScopeIOSHistorySelection(hostID: snapshot.host.id, range: range)
        )
    }

    func selectHistoryLens(_ lens: HistoryLens) {
        historyLens = lens
    }

    func selectHistoryMapLens(_ lens: HistoryMapLens) {
        historyMapLensOverride = lens
    }

    func requestHistoryMapPermission() {
        let authorization = HistoryMapAuthorizationPresentation(
            authorization: historyLocationAuthorization,
            taggingOptIn: historyLocationTaggingEnabled
        )
        guard authorization.requestDecision != .none else { return }
        historyLocationTaggingEnabled = true
        UserDefaults.standard.set(true, forKey: Self.historyLocationTaggingEnabledKey)
        applyBackgroundKeepAlive()
        if authorization.requestDecision == .requestWhenInUse {
            historyLocationService.requestWhenInUseAuthorization()
        }
    }

    func requestHistoryExport(format: HistoryExportFormat) {
        let requestedHost = snapshot.host
        let requestedRange = historyRange
        Task { @MainActor [weak self] in
            await self?.historyExportCoordinator?.requestExport(
                host: requestedHost,
                range: requestedRange,
                format: format,
                now: Date()
            )
        }
    }

    func requestHistoryReport(format: HistoryReportFormat) {
        let selection = PingScopeIOSHistorySelection(hostID: snapshot.host.id, range: historyRange)
        guard case let .loaded(loadedSelection, historyPresentation) = historyPresentationState,
              loadedSelection == selection else {
            return
        }
        let report = HistoryReportPresentation(
            host: snapshot.host,
            range: historyRange,
            samples: historyPresentation.sourceSamples
        )
        Task { @MainActor [weak self] in
            await self?.historyExportCoordinator?.requestReport(
                presentation: report,
                format: format
            )
        }
    }

    func requestHistoryMapExport(
        presentation: HistoryMapPresentation,
        lens: HistoryMapLens,
        visibleRegion: HistoryMapExportRegion
    ) {
        let requestedHost = snapshot.host
        let requestedRange = historyRange
        let selection = PingScopeIOSHistorySelection(hostID: requestedHost.id, range: requestedRange)
        guard case let .loaded(loadedSelection, historyPresentation) = historyPresentationState,
              loadedSelection == selection,
              historyPresentation.mapPresentation == presentation else {
            return
        }
        let request = HistoryMapExportRequest(
            host: requestedHost,
            range: requestedRange,
            lens: lens,
            presentation: presentation,
            visibleRegion: visibleRegion
        )
        Task { @MainActor [weak self] in
            await self?.historyExportCoordinator?.requestMap(request)
        }
    }

    func historyShareActivityDidFinish(completed: Bool) {
        historyExportCoordinator?.activityDidFinish(completed: completed)
    }

    func historyShareSheetDismissed() {
        historyExportCoordinator?.activityDidFinish(completed: false)
    }

    func dismissHistoryExportError() {
        historyExportCoordinator?.dismissError()
    }

    func refreshHistoryPresentation(hostID: UUID, range: HistoryRange) async {
        let trigger = PingScopeIOSHistoryRefreshTrigger.historyVisible(
            PingScopeIOSHistorySelection(hostID: hostID, range: range)
        )
        guard let selection = PingScopeIOSHistoryRangedRefreshPolicy.selection(for: trigger),
              snapshot.host.id == selection.hostID,
              historyRange == selection.range else {
            return
        }
        historyPresentationState = .loading(selection: selection)
        await refreshRangedHistory(selection: selection, now: Date())
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
            historyLocationService.requestAlwaysAuthorization()
        }
        applyBackgroundKeepAlive()
    }

    func requestBackgroundKeepAlivePermission() {
        historyLocationService.requestAlwaysAuthorization()
        backgroundKeepAliveStatus = historyLocationService.statusText()
    }

    func setHistoryLocationTaggingEnabled(_ isEnabled: Bool) {
        historyLocationTaggingEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.historyLocationTaggingEnabledKey)
        if isEnabled {
            historyLocationService.requestWhenInUseAuthorization()
        }
        applyBackgroundKeepAlive()
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
            await model.refreshHistory(force: true)
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
                // History backs the History tab in both scopes; the query keys
                // on the remembered focused host, which stays valid in All Hosts.
                await refreshHistoryIfStale()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func completeFiniteSession() async {
        cancelRefreshLoop()
        if hostScope == .allHosts {
            await stopMonitoring(reason: .completed)
            await refreshSnapshot()
        }
        await refreshHistory(force: true)
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
    private static let historyLocationTaggingEnabledKey = "PingScope.iOS.historyLocationTaggingEnabled"

    private func startNetworkPathMonitoring() {
        let locationSnapshotStore = historyLocationService.snapshotStore
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let interface = Self.networkInterface(from: path)
            let capture = NetworkCaptureResolver(
                activeInterfaceNames: Self.activeNetworkInterfaceNames,
                wifiName: { nil },
                cellularRadio: Self.currentCellularRadio
            ).snapshot(interface: interface)
            locationSnapshotStore.updateNetwork(
                interface: capture.interface,
                name: capture.name,
                isVPN: capture.isVPN
            )
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.refreshWiFiNameIfAuthorized()
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

    nonisolated private static func networkInterface(from path: Network.NWPath) -> String {
        guard path.status == .satisfied else { return "other" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    nonisolated private static func activeNetworkInterfaceNames() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(first) }

        var names: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let flags = Int32(interface.pointee.ifa_flags)
            if flags & IFF_UP != 0, let name = interface.pointee.ifa_name {
                names.append(String(cString: name))
            }
            current = interface.pointee.ifa_next
        }
        return names
    }

    nonisolated private static func currentCellularRadio() -> String? {
        guard let technology = CTTelephonyNetworkInfo()
            .serviceCurrentRadioAccessTechnology?
            .values
            .first else { return nil }
        return switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: "5G"
        case CTRadioAccessTechnologyLTE: "LTE"
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMA1x,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB: "3G"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS: "2G"
        default: nil
        }
    }

    private func refreshWiFiNameIfAuthorized() {
        let isAllowed = PingScopeIOSWiFiNameReadPolicy.isAllowed(
            // The iOS target's declared capability is pinned by
            // CorePlatformImportGuardTests; the public API also returns nil
            // when the signed provisioning profile lacks the entitlement.
            hasWiFiInfoEntitlement: true,
            authorization: historyLocationAuthorization,
            networkInterface: historyLocationService.snapshotStore.snapshot().networkInterface
        )
        guard isAllowed else {
            historyLocationService.snapshotStore.clearNetworkName(ifInterfaceMatches: "wifi")
            return
        }

        Task { @MainActor [weak self] in
            guard let name = await Self.currentWiFiName(), !name.isEmpty, let self else { return }
            self.historyLocationService.snapshotStore.updateFetchedWiFiName(
                name,
                hasWiFiInfoEntitlement: true,
                authorization: self.historyLocationAuthorization
            )
        }
    }

    nonisolated private static func currentWiFiName() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
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
        hosts.firstIndex(where: \.isDefaultGateway)
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
        // Honor the decision contract: .update keeps the existing activity alive
        // (startLiveActivity routes an existing activity to update()); ending it
        // here would flicker the lock screen on a same-host reselect.
        if activityDecision != .update, liveActivity != nil {
            await endLiveActivity()
        }
        guard isCurrentLifecycle(context) else { return }

        hostScope = .focused
        if saveSelection {
            hostStore.save(hosts: hosts, selectedHostID: host.id, hostScope: .focused)
        }
        controller = LiveMonitorSessionController(
            host: host,
            historyStore: historyStore,
            historySampleEnricher: historyLocationService.snapshotStore.makeHistorySampleEnricher()
        )
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
        // Honor the decision contract: .update keeps the existing activity alive.
        if activityDecision != .update, liveActivity != nil {
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
        controller = LiveMonitorSessionController(
            host: host,
            historyStore: historyStore,
            historySampleEnricher: historyLocationService.snapshotStore.makeHistorySampleEnricher()
        )
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
        historyLocationService.setState(
            keepAliveEnabled: backgroundKeepAliveEnabled,
            taggingEnabled: historyLocationTaggingEnabled,
            monitoringActive: isMonitoringActive
        )
        backgroundKeepAliveStatus = historyLocationService.statusText()
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
            let activeController = controller
            let refreshedSnapshot = await activeController.snapshot()
            // A host switch may have replaced the controller while we were
            // suspended (the refresh loop is not serialized with lifecycle ops);
            // a stale snapshot must not overwrite the new host's state.
            guard activeController === controller else { return }
            snapshot = refreshedSnapshot
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
        // A scope switch may have landed while we were suspended; stale
        // all-hosts data must not overwrite the focused presentation.
        guard hostScope == .allHosts else { return }
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
        // The widget must keep updating in All Hosts scope too; without this the
        // app-group snapshot freezes at the moment of the scope switch.
        await publishWidgetSnapshot(allHostsSnapshots: snapshots)

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
        let requestedHostID = snapshot.host.id
        let samples = await historyStore.latestSamples(hostID: requestedHostID, since: cutoff, limit: 100)
        // Drop the result if a host switch happened while we were suspended:
        // the 30s throttle would otherwise pin the wrong host's history.
        guard snapshot.host.id == requestedHostID else { return }
        historySamples = samples
        rebuildGraphSamples()
        await publishWidgetSnapshot()
    }

    private func refreshRangedHistory(
        selection: PingScopeIOSHistorySelection,
        now: Date
    ) async {
        let result: PingScopeIOSHistoryLoadResult
        if let historyStore {
            guard let loaded = await historyLoader.load(
                store: historyStore,
                hostID: selection.hostID,
                range: selection.range,
                now: now
            ) else {
                return
            }
            result = loaded
        } else {
            result = PingScopeIOSHistoryLoadResult(
                hostID: selection.hostID,
                range: selection.range,
                cutoff: selection.range.cutoff(endingAt: now),
                endingAt: now,
                samples: [],
                chartReduction: HistoryChartReduction(samples: []),
                isCollecting: false
            )
        }

        guard snapshot.host.id == selection.hostID,
              historyRange == selection.range else { return }
        let thresholds = snapshot.host.thresholds
        let presentation = await Task.detached(priority: .userInitiated) {
            PingScopeIOSHistoryPresentation(loadResult: result, thresholds: thresholds)
        }.value
        // Host or range may change while the detached presentation work runs.
        guard snapshot.host.id == selection.hostID,
              historyRange == selection.range else { return }
        historyPresentationState = .loaded(selection: selection, presentation: presentation)
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

    private func publishWidgetSnapshot(allHostsSnapshots: [LiveMonitorSessionSnapshot]? = nil) async {
        let widgetSnapshot: WidgetSnapshot
        if hostScope == .allHosts {
            let snapshots: [LiveMonitorSessionSnapshot]
            if let allHostsSnapshots {
                snapshots = allHostsSnapshots
            } else {
                snapshots = await multiHostCoordinator.orderedSnapshots()
            }
            widgetSnapshot = makeAllHostsWidgetSnapshot(snapshots: snapshots)
        } else {
            widgetSnapshot = makeFocusedWidgetSnapshot()
        }
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

    private func makeFocusedWidgetSnapshot() -> WidgetSnapshot {
        let host = snapshot.host
        let recentResults = presenter.mergedSamples(
            history: historySamples,
            live: snapshot.series.samples,
            range: .tenMinutes
        )
        .suffix(60)

        return WidgetSnapshot(
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
    }

    private func makeAllHostsWidgetSnapshot(snapshots: [LiveMonitorSessionSnapshot]) -> WidgetSnapshot {
        let hosts = snapshots.map { entry in
            WidgetHost(
                id: entry.host.id,
                displayName: entry.host.displayName,
                address: entry.host.address,
                method: entry.host.method,
                port: entry.host.port,
                isPrimary: entry.host.id == snapshot.host.id
            )
        }
        let health = snapshots.map { entry in
            WidgetHostHealth(
                hostID: entry.host.id,
                status: entry.health.status,
                latencyMilliseconds: entry.health.latestResult?.latency?.milliseconds,
                consecutiveFailureCount: entry.health.consecutiveFailureCount,
                failureReason: entry.health.latestResult?.failureReason,
                latestResultAt: entry.health.latestResult?.timestamp
            )
        }
        let recentResults = snapshots
            .flatMap { $0.series.samples.suffix(60) }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(60)
        return WidgetSnapshot(
            primaryHostID: snapshot.host.id,
            hosts: hosts,
            health: health,
            recentSamples: recentResults.map(WidgetSample.init(result:)),
            networkStatus: .connected,
            generatedAt: Date()
        )
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
        await refreshHistory(force: true)
        guard isCurrentLifecycle(context) else { return }
        await endLiveActivity()
        guard isCurrentLifecycle(context) else { return }
        applyBackgroundKeepAlive()
    }

    private func endOrphanedLiveActivities() async {
        guard liveActivity == nil else { return }
        let directory = ActivityKitLiveActivityDirectory()
        for orphan in directory.currentActivities {
            await directory.end(orphan)
        }
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
            let requestedActivity = try await PingScopeIOSLiveActivityStartup.requestReplacingOrphans(
                in: ActivityKitLiveActivityDirectory()
            ) {
                try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: staleDate),
                    pushType: nil
                )
            }
            let lease = await lifecycleHarness.claimActivity()
            liveActivity = requestedActivity
            liveActivityLease = lease
            _ = liveActivityUpdatePolicy.shouldPublish(state)
        } catch {
            NSLog("PingScope live activity request failed: \(String(describing: error))")
        }
    }

    private func updateLiveActivity() async {
        await releaseLiveActivityIfDefunct()
        guard let liveActivity, let session = presentedSession else { return }
        let state = liveActivityContentState(session: session)
        guard liveActivityUpdatePolicy.shouldPublish(state) else { return }
        await liveActivity.update(ActivityContent(state: state, staleDate: session.scheduledEndAt))
    }

    /// A user-dismissed or system-ended activity never notifies us; holding its
    /// reference would pin the availability decision to `.update` on a dead
    /// activity for the rest of the session, so a fresh one is never requested.
    private func releaseLiveActivityIfDefunct() async {
        guard let activity = liveActivity,
              activity.activityState == .dismissed || activity.activityState == .ended else { return }
        if let lease = liveActivityLease {
            _ = await lifecycleHarness.clearActivity(ifCurrent: lease)
        }
        liveActivity = nil
        liveActivityLease = nil
        liveActivityUpdatePolicy.reset()
    }

    private func ensureLiveActivityForCurrentSession() async {
        await refreshSnapshot()
        await ensureLiveActivityForPresentedSession()
    }

    private func ensureLiveActivityForPresentedSession() async {
        await releaseLiveActivityIfDefunct()
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
                liveActivityUpdatePolicy.reset()
            }
            return
        }
        if await lifecycleHarness.clearActivity(ifCurrent: endingLease), liveActivityLease == endingLease {
            liveActivity = nil
            liveActivityLease = nil
            liveActivityUpdatePolicy.reset()
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
            return PingScopeIOSLiveActivityContentStateBuilder.focused(
                host: snapshot.host,
                session: session,
                health: snapshot.health,
                samples: snapshot.series.samples,
                at: date
            )
        }

        let activityRows = PingScopeIOSHostScopePresentation.activityRows(from: allHostRows)
            .map(PingScopeLiveActivityHostRow.init(snapshot:))
        let latestResult = allHostGraphSeries
            .flatMap(\.samples)
            .max { lhs, rhs in lhs.timestamp < rhs.timestamp }
        return PingScopeLiveActivityAttributes.ContentState(
            latencyMilliseconds: nil,
            status: PingScopeIOSHostScopePresentation.aggregateStatus(from: allHostRows),
            lastUpdatedAt: latestResult?.timestamp,
            remainingSeconds: session.duration == .continuous
                ? 0
                : Int(session.remainingDuration(at: date).seconds.rounded(.down)),
            isStale: session.phase(at: date) != .live,
            mode: .allHosts,
            hostRows: activityRows
        )
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

import AppKit
import Combine
import Foundation
@preconcurrency import Network
import PingScopeCore
import PingScopeCloudSync
import PingScopeHistoryKit
import ServiceManagement
import WidgetKit
#if DEBUG
import os

private let snapshotPointsOfInterestLog = OSLog(
    subsystem: "tv.kodi.pingscope",
    category: .pointsOfInterest
)
#endif

typealias DisplayPresentationSampleFingerprint = PerHostSampleFingerprint

struct DisplayPresentationInputKey: Equatable {
    let visibleSamples: DisplayPresentationSampleFingerprint
    let selectedRange: TimeRange
    let includesAllHosts: Bool
    let primaryHost: HostConfig?
    let hosts: [HostConfig]
    let healthByHost: [UUID: HostHealth]
    let allHostVisibleSamples: [UUID: DisplayPresentationSampleFingerprint]?

    init(
        visibleSamples: [PingResult],
        selectedRange: TimeRange,
        includesAllHosts: Bool,
        primaryHost: HostConfig?,
        hosts: [HostConfig],
        healthByHost: [UUID: HostHealth],
        allHostVisibleSamples: [UUID: [PingResult]]?
    ) {
        self.visibleSamples = DisplayPresentationSampleFingerprint(samples: visibleSamples)
        self.selectedRange = selectedRange
        self.includesAllHosts = includesAllHosts
        self.primaryHost = primaryHost
        self.hosts = hosts
        self.healthByHost = healthByHost
        self.allHostVisibleSamples = allHostVisibleSamples?.mapValues { samples in
            DisplayPresentationSampleFingerprint(samples: samples)
        }
    }
}

@MainActor
final class DisplayPresentationRecomputeScheduler {
    private let delay: Duration
    private var task: Task<Void, Never>?
    private(set) var needsRecompute = false

    init(delay: Duration = .milliseconds(200)) {
        self.delay = delay
    }

    func schedule(_ operation: @escaping @MainActor () -> Void) {
        needsRecompute = true
        guard task == nil else { return }

        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            task = nil
            guard needsRecompute else { return }
            needsRecompute = false
            operation()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        needsRecompute = false
    }
}

@MainActor
final class LiveDisplayModel: ObservableObject {
    @Published private(set) var snapshot: RuntimeSnapshot
    @Published private(set) var displayPresentation: PingScopeDisplayPresentation

    init(
        snapshot: RuntimeSnapshot = RuntimeSnapshot(
            hosts: HostConfig.defaultHosts(),
            primaryHostID: HostConfig.defaultInternet.id,
            healthByHost: [:],
            samplesByHost: [:]
        ),
        displayPresentation: PingScopeDisplayPresentation? = nil
    ) {
        self.snapshot = snapshot
        self.displayPresentation = displayPresentation ?? PingScopeDisplayPresentation()
    }

    func updateSnapshot(_ snapshot: RuntimeSnapshot) {
        self.snapshot = snapshot
    }

    func updateDisplayPresentation(_ displayPresentation: PingScopeDisplayPresentation) {
        self.displayPresentation = displayPresentation
    }
}

@MainActor
final class PingScopeModel: NSObject, ObservableObject, NSWindowDelegate {
    nonisolated static let historyRetention = PingHistoryRetention.maximumDuration

    let liveDisplay: LiveDisplayModel
    var snapshot: RuntimeSnapshot { liveDisplay.snapshot }
    var displayPresentation: PingScopeDisplayPresentation { liveDisplay.displayPresentation }
    @Published private(set) var configuredHosts = HostConfig.defaultHosts()
    @Published private(set) var configuredPrimaryHostID: UUID? = HostConfig.defaultInternet.id

    var configuredPrimaryHost: HostConfig? {
        guard let configuredPrimaryHostID else { return configuredHosts.first }
        return configuredHosts.first { $0.id == configuredPrimaryHostID } ?? configuredHosts.first
    }

    @Published var selectedRange: TimeRange = .fiveMinutes {
        didSet {
            recomputeDisplayPresentation()
            refreshVisibleHistory()
        }
    }
    @Published var draftHostName = ""
    @Published var draftHostAddress = ""
    @Published var draftHostID = UUID()
    @Published var draftNetworkTier: NetworkTier?
    @Published var draftMethod: PingMethod = .https
    @Published var draftPort: Int = Int(PingMethod.https.defaultPort ?? 0)
    @Published var draftIntervalMilliseconds: Double = 2_000
    @Published var draftTimeoutMilliseconds: Double = 2_000
    @Published var draftDegradedThresholdMilliseconds: Double = LatencyThresholds.defaults.degradedMilliseconds
    @Published var draftDownAfterFailures: Int = LatencyThresholds.defaults.downAfterFailures
    @Published var draftIsEnabled = true
    @Published var draftNotificationPolicy: HostNotificationPolicy = .inherit
    @Published var draftDisplayColor: HostDisplayColor?
    @Published var draftTestResultText: String?
    @Published private(set) var isTestingDraftHost = false
    @Published var editingHostID: UUID?
    @Published var isCreatingHost = false
    @Published var showsAdvancedHostFields = false
    @Published private(set) var gatewayDetectionText: String?
    @Published var notificationRules: NotificationRuleSet {
        didSet {
            UserDefaults.standard.notificationRules = notificationRules
            scheduleNotificationRuleUpdate()
        }
    }
    @Published var enabledNetworkStatusAlerts: Set<NetworkConnectivityStatus> {
        didSet {
            UserDefaults.standard.enabledNetworkStatusAlerts = enabledNetworkStatusAlerts
        }
    }
    @Published var overlayVisible: Bool {
        didSet {
            UserDefaults.standard.overlayVisible = overlayVisible
        }
    }
    @Published var overlayAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.overlayAlwaysOnTop = overlayAlwaysOnTop
        }
    }
    @Published var overlayOpacity: Double {
        didSet {
            UserDefaults.standard.overlayOpacity = overlayOpacity
        }
    }
    @Published var overlayCompactMode: Bool {
        didSet {
            UserDefaults.standard.overlayCompactMode = overlayCompactMode
            onPresentationChanged?()
        }
    }
    @Published var displayMode: PingScopeDisplayMode {
        didSet {
            UserDefaults.standard.pingScopeDisplayMode = displayMode
            onPresentationChanged?()
        }
    }
    @Published var overlayShowsAllHosts: Bool {
        didSet {
            UserDefaults.standard.overlayShowsAllHosts = overlayShowsAllHosts
            recomputeDisplayPresentation()
        }
    }
    @Published var popoverShowsAllHosts: Bool {
        didSet {
            UserDefaults.standard.popoverShowsAllHosts = popoverShowsAllHosts
            recomputeDisplayPresentation()
        }
    }
    @Published var overlayShowsLegend: Bool {
        didSet {
            UserDefaults.standard.overlayShowsLegend = overlayShowsLegend
            onPresentationChanged?()
        }
    }
    @Published var allowsLocalNetworkProbes: Bool {
        didSet {
            UserDefaults.standard.allowsLocalNetworkProbes = allowsLocalNetworkProbes
            scheduleLocalNetworkProbeUpdate()
        }
    }
    @Published var startsAtLogin: Bool {
        didSet {
            guard !isApplyingStartAtLoginChange else { return }
            UserDefaults.standard.startsAtLogin = startsAtLogin
            configureStartAtLogin(startsAtLogin)
        }
    }
    @Published var widgetsEnabled: Bool {
        didSet {
            UserDefaults.standard.widgetSharingOptedIn = widgetsEnabled
            UserDefaults.standard.widgetsEnabled = widgetsEnabled
            if widgetsEnabled {
                publishWidgetSnapshot(snapshot)
            } else {
                // Remove what was already written to the shared app-group
                // container, so opting out stops exposing data to the widget
                // rather than only stopping future publishes.
                let store = widgetSnapshotStore ?? WidgetSnapshotStore()
                widgetSnapshotStore = nil
                lastPublishedWidgetSnapshot = nil
                lastWidgetTimelineReloadAt = nil
                Task {
                    await store.delete()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
    @Published private(set) var currentNetworkStatus: NetworkConnectivityStatus = .connected
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .unknown
    @Published private(set) var notificationRequestMessage: String?
    @Published var historyExportHostID: UUID?
    @Published var historyExportRange: HistoryExportRangePreset = .default
    @Published var historyExportCustomValue = "1"
    @Published var historyExportCustomUnit: HistoryExportRangeUnit = .hours
    @Published private(set) var historyExportMessage: String?
    @Published private(set) var isExportingHistory = false
    @Published var historySurfaceHostID: UUID?
    @Published var historySurfaceRange = UserDefaults.standard.pingScopeMacHistoryRange {
        didSet { UserDefaults.standard.pingScopeMacHistoryRange = historySurfaceRange }
    }
    @Published var historySurfacePresentation: MacHistorySurfacePresentation?
    @Published var isLoadingHistorySurface = false
    @Published private(set) var diagnosticsMessage: String?
    @Published var isCloudSyncEnabled: Bool {
        didSet {
            guard !isApplyingCloudSyncActivationState else { return }
            cloudSyncDefaults.set(isCloudSyncEnabled, forKey: PingScopeCloudSyncPreference.enabledKey)
            configureCloudSync(isAutomaticLaunch: false)
        }
    }
    @Published private(set) var cloudSyncStatusText = "Off"
    @Published var overlayFrame: NSRect

    let presenter = DisplayStatePresenter()
    private let networkDiagnoser = NetworkPerspectiveDiagnoser()
    let runtime: PingRuntime
    private let hostTester: HostTester
    let gatewayEndpointResolver: DefaultGatewayEndpointResolver
    let gatewayDetector = DefaultGatewayDetector()
    let starlinkDetector = StarlinkDishDetector()
    private let notificationDispatcher = MacNotificationDispatcher()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.pingscope.network-path")
    private let networkCaptureStore: NetworkCaptureSnapshotStore
    var widgetSnapshotStore: WidgetSnapshotStore?
    private var snapshotTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    var endpointRefreshTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    var historySurfaceTask: Task<Void, Never>?
    var historySurfaceLoadToken: UInt64 = 0
    private var overlayFramePersistTask: Task<Void, Never>?
    var widgetSnapshotPublishTask: Task<Void, Never>?
    var notificationRulesTask: Task<Void, Never>?
    var localNetworkProbeTask: Task<Void, Never>?
    private var draftTestTask: Task<Void, Never>?
    private var draftTestGeneration = 0
    private var isApplyingStartAtLoginChange = false
    private var isApplyingCloudSyncActivationState = false
    private var cloudSyncConfigurationGeneration: UInt64 = 0
    private let hostMutationCommits = HostMutationCommitQueue()
    private var lastHistoryKey: String?
    private let displayPresentationRecomputeScheduler = DisplayPresentationRecomputeScheduler()
    private var presentationVisibleHistorySamples: [PingResult] = []
    private var lastDisplayPresentationInputKey: DisplayPresentationInputKey?
    var lastPublishedWidgetSnapshot: WidgetSnapshot?
    var lastWidgetTimelineReloadAt: Date?
    let widgetPublishPolicy = WidgetSnapshotPublishPolicy()
    private let hostConfigPersistence: HostConfigPersistence
    private let cloudSyncService: PingScopeCloudSyncService?
    private let cloudSyncActivation: PingScopeCloudSyncActivationController?
    private let cloudSyncDefaults: UserDefaults
    private let acceptedHostReconciliationGate: @Sendable () async -> Void
    private let cloudHostUploadObserver: @Sendable ([HostConfig]) -> Void
    private var lastCloudSyncHostIDs: Set<UUID> = []
    private var lastCloudSyncHostsByID: [UUID: HostConfig] = [:]
    var historySurfaceStore: (any PingHistoryStore)?
    var historySurfaceLoader: any MacHistorySurfaceLoading
    private var lastObservedGateway: String?
    private var lastNetworkPathSignature: String?
    var onMenuStateChanged: ((MenuBarState) -> Void)?
    var onOverlayGraphClicked: (() -> Void)?
    var onPresentationChanged: (() -> Void)?

    override convenience init() {
        self.init(cloudSyncDefaultsSuiteName: nil)
    }

    init(
        cloudSyncDefaultsSuiteName: String?,
        runtimeOverride: PingRuntime? = nil,
        acceptedHostReconciliationGate: @escaping @Sendable () async -> Void = {},
        cloudHostUploadObserver: @escaping @Sendable ([HostConfig]) -> Void = { _ in }
    ) {
        let cloudSyncDefaults = cloudSyncDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let hostConfigPersistence = HostConfigPersistence(defaults: cloudSyncDefaults)
        let loadedHosts = hostConfigPersistence.loadInitialConfiguration { message in
            DebugLog.write(message)
        }
        self.liveDisplay = LiveDisplayModel(
            snapshot: RuntimeSnapshot(
                hosts: loadedHosts.hosts,
                primaryHostID: loadedHosts.primaryHostID ?? loadedHosts.hosts.first?.id,
                healthByHost: [:],
                samplesByHost: [:]
            )
        )
        let hostStore = HostStore(defaultHosts: loadedHosts.hosts, primaryHostID: loadedHosts.primaryHostID)
        let probeFactory = DefaultProbeFactory()
        let networkCaptureStore = NetworkCaptureSnapshotStore()
        self.networkCaptureStore = networkCaptureStore
        let historyStore: (any PingHistoryStore)?
        let cloudSyncService: PingScopeCloudSyncService?
        do {
            let sqliteHistoryStore = try SQLiteHistoryStore(
                url: SQLiteHistoryStore.defaultURL(),
                retention: Self.historyRetention,
                logger: { message in
                    DebugLog.write(message)
                }
            )
            let service = PingScopeCloudSyncService(
                historyStore: sqliteHistoryStore,
                hostStore: UserDefaultsSharedHostStore(legacyPlatform: .macOS)
            )
            historyStore = NetworkCapturedHistoryStore(
                destination: CloudSyncingHistoryStore(destination: sqliteHistoryStore, service: service),
                networkCaptureStore: networkCaptureStore
            )
            cloudSyncService = service
        } catch {
            DebugLog.write("history store unavailable: \(error)")
            historyStore = nil
            cloudSyncService = nil
        }
        let allowsLocalNetworkProbes = UserDefaults.standard.allowsLocalNetworkProbes
        UserDefaults.standard.migrateNoisyNetworkStatusAlertDefaults()
        let notificationRules = UserDefaults.standard.notificationRules ?? NotificationRuleSet()
        self.runtime = runtimeOverride ?? PingRuntime(
            hostStore: hostStore,
            scheduler: MeasurementScheduler(probeFactory: probeFactory, logger: { message in
                DebugLog.write(message)
            }),
            historyStore: historyStore,
            allowsLocalNetworkProbes: allowsLocalNetworkProbes,
            notificationRules: notificationRules,
            logger: { message in
                DebugLog.write(message)
            }
        )
        self.historySurfaceStore = historyStore
        self.historySurfaceLoader = MacHistorySurfaceLoader()
        self.cloudSyncService = cloudSyncService
        self.cloudSyncActivation = cloudSyncService.map {
            PingScopeCloudSyncActivationController(
                service: $0,
                defaultsSuiteName: cloudSyncDefaultsSuiteName
            )
        }
        self.cloudSyncDefaults = cloudSyncDefaults
        self.acceptedHostReconciliationGate = acceptedHostReconciliationGate
        self.cloudHostUploadObserver = cloudHostUploadObserver
        self.hostConfigPersistence = hostConfigPersistence
        self.hostTester = HostTester(probeFactory: probeFactory)
        self.gatewayEndpointResolver = DefaultGatewayEndpointResolver(probeFactory: probeFactory)
        self.notificationRules = notificationRules
        self.enabledNetworkStatusAlerts = UserDefaults.standard.enabledNetworkStatusAlerts
        self.overlayVisible = UserDefaults.standard.overlayVisible
        self.overlayAlwaysOnTop = UserDefaults.standard.overlayAlwaysOnTop
        self.overlayOpacity = UserDefaults.standard.overlayOpacity
        self.overlayCompactMode = UserDefaults.standard.overlayCompactMode
        self.displayMode = UserDefaults.standard.pingScopeDisplayMode
        self.overlayShowsAllHosts = UserDefaults.standard.overlayShowsAllHosts
        self.popoverShowsAllHosts = UserDefaults.standard.popoverShowsAllHosts
        self.overlayShowsLegend = UserDefaults.standard.overlayShowsLegend
        self.allowsLocalNetworkProbes = allowsLocalNetworkProbes
        self.startsAtLogin = UserDefaults.standard.startsAtLogin ?? (SMAppService.mainApp.status == .enabled)
        let widgetsEnabled = UserDefaults.standard.widgetSharingOptedIn == true && UserDefaults.standard.widgetsEnabled
        if !widgetsEnabled, UserDefaults.standard.widgetsEnabled {
            UserDefaults.standard.widgetsEnabled = false
        }
        self.widgetsEnabled = widgetsEnabled
        self.isCloudSyncEnabled = PingScopeCloudSyncPreference.isEnabled(in: cloudSyncDefaults)
        self.lastCloudSyncHostIDs = Set(loadedHosts.hosts.map(\.id))
        self.lastCloudSyncHostsByID = Dictionary(uniqueKeysWithValues: loadedHosts.hosts.map { ($0.id, $0) })
        self.overlayFrame = UserDefaults.standard.overlayFrame ?? NSRect(x: 80, y: 620, width: 240, height: 96)
        super.init()
        configureCloudSync(isAutomaticLaunch: true)
    }

    convenience init(runtimeForTesting runtime: PingRuntime) {
        self.init(cloudSyncDefaultsSuiteName: nil, runtimeOverride: runtime)
    }

    convenience init(
        historySurfaceStore: any PingHistoryStore,
        historySurfaceLoader: any MacHistorySurfaceLoading,
        configuredHosts: [HostConfig],
        primaryHostID: UUID?
    ) {
        self.init()
        self.historySurfaceStore = historySurfaceStore
        self.historySurfaceLoader = historySurfaceLoader
        self.configuredHosts = configuredHosts
        self.configuredPrimaryHostID = primaryHostID
    }

    func replaceConfiguredHostsForTesting(_ hosts: [HostConfig], primaryHostID: UUID?) {
        configuredHosts = hosts
        configuredPrimaryHostID = primaryHostID
    }

    var primaryHost: HostConfig? {
        snapshot.primaryHost
    }

    var primaryHealth: HostHealth {
        if let health = snapshot.primaryHealth {
            return health
        }
        return HostHealth(hostID: primaryHost?.id ?? UUID())
    }

    var menuBarState: MenuBarState {
        presenter.menuBarState(for: primaryHost, health: snapshot.primaryHealth)
    }

    var selectedRangeState: MenuBarState {
        if let visibleSampleState {
            return visibleSampleState
        }
        return presenter.rangeStatusState(for: primaryHost, health: snapshot.primaryHealth, range: selectedRange)
    }

    var selectedRangeStatusLabel: String {
        if let visibleSampleStatusLabel {
            return visibleSampleStatusLabel
        }
        return presenter.rangeStatusLabel(for: snapshot.primaryHealth, range: selectedRange)
    }

    private var visibleSampleState: MenuBarState? {
        guard let primaryHost,
              !hasCurrentLiveRangeResult,
              let latest = displayPresentation.visibleSamples.last else {
            return nil
        }
        var visibleHealth = HostHealth(hostID: primaryHost.id, thresholds: primaryHost.thresholds)
        visibleHealth.ingest(latest)
        return presenter.menuBarState(for: primaryHost, health: visibleHealth)
    }

    private var visibleSampleStatusLabel: String? {
        guard !hasCurrentLiveRangeResult,
              let latest = displayPresentation.visibleSamples.last else {
            return nil
        }
        return latest.isSuccess ? "Healthy" : "Failed"
    }

    private var hasCurrentLiveRangeResult: Bool {
        guard let latestResult = snapshot.primaryHealth?.latestResult else { return false }
        return latestResult.timestamp >= Date().addingTimeInterval(-selectedRange.duration)
    }

    var menuBarGlyphContent: MenuBarGlyphContent {
        presenter.menuBarGlyphContent(for: primaryHost, health: snapshot.primaryHealth)
    }

    var networkDiagnosis: NetworkPerspectiveDiagnosis {
        networkDiagnoser.diagnose(hosts: snapshot.hosts, healthByHost: snapshot.healthByHost, networkStatus: currentNetworkStatus)
    }

    var historyExportHost: HostConfig? {
        let selectedID = historyExportHostID ?? primaryHost?.id
        return snapshot.hosts.first { $0.id == selectedID } ?? primaryHost ?? snapshot.hosts.first
    }

    var diagnosticsLogURL: URL {
        DebugLog.fileURL
    }

    var appVersionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(shortVersion) (\(build))"
    }

    var bundleIdentifierText: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var widgetsStatusText: String {
        widgetsEnabled ? "Shared data enabled" : "Disabled"
    }
    var recentDiagnosticFailures: [PingResult] {
        newestFailures(limit: 8, in: displayPresentation.visibleSamples)
    }

    private func newestFailures(limit: Int, in samples: [PingResult]) -> [PingResult] {
        guard limit > 0 else { return [] }
        var failures: [PingResult] = []
        failures.reserveCapacity(limit)
        for sample in samples.reversed() where sample.failureReason != nil {
            failures.append(sample)
            if failures.count == limit {
                break
            }
        }
        return failures
    }

    var methodsForCurrentBuild: [PingMethod] {
        BuildFlavor.current.availableMethods
    }

    var draftHost: HostConfig {
        HostConfig(
            id: draftHostID,
            displayName: draftHostName,
            address: draftHostAddress,
            tier: draftNetworkTier,
            method: draftMethod,
            port: draftMethod == .icmp ? nil : UInt16(clamping: draftPort),
            interval: .milliseconds(draftIntervalMilliseconds),
            timeout: .milliseconds(draftTimeoutMilliseconds),
            thresholds: LatencyThresholds(
                degradedMilliseconds: draftDegradedThresholdMilliseconds,
                downAfterFailures: draftDownAfterFailures
            ),
            isEnabled: draftIsEnabled,
            notifications: draftNotificationPolicy,
            displayColor: draftDisplayColor
        )
    }

    func start() {
        startRuntimeSubscriptions()
        Task { [runtime] in await runtime.start() }
        startNetworkMonitoring()
        startNetworkPathMonitoring()
        refreshNotificationPermission()
    }

    func startRuntimeSubscriptions() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            guard let snapshots = await self?.runtime.snapshots() else { return }
            for await snapshot in snapshots {
                guard let self else { return }
                self.processRuntimeSnapshot(snapshot)
            }
        }
        // Alerts arrive on their own non-conflating stream: the snapshot stream
        // above deliberately drops intermediate states when the main actor is
        // busy, which would silently and permanently lose one-shot alerts.
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            guard let events = await self?.runtime.alerts() else { return }
            for await event in events {
                guard let self else { return }
                self.deliverAlerts(event.decisions, hosts: event.hosts)
            }
        }
    }

    private func processRuntimeSnapshot(_ snapshot: RuntimeSnapshot) {
        #if DEBUG
        let signpostID = OSSignpostID(log: snapshotPointsOfInterestLog)
        os_signpost(
            .begin,
            log: snapshotPointsOfInterestLog,
            name: "PingScopeModel.processSnapshot",
            signpostID: signpostID
        )
        defer {
            os_signpost(
                .end,
                log: snapshotPointsOfInterestLog,
                name: "PingScopeModel.processSnapshot",
                signpostID: signpostID
            )
        }
        #endif
        liveDisplay.updateSnapshot(snapshot)
        updateConfiguredHostsIfNeeded(snapshot)
        scheduleDisplayPresentationRecompute()
        persistHostState(snapshot)
        onMenuStateChanged?(menuBarState)
        ensureLocalNetworkProbesForSelectedLocalHost(snapshot)
        refreshVisibleHistoryIfNeeded()
        if widgetsEnabled == true {
            publishWidgetSnapshot(snapshot)
        }
    }

    func stop() {
        cancelModelTasks()
        Task { await runtime.stop() }
    }

    /// Termination-path stop: awaits the runtime shutdown (including the history
    /// write-buffer flush) instead of firing it into a task the process exit
    /// would abandon, so buffered samples reach SQLite before quit.
    func stopAndFlush() async {
        cancelModelTasks()
        await runtime.stop()
    }

    private func cancelModelTasks() {
        snapshotTask?.cancel()
        alertTask?.cancel()
        networkTask?.cancel()
        endpointRefreshTask?.cancel()
        historyTask?.cancel()
        historySurfaceLoadToken += 1
        historySurfaceTask?.cancel()
        historySurfaceTask = nil
        isLoadingHistorySurface = false
        displayPresentationRecomputeScheduler.cancel()
        overlayFramePersistTask?.cancel()
        notificationRulesTask?.cancel()
        localNetworkProbeTask?.cancel()
        draftTestTask?.cancel()
        pathMonitor.cancel()
    }

    func applyCadenceInputs(_ inputs: CadenceInputs) async {
        await runtime.setCadenceInputs(inputs)
    }

    func pauseMeasurementsForSleep() {
        Task { await runtime.stopMeasurements() }
    }

    func resumeMeasurementsAfterSystemChange() {
        startNetworkMonitoring()
        Task { await runtime.restartScheduler() }
        refreshNetworkEndpoints(removeMissingStarlink: true, retryDelays: [.seconds(1), .seconds(3)])
    }

    func selectHost(_ id: UUID) {
        performUserHostMutation { runtime in
            await runtime.selectPrimaryHost(id)
        }
        lastHistoryKey = nil
    }

    func selectHostForEditing(_ id: UUID) {
        guard let host = snapshot.hosts.first(where: { $0.id == id }) else { return }
        loadDraft(from: host)
    }

    func setPingInterval(_ interval: Duration, for hostID: UUID) {
        guard interval >= .milliseconds(250),
              var host = snapshot.hosts.first(where: { $0.id == hostID }) else {
            return
        }
        host.interval = interval
        let updatedHost = host
        performUserHostMutation { runtime in
            await runtime.upsertHost(updatedHost)
        }
    }

    func beginAddingHost() {
        clearDraftHost()
        isCreatingHost = true
    }

    func addDraftHost() {
        var host = draftHost
        guard host.validationErrors.isEmpty else { return }
        host.displayName = host.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        host.address = host.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedHost = host
        applyHostOptimistically(savedHost)
        clearDraftHost()
        performUserHostMutation { runtime in
            await runtime.upsertHost(savedHost)
        }
    }

    func clearDraftHost() {
        editingHostID = nil
        isCreatingHost = false
        showsAdvancedHostFields = false
        draftHostID = UUID()
        draftHostName = ""
        draftHostAddress = ""
        draftNetworkTier = nil
        draftMethod = .https
        draftPort = Int(PingMethod.https.defaultPort ?? 0)
        draftIntervalMilliseconds = 2_000
        draftTimeoutMilliseconds = 2_000
        draftDegradedThresholdMilliseconds = LatencyThresholds.defaults.degradedMilliseconds
        draftDownAfterFailures = LatencyThresholds.defaults.downAfterFailures
        draftIsEnabled = true
        draftNotificationPolicy = .inherit
        draftDisplayColor = nil
        draftTestResultText = nil
    }

    func applyDraftMethod(_ method: PingMethod) {
        draftMethod = method
        draftPort = Int(method.defaultPort ?? 0)
        draftTestResultText = nil
    }

    func useStarlinkDishPreset() {
        loadDraft(from: .defaultStarlinkDish)
        draftHostID = UUID()
        editingHostID = nil
        isCreatingHost = true
        draftTestResultText = nil
    }

    func testDraftHost() {
        let host = draftHost
        guard host.validationErrors.isEmpty else {
            draftTestResultText = "Fix host settings before testing"
            return
        }

        draftTestTask?.cancel()
        draftTestGeneration += 1
        let generation = draftTestGeneration
        isTestingDraftHost = true
        draftTestResultText = nil
        draftTestTask = Task { [hostTester] in
            let result = await hostTester.test(host)
            await MainActor.run {
                guard generation == self.draftTestGeneration, !Task.isCancelled else { return }
                self.isTestingDraftHost = false
                if let latency = result.latency {
                    self.draftTestResultText = "\(Int(latency.milliseconds.rounded()))ms"
                } else {
                    self.draftTestResultText = "Failed: \(result.failureReason?.userMessage ?? "No response")"
                }
            }
        }
    }

    func deleteHost(_ id: UUID) {
        performUserHostMutation { runtime in
            await runtime.deleteHost(id)
        }
    }

    func resetToDefaults() {
        notificationRules = NotificationRuleSet()
        enabledNetworkStatusAlerts = NetworkConnectivityStatus.defaultAlertStatuses
        performUserHostMutation { runtime in
            await runtime.reset()
        }
    }

    func setPrimaryHost(_ id: UUID) {
        selectHost(id)
    }

    func setAlertType(_ type: AlertType, enabled: Bool) {
        if enabled {
            notificationRules.alertTypes.insert(type)
        } else {
            notificationRules.alertTypes.remove(type)
        }
    }

    func setNotificationsEnabled(_ isEnabled: Bool) {
        notificationRules.isEnabled = isEnabled
        guard isEnabled, notificationPermissionState == .notDetermined else { return }
        requestNotificationPermission()
    }

    func refreshNotificationPermission() {
        Task { @MainActor [weak self, notificationDispatcher] in
            let state = await notificationDispatcher.permissionState()
            self?.notificationPermissionState = state
        }
    }

    func requestNotificationPermission() {
        notificationPermissionState = .requesting
        notificationRequestMessage = nil
        Task { @MainActor [weak self, notificationDispatcher] in
            let granted = await notificationDispatcher.requestAuthorization()
            let state = await notificationDispatcher.permissionState()
            self?.notificationPermissionState = state
            self?.notificationRequestMessage = granted ? "Permission allowed" : "Permission was not granted"
        }
    }

    func sendTestNotification() {
        notificationRequestMessage = "Scheduling test..."
        Task { @MainActor [weak self, notificationDispatcher] in
            let sent = await notificationDispatcher.sendTestNotification()
            let state = await notificationDispatcher.permissionState()
            self?.notificationPermissionState = state
            self?.notificationRequestMessage = sent ? "Test notification scheduled" : "Could not schedule test notification"
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.hadm.pingscope") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearDiagnosticsLog() {
        DebugLog.clear()
        diagnosticsMessage = "Cleared debug log"
    }

    func setDiagnosticsMessage(_ message: String?) {
        diagnosticsMessage = message
    }

    func exportHistory(format: HistoryExportFormat) {
        guard let host = historyExportHost else {
            historyExportMessage = "No host selected"
            return
        }
        guard let duration = historyExportRange.resolvedDuration(
            customValue: historyExportCustomValue,
            customUnit: historyExportCustomUnit
        ) else {
            historyExportMessage = "Enter a valid export range"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export PingScope History"
        let rangeName = historyExportRange.filenameComponent(
            customValue: historyExportCustomValue,
            customUnit: historyExportCustomUnit
        )
        panel.nameFieldStringValue = "\(Self.safeFilename(host.displayName))-\(rangeName).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExportingHistory = true
        historyExportMessage = "Exporting..."
        Task {
            do {
                let sampleCount = try await runtime.exportHistory(
                    host: host,
                    since: Date().addingTimeInterval(-duration),
                    format: format,
                    to: url
                )
                await MainActor.run {
                    self.isExportingHistory = false
                    self.historyExportMessage = "Exported \(sampleCount) samples"
                }
            } catch {
                DebugLog.write("history export failed error=\(error.localizedDescription)")
                await MainActor.run {
                    self.isExportingHistory = false
                    self.historyExportMessage = Self.historyExportFailureMessage(for: error)
                }
            }
        }
    }

    private static func historyExportFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return "Export failed: permission denied"
            case NSFileWriteOutOfSpaceError:
                return "Export failed: disk is full"
            default:
                break
            }
        }
        let message = nsError.localizedDescription
        return message.isEmpty ? "Export failed" : "Export failed: \(message)"
    }

    func setNetworkStatusAlert(_ status: NetworkConnectivityStatus, enabled: Bool) {
        if enabled {
            enabledNetworkStatusAlerts.insert(status)
        } else {
            enabledNetworkStatusAlerts.remove(status)
        }
    }

    func addDefaultGatewayHost() {
        gatewayDetectionText = "Detecting..."
        Task { [gatewayDetector, gatewayEndpointResolver] in
            let host = await gatewayDetector.detect()
            let resolvedHost = if let host {
                await gatewayEndpointResolver.resolve(address: host.address)
            } else {
                Optional<HostConfig>.none
            }
            await MainActor.run {
                guard let host = resolvedHost else {
                    self.gatewayDetectionText = "No default gateway found"
                    return
                }
                var gatewayHost = host
                if let existingHost = self.snapshot.hosts.first(where: {
                    $0.address == host.address || $0.displayName == host.displayName
                }) {
                    gatewayHost.id = existingHost.id
                }
                self.allowsLocalNetworkProbes = true
                self.gatewayDetectionText = "\(gatewayHost.address) monitoring enabled"
                self.loadDraft(from: gatewayHost)
                let savedGatewayHost = gatewayHost
                self.performUserHostMutation { runtime in
                    await runtime.upsertHost(savedGatewayHost)
                    await runtime.selectPrimaryHost(savedGatewayHost.id)
                }
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        persistOverlayFrame(notification)
    }

    func windowDidResize(_ notification: Notification) {
        persistOverlayFrame(notification)
    }

    func resetOverlayFrame() {
        overlayFrame = NSRect(x: 80, y: 620, width: 240, height: 96)
        UserDefaults.standard.overlayFrame = overlayFrame
    }

    func openOverlayDetails() {
        onOverlayGraphClicked?()
    }

    private func refreshVisibleHistoryIfNeeded() {
        guard let hostID = primaryHost?.id else {
            recomputeDisplayPresentation(visibleHistorySamples: [])
            lastHistoryKey = nil
            return
        }

        let key = historyCacheKey(hostID: hostID, range: selectedRange)
        guard key != lastHistoryKey else { return }
        lastHistoryKey = key
        refreshVisibleHistory()
    }

    private func refreshVisibleHistory() {
        guard let hostID = primaryHost?.id else {
            recomputeDisplayPresentation(visibleHistorySamples: [])
            lastHistoryKey = nil
            return
        }

        let range = selectedRange
        let key = historyCacheKey(hostID: hostID, range: range)
        lastHistoryKey = key
        recomputeDisplayPresentation(visibleHistorySamples: [])
        historyTask?.cancel()
        historyTask = Task { [runtime] in
            let samples = await runtime.historySamples(
                hostID: hostID,
                since: Date().addingTimeInterval(-range.duration),
                limit: Self.visibleHistorySampleLimit(for: range)
            )
            await MainActor.run {
                guard self.lastHistoryKey == key else { return }
                self.recomputeDisplayPresentation(visibleHistorySamples: samples)
            }
        }
    }

    private func historyCacheKey(hostID: UUID, range: TimeRange, now: Date = Date()) -> String {
        let refreshBucket = Int(now.timeIntervalSince1970 / 30)
        return "\(hostID.uuidString)-\(range.rawValue)-\(refreshBucket)"
    }

    static func visibleHistorySampleLimit(for range: TimeRange) -> Int {
        max(300, min(4_000, Int(range.duration.rounded(.up)) + 300))
    }

    private func scheduleDisplayPresentationRecompute() {
        displayPresentationRecomputeScheduler.schedule { [weak self] in
            self?.recomputeDisplayPresentation()
        }
    }

    private func updateConfiguredHostsIfNeeded(_ snapshot: RuntimeSnapshot) {
        if configuredHosts != snapshot.hosts {
            configuredHosts = snapshot.hosts
        }
        if configuredPrimaryHostID != snapshot.primaryHostID {
            configuredPrimaryHostID = snapshot.primaryHostID
        }
    }

    private func recomputeDisplayPresentation(visibleHistorySamples: [PingResult]? = nil) {
        if let visibleHistorySamples {
            presentationVisibleHistorySamples = visibleHistorySamples
        }
        let now = Date()
        let includesAllHosts = overlayShowsAllHosts || popoverShowsAllHosts
        let preparation = PingScopeDisplayPreparation(
            snapshot: snapshot,
            selectedRange: selectedRange,
            visibleHistorySamples: presentationVisibleHistorySamples,
            includesAllHosts: includesAllHosts,
            presenter: presenter,
            now: now
        )
        let allHostVisibleSamples: [UUID: [PingResult]]? = if includesAllHosts {
            Dictionary(uniqueKeysWithValues: preparation.allHostGraphSeries.map { series in
                (series.host.id, series.samples)
            })
        } else {
            nil
        }
        let inputKey = DisplayPresentationInputKey(
            visibleSamples: preparation.visibleSamples,
            selectedRange: selectedRange,
            includesAllHosts: includesAllHosts,
            primaryHost: snapshot.primaryHost,
            hosts: snapshot.hosts,
            healthByHost: snapshot.healthByHost,
            allHostVisibleSamples: allHostVisibleSamples
        )
        guard inputKey != lastDisplayPresentationInputKey else { return }
        lastDisplayPresentationInputKey = inputKey

        liveDisplay.updateDisplayPresentation(
            PingScopeDisplayPresentation(
                snapshot: snapshot,
                preparation: preparation,
                includesAllHosts: includesAllHosts,
                presenter: presenter
            )
        )
        onPresentationChanged?()
    }

    private func applyHostOptimistically(_ host: HostConfig) {
        var hosts = snapshot.hosts
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        liveDisplay.updateSnapshot(
            RuntimeSnapshot(
                hosts: hosts,
                primaryHostID: snapshot.primaryHostID ?? host.id,
                healthByHost: snapshot.healthByHost,
                samplesByHost: snapshot.samplesByHost
            )
        )
        updateConfiguredHostsIfNeeded(snapshot)
        recomputeDisplayPresentation()
        onMenuStateChanged?(menuBarState)
    }

    private func persistOverlayFrame(_ notification: Notification) {
        // The model may become the delegate of other windows; only the overlay
        // window's frame may be persisted as the overlay frame, or an unrelated
        // window's move teleports the overlay (potentially off-screen).
        guard let window = notification.object as? NSWindow, window is OverlayWindow else { return }
        overlayFrame = window.frame
        let frame = window.frame
        overlayFramePersistTask?.cancel()
        overlayFramePersistTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                UserDefaults.standard.overlayFrame = frame
            }
        }
    }

    private func persistHostState(_ snapshot: RuntimeSnapshot) {
        guard let persistedState = hostConfigPersistence.persist(snapshot, logger: DebugLog.write) else { return }
        guard let cloudSyncService else { return }
        let persistedHosts = persistedState.hosts
        let hostsByID = Dictionary(uniqueKeysWithValues: persistedHosts.map { ($0.id, $0) })
        guard hostsByID != lastCloudSyncHostsByID else { return }
        let currentIDs = Set(persistedHosts.map(\.id))
        let deletedIDs = lastCloudSyncHostIDs.subtracting(currentIDs)
        lastCloudSyncHostIDs = currentIDs
        lastCloudSyncHostsByID = hostsByID
        cloudHostUploadObserver(persistedHosts)
        Task {
            await cloudSyncService.uploadHosts(persistedHosts)
            for id in deletedIDs { await cloudSyncService.deleteHost(id: id) }
        }
    }

    private func configureCloudSync(isAutomaticLaunch: Bool) {
        guard let cloudSyncActivation else {
            cloudSyncStatusText = "Unavailable"
            return
        }
        let enabled = isCloudSyncEnabled
        let hosts = configuredHosts
        cloudSyncConfigurationGeneration &+= 1
        let generation = cloudSyncConfigurationGeneration
        cloudSyncStatusText = enabled ? "Checking iCloud account…" : "Off"
        Task { @MainActor [weak self] in
            if let cloudSyncService = self?.cloudSyncService {
                await cloudSyncService.setAcceptedHostStateHandler { [weak self] state in
                    await self?.reconcileAcceptedCloudHostState(state)
                }
            }
            let state = if isAutomaticLaunch {
                await cloudSyncActivation.activatePersisted(hosts: hosts)
            } else {
                await cloudSyncActivation.setEnabledByUser(enabled, hosts: hosts)
            }
            guard let self, generation == cloudSyncConfigurationGeneration else { return }
            isApplyingCloudSyncActivationState = true
            isCloudSyncEnabled = state.isEnabled
            isApplyingCloudSyncActivationState = false
            cloudSyncStatusText = state.statusText
        }
    }

    func reconcileAcceptedCloudHostState(_ state: SharedHostStoreState) async {
        await hostMutationCommits.perform { [weak self] in
            guard let self else { return }
            let resolvedState = hostConfigPersistence.resolveAcceptedHostState(state)
            await acceptedHostReconciliationGate()

            let acceptedHosts = HostConfig.sanitizedHosts(resolvedState.hosts)
            let acceptedSnapshot = await runtime.reconcileAcceptedHostState(
                SharedHostStoreState(
                    hosts: acceptedHosts,
                    primaryHostID: resolvedState.primaryHostID,
                    selectedHostID: resolvedState.selectedHostID
                )
            )

            hostConfigPersistence.commitAcceptedHostState(resolvedState)
            lastCloudSyncHostIDs = Set(acceptedHosts.map(\.id))
            lastCloudSyncHostsByID = Dictionary(uniqueKeysWithValues: acceptedHosts.map { ($0.id, $0) })
            processRuntimeSnapshot(acceptedSnapshot)
        }
    }

    func waitForHostMutationCommits() async {
        await hostMutationCommits.waitForIdle()
    }

    func performAutomaticHostMutation(
        _ mutation: @escaping @MainActor @Sendable (PingRuntime) async -> Void
    ) {
        performHostMutation(allowsUserManagedPersistence: false, mutation)
    }

    private func performUserHostMutation(
        _ mutation: @escaping @MainActor @Sendable (PingRuntime) async -> Void
    ) {
        performHostMutation(allowsUserManagedPersistence: true, mutation)
    }

    private func performHostMutation(
        allowsUserManagedPersistence: Bool,
        _ mutation: @escaping @MainActor @Sendable (PingRuntime) async -> Void
    ) {
        hostMutationCommits.enqueue { [weak self] in
            guard let self else { return }
            if allowsUserManagedPersistence {
                hostConfigPersistence.allowUserManagedPersistence()
            }
            await mutation(runtime)
            let committedSnapshot = await runtime.currentSnapshot()
            processRuntimeSnapshot(committedSnapshot)
        }
    }

    private static func cloudSyncStatusText(for status: PingScopeCloudSyncStatus) -> String {
        switch status {
        case .off: "Off"
        case .checkingAccount: "Checking iCloud account…"
        case .idle: "Up to date"
        case .syncing: "Syncing…"
        case .accountUnavailable: "Private iCloud account unavailable"
        case let .failed(message): "Sync error: \(message)"
        }
    }

    private func configureStartAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DebugLog.write("start at login configuration failed enabled=\(isEnabled) error=\(error.localizedDescription)")
            if startsAtLogin == isEnabled {
                isApplyingStartAtLoginChange = true
                startsAtLogin = !isEnabled
                isApplyingStartAtLoginChange = false
                UserDefaults.standard.startsAtLogin = startsAtLogin
            }
        }
    }

    private func deliverAlerts(_ alerts: [AlertDecision], hosts: [HostConfig]) {
        guard notificationRules.isEnabled, !alerts.isEmpty else { return }
        Task { [notificationDispatcher] in
            await notificationDispatcher.deliver(alerts, hosts: hosts)
        }
    }

    private func startNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = Task { [weak self] in
            guard let gatewayDetector = self?.gatewayDetector,
                  let gatewayEndpointResolver = self?.gatewayEndpointResolver,
                  let starlinkDetector = self?.starlinkDetector else { return }
            while !Task.isCancelled {
                let result = await Self.detectNetworkEndpointResult(
                    gatewayDetector: gatewayDetector,
                    gatewayEndpointResolver: gatewayEndpointResolver,
                    starlinkDetector: starlinkDetector,
                    removeMissingStarlink: true
                )
                guard !Task.isCancelled else { return }
                do {
                    guard let self else { return }
                    self.handleGatewayObservation(result.gatewayOutcome, resolvedHost: result.resolvedGateway)
                    self.reconcileStarlinkDetection(result.starlinkOutcome, removeMissing: result.removeMissingStarlink)
                }
                // NWPath changes and wake events trigger immediate refreshes. This
                // watchdog only covers missed system notifications.
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    private func startNetworkPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = Self.networkStatus(from: path)
            let signature = Self.networkPathSignature(from: path)
            let interface = Self.networkInterface(from: path)
            let capture = NetworkCaptureResolver(
                activeInterfaceNames: Self.activeNetworkInterfaceNames,
                wifiName: { nil },
                cellularRadio: { nil }
            ).snapshot(interface: interface)
            self?.networkCaptureStore.update(capture)
            DispatchQueue.main.async { [weak self] in
                if interface == "wifi", let name = Self.currentWiFiName() {
                    self?.networkCaptureStore.updateName(name, ifInterfaceMatches: "wifi")
                }
                self?.handleNetworkPathUpdate(status: status, signature: signature)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handleNetworkPathUpdate(status: NetworkConnectivityStatus, signature: String) {
        let changedPath = signature != lastNetworkPathSignature
        DebugLog.write("network path update status=\(status.rawValue) changedPath=\(changedPath) signature=\(DebugLog.redacted(signature))")
        lastNetworkPathSignature = signature
        handleNetworkStatus(status, forceRestart: changedPath)

        guard status == .connected, changedPath else { return }
        refreshNetworkEndpoints(removeMissingStarlink: true, retryDelays: [.seconds(1), .seconds(3)])
    }

    func handleGatewayObservation(_ outcome: DefaultGatewayDetector.DetectionOutcome, resolvedHost: HostConfig?) {
        switch outcome {
        case let .detected(host):
            handleGatewayObservation(host.address, resolvedHost: resolvedHost)
        case .notFound:
            handleGatewayObservation(nil, resolvedHost: nil)
        case .failed:
            DebugLog.write("gateway observation failed currentStatus=\(currentNetworkStatus.rawValue)")
        case .cancelled:
            DebugLog.write("gateway observation cancelled currentStatus=\(currentNetworkStatus.rawValue)")
        }
    }

    private func handleGatewayObservation(_ gateway: String?, resolvedHost: HostConfig?) {
        DebugLog.write("gateway observation gateway=\(DebugLog.redacted(gateway)) currentStatus=\(currentNetworkStatus.rawValue)")
        if gateway == nil, currentNetworkStatus == .connected {
            handleNetworkStatus(.noInternet)
        }
        if let resolvedHost {
            syncDefaultGatewayHost(resolvedHost)
        }
        defer { lastObservedGateway = gateway }
        guard let previousGateway = lastObservedGateway, let gateway, previousGateway != gateway else { return }
        Task {
            if let alert = await runtime.evaluateNetworkChange(previousGateway: previousGateway, currentGateway: gateway) {
                await notificationDispatcher.deliver(alert, hosts: snapshot.hosts)
            }
        }
    }

    private func handleNetworkStatus(_ status: NetworkConnectivityStatus, forceRestart: Bool = false) {
        let changedStatus = status != currentNetworkStatus
        guard changedStatus || forceRestart else { return }
        DebugLog.write("network status handled status=\(status.rawValue) changedStatus=\(changedStatus) forceRestart=\(forceRestart)")
        if changedStatus {
            currentNetworkStatus = status
            onPresentationChanged?()
            if widgetsEnabled {
                publishWidgetSnapshot(snapshot)
            }
        }
        if status == .connected {
            startNetworkMonitoring()
        }
        Task { await runtime.restartScheduler() }
        guard changedStatus else { return }
        guard status != .noInternet else { return }
        guard notificationRules.isEnabled, enabledNetworkStatusAlerts.contains(status) else { return }
        Task {
            await notificationDispatcher.deliver(.networkStatus(status), hosts: snapshot.hosts)
        }
    }

}

@MainActor
private final class HostMutationCommitQueue {
    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let next = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = next
        return next
    }

    func perform(_ operation: @escaping @MainActor () async -> Void) async {
        await enqueue(operation).value
    }

    func waitForIdle() async {
        await tail?.value
    }
}

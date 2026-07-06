import AppKit
import Combine
import Foundation
@preconcurrency import Network
import PingScopeCore
import ServiceManagement
import WidgetKit

@MainActor
final class PingScopeModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var snapshot = RuntimeSnapshot(
        hosts: HostConfig.defaultHosts(),
        primaryHostID: HostConfig.defaultInternet.id,
        healthByHost: [:],
        samplesByHost: [:]
    )
    @Published var selectedRange: TimeRange = .fiveMinutes {
        didSet {
            recomputeDisplayPresentation()
            refreshVisibleHistory()
        }
    }
    @Published var draftHostName = ""
    @Published var draftHostAddress = ""
    @Published var draftNetworkTier: NetworkTier?
    @Published var draftMethod: PingMethod = .https
    @Published var draftPort: Int = Int(PingMethod.https.defaultPort ?? 0)
    @Published var draftIntervalMilliseconds: Double = 2_000
    @Published var draftTimeoutMilliseconds: Double = 2_000
    @Published var draftDegradedThresholdMilliseconds: Double = LatencyThresholds.defaults.degradedMilliseconds
    @Published var draftDownAfterFailures: Int = LatencyThresholds.defaults.downAfterFailures
    @Published var draftIsEnabled = true
    @Published var draftNotificationPolicy: HostNotificationPolicy = .inherit
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
    @Published private(set) var displayPresentation = PingScopeDisplayPresentation()
    @Published var historyExportHostID: UUID?
    @Published var historyExportRange: HistoryExportRangePreset = .default
    @Published var historyExportCustomValue = "1"
    @Published var historyExportCustomUnit: HistoryExportRangeUnit = .hours
    @Published private(set) var historyExportMessage: String?
    @Published private(set) var isExportingHistory = false
    @Published private(set) var diagnosticsMessage: String?
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
    var widgetSnapshotStore: WidgetSnapshotStore?
    private var snapshotTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    var endpointRefreshTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var overlayFramePersistTask: Task<Void, Never>?
    var widgetSnapshotPublishTask: Task<Void, Never>?
    var notificationRulesTask: Task<Void, Never>?
    var localNetworkProbeTask: Task<Void, Never>?
    private var draftTestTask: Task<Void, Never>?
    private var draftTestGeneration = 0
    private var isApplyingStartAtLoginChange = false
    private var lastHistoryKey: String?
    var lastPublishedWidgetSnapshot: WidgetSnapshot?
    var lastWidgetTimelineReloadAt: Date?
    let widgetPublishPolicy = WidgetSnapshotPublishPolicy()
    private let hostConfigPersistence: HostConfigPersistence
    private var lastObservedGateway: String?
    private var lastNetworkPathSignature: String?
    var onMenuStateChanged: ((MenuBarState) -> Void)?
    var onOverlayGraphClicked: (() -> Void)?
    var onPresentationChanged: (() -> Void)?

    override init() {
        let hostConfigPersistence = HostConfigPersistence()
        let loadedHosts = hostConfigPersistence.loadInitialConfiguration { message in
            DebugLog.write(message)
        }
        let hostStore = HostStore(defaultHosts: loadedHosts.hosts, primaryHostID: loadedHosts.primaryHostID)
        let probeFactory = DefaultProbeFactory()
        let historyStore: SQLiteHistoryStore?
        do {
            historyStore = try SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL(), logger: { message in
                DebugLog.write(message)
            })
        } catch {
            DebugLog.write("history store unavailable: \(error)")
            historyStore = nil
        }
        let allowsLocalNetworkProbes = UserDefaults.standard.allowsLocalNetworkProbes
        UserDefaults.standard.migrateNoisyNetworkStatusAlertDefaults()
        let notificationRules = UserDefaults.standard.notificationRules ?? NotificationRuleSet()
        self.runtime = PingRuntime(
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
        self.hostConfigPersistence = hostConfigPersistence
        self.hostTester = HostTester(probeFactory: probeFactory)
        self.gatewayEndpointResolver = DefaultGatewayEndpointResolver(probeFactory: probeFactory)
        self.notificationRules = notificationRules
        self.enabledNetworkStatusAlerts = UserDefaults.standard.enabledNetworkStatusAlerts
        self.overlayVisible = UserDefaults.standard.overlayVisible
        self.overlayAlwaysOnTop = UserDefaults.standard.overlayAlwaysOnTop
        self.overlayOpacity = UserDefaults.standard.overlayOpacity
        self.overlayCompactMode = UserDefaults.standard.overlayCompactMode
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
        self.overlayFrame = UserDefaults.standard.overlayFrame ?? NSRect(x: 80, y: 620, width: 240, height: 96)
        super.init()
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
            id: editingHostID ?? UUID(),
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
            notifications: draftNotificationPolicy
        )
    }

    func start() {
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            guard let self else { return }
            let snapshots = await self.runtime.snapshots()
            for await snapshot in snapshots {
                await MainActor.run {
                    self.snapshot = snapshot
                    self.recomputeDisplayPresentation()
                    self.persistHostState(snapshot)
                    self.onMenuStateChanged?(self.menuBarState)
                    self.ensureLocalNetworkProbesForSelectedLocalHost(snapshot)
                    self.refreshVisibleHistoryIfNeeded()
                    if self.widgetsEnabled == true {
                        self.publishWidgetSnapshot(snapshot)
                    }
                }
            }
        }
        // Alerts arrive on their own non-conflating stream: the snapshot stream
        // above deliberately drops intermediate states when the main actor is
        // busy, which would silently and permanently lose one-shot alerts.
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            guard let self else { return }
            let events = await self.runtime.alerts()
            for await event in events {
                await MainActor.run {
                    self.deliverAlerts(event.decisions, hosts: event.hosts)
                }
            }
        }
        Task { await runtime.start() }
        startNetworkMonitoring()
        startNetworkPathMonitoring()
        refreshNotificationPermission()
    }

    func stop() {
        snapshotTask?.cancel()
        alertTask?.cancel()
        networkTask?.cancel()
        endpointRefreshTask?.cancel()
        historyTask?.cancel()
        overlayFramePersistTask?.cancel()
        notificationRulesTask?.cancel()
        localNetworkProbeTask?.cancel()
        draftTestTask?.cancel()
        pathMonitor.cancel()
        Task { await runtime.stop() }
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
        draftTestResultText = nil
    }

    func applyDraftMethod(_ method: PingMethod) {
        draftMethod = method
        draftPort = Int(method.defaultPort ?? 0)
        draftTestResultText = nil
    }

    func useStarlinkDishPreset() {
        loadDraft(from: .defaultStarlinkDish)
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
        Task { [notificationDispatcher] in
            let state = await notificationDispatcher.permissionState()
            await MainActor.run {
                self.notificationPermissionState = state
            }
        }
    }

    func requestNotificationPermission() {
        notificationPermissionState = .requesting
        notificationRequestMessage = nil
        Task { [notificationDispatcher] in
            let granted = await notificationDispatcher.requestAuthorization()
            let state = await notificationDispatcher.permissionState()
            await MainActor.run {
                self.notificationPermissionState = state
                self.notificationRequestMessage = granted ? "Permission allowed" : "Permission was not granted"
            }
        }
    }

    func sendTestNotification() {
        notificationRequestMessage = "Scheduling test..."
        Task { [notificationDispatcher] in
            let sent = await notificationDispatcher.sendTestNotification()
            let state = await notificationDispatcher.permissionState()
            await MainActor.run {
                self.notificationPermissionState = state
                self.notificationRequestMessage = sent ? "Test notification scheduled" : "Could not schedule test notification"
            }
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

    private func recomputeDisplayPresentation(visibleHistorySamples: [PingResult]? = nil) {
        displayPresentation = PingScopeDisplayPresentation(
            snapshot: snapshot,
            selectedRange: selectedRange,
            visibleHistorySamples: visibleHistorySamples ?? displayPresentation.visibleHistorySamples,
            includesAllHosts: overlayShowsAllHosts || popoverShowsAllHosts,
            presenter: presenter
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
        snapshot = RuntimeSnapshot(
            hosts: hosts,
            primaryHostID: snapshot.primaryHostID ?? host.id,
            healthByHost: snapshot.healthByHost,
            samplesByHost: snapshot.samplesByHost
        )
        recomputeDisplayPresentation()
        persistHostState(snapshot)
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
        hostConfigPersistence.persist(snapshot, logger: DebugLog.write)
    }

    private func performUserHostMutation(_ mutation: @escaping @Sendable (PingRuntime) async -> Void) {
        hostConfigPersistence.allowUserManagedPersistence()
        Task { [runtime] in
            await mutation(runtime)
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
            while !Task.isCancelled {
                await self?.performNetworkEndpointDetection(removeMissingStarlink: true)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func startNetworkPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = Self.networkStatus(from: path)
            let signature = Self.networkPathSignature(from: path)
            DispatchQueue.main.async { [weak self] in
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

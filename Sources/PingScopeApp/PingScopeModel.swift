import AppKit
import Combine
import Foundation
@preconcurrency import Network
import PingScopeCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class PingScopeModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var snapshot = RuntimeSnapshot(hosts: [.defaultInternet], primaryHostID: HostConfig.defaultInternet.id, healthByHost: [:], samplesByHost: [:])
    @Published var selectedRange: TimeRange = .fiveMinutes {
        didSet {
            recomputeVisibleSamples()
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
        }
    }
    @Published var overlayShowsAllHosts: Bool {
        didSet {
            UserDefaults.standard.overlayShowsAllHosts = overlayShowsAllHosts
            recomputeVisibleSamples()
        }
    }
    @Published var popoverShowsAllHosts: Bool {
        didSet {
            UserDefaults.standard.popoverShowsAllHosts = popoverShowsAllHosts
            recomputeVisibleSamples()
        }
    }
    @Published var overlayShowsLegend: Bool {
        didSet {
            UserDefaults.standard.overlayShowsLegend = overlayShowsLegend
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
                Task { await store.delete() }
            }
        }
    }
    @Published private(set) var currentNetworkStatus: NetworkConnectivityStatus = .connected
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .unknown
    @Published private(set) var notificationRequestMessage: String?
    @Published private(set) var visibleHistorySamples: [PingResult] = []
    @Published private(set) var visibleSamples: [PingResult] = []
    @Published private(set) var allHostGraphSeries: [HostLatencyGraphSeries] = []
    @Published private(set) var primaryStats = SampleStats(samples: [])
    @Published var historyExportHostID: UUID?
    @Published var historyExportRange: TimeRange = .oneHour
    @Published private(set) var historyExportMessage: String?
    @Published private(set) var isExportingHistory = false
    @Published private(set) var diagnosticsMessage: String?
    @Published var overlayFrame: NSRect

    private let presenter = DisplayStatePresenter()
    private let networkDiagnoser = NetworkPerspectiveDiagnoser()
    let runtime: PingRuntime
    private let hostTester: HostTester
    private let gatewayDetector = DefaultGatewayDetector()
    private let starlinkDetector = StarlinkDishDetector()
    private let notificationDispatcher = MacNotificationDispatcher()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.pingscope.network-path")
    private var widgetSnapshotStore: WidgetSnapshotStore?
    private var snapshotTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var endpointRefreshTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    var notificationRulesTask: Task<Void, Never>?
    var localNetworkProbeTask: Task<Void, Never>?
    private var draftTestTask: Task<Void, Never>?
    private var draftTestGeneration = 0
    private var isApplyingStartAtLoginChange = false
    private var lastHistoryKey: String?
    private var lastPersistedHostState: PersistedHostState?
    private var lastPublishedWidgetSnapshot: WidgetSnapshot?
    private let widgetSnapshotHeartbeatInterval: TimeInterval = 5 * 60
    private var lastObservedGateway: String?
    private var lastNetworkPathSignature: String?
    var onMenuStateChanged: ((MenuBarState) -> Void)?
    var onOverlayGraphClicked: (() -> Void)?

    override init() {
        let savedHosts = HostConfigMigrator().migrate(UserDefaults.standard.hostConfigs)
        let hosts = savedHosts.isEmpty ? [HostConfig.defaultInternet] : BuildFlavor.current.normalizedHosts(savedHosts)
        let hostStore = HostStore(defaultHosts: hosts, primaryHostID: UserDefaults.standard.primaryHostID)
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
            notificationRules: notificationRules
        )
        self.hostTester = HostTester(probeFactory: probeFactory)
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

    var primarySeries: SampleSeries? {
        snapshot.primarySeries
    }

    var menuBarState: MenuBarState {
        presenter.menuBarState(for: primaryHost, health: snapshot.primaryHealth)
    }

    var selectedRangeState: MenuBarState {
        presenter.rangeStatusState(for: primaryHost, health: snapshot.primaryHealth, range: selectedRange)
    }

    var selectedRangeStatusLabel: String {
        presenter.rangeStatusLabel(for: snapshot.primaryHealth, range: selectedRange)
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
        newestFailures(limit: 8, in: visibleSamples)
    }

    private func newestFailures(limit: Int, in samples: [PingResult]) -> [PingResult] {
        guard limit > 0 else { return [] }
        var failures: [PingResult] = []
        failures.reserveCapacity(limit)
        for sample in samples where sample.failureReason != nil {
            let insertionIndex = failures.firstIndex { sample.timestamp > $0.timestamp } ?? failures.count
            if insertionIndex < limit {
                failures.insert(sample, at: insertionIndex)
                if failures.count > limit {
                    failures.removeLast()
                }
            } else if failures.count < limit {
                failures.append(sample)
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
        let stream = Task { await runtime.snapshots() }
        snapshotTask = Task { [weak self] in
            let snapshots = await stream.value
            for await snapshot in snapshots {
                await MainActor.run {
                    self?.snapshot = snapshot
                    self?.recomputeVisibleSamples()
                    self?.persistHostState(snapshot)
                    if let state = self?.menuBarState {
                        self?.onMenuStateChanged?(state)
                    }
                    self?.evaluateInternetLoss(from: snapshot)
                    self?.ensureLocalNetworkProbesForSelectedLocalHost(snapshot)
                    self?.refreshVisibleHistoryIfNeeded()
                    if self?.widgetsEnabled == true {
                        self?.publishWidgetSnapshot(snapshot)
                    }
                }
            }
        }
        // Alerts arrive on their own non-conflating stream: the snapshot stream
        // above deliberately drops intermediate states when the main actor is
        // busy, which would silently and permanently lose one-shot alerts.
        alertTask?.cancel()
        let alertStream = Task { await runtime.alerts() }
        alertTask = Task { [weak self] in
            let events = await alertStream.value
            for await event in events {
                await MainActor.run {
                    self?.deliverAlerts(event.decisions, hosts: event.hosts)
                }
            }
        }
        Task { await runtime.start() }
        startNetworkMonitoring()
        startNetworkPathMonitoring()
        refreshNetworkEndpoints(removeMissingStarlink: true)
        refreshNotificationPermission()
    }

    func stop() {
        snapshotTask?.cancel()
        alertTask?.cancel()
        networkTask?.cancel()
        endpointRefreshTask?.cancel()
        historyTask?.cancel()
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
        Task { await runtime.selectPrimaryHost(id) }
        lastHistoryKey = nil
    }

    func selectHostForEditing(_ id: UUID) {
        guard let host = snapshot.hosts.first(where: { $0.id == id }) else { return }
        loadDraft(from: host)
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
        clearDraftHost()
        Task { await runtime.upsertHost(host) }
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
        Task { await runtime.deleteHost(id) }
    }

    func resetToDefaults() {
        notificationRules = NotificationRuleSet()
        enabledNetworkStatusAlerts = NetworkConnectivityStatus.defaultAlertStatuses
        Task { await runtime.reset() }
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

    func revealDiagnosticsLog() {
        if !FileManager.default.fileExists(atPath: diagnosticsLogURL.path) {
            DebugLog.write("diagnostics log created from settings")
            DebugLog.flush()
        }
        NSWorkspace.shared.activateFileViewerSelecting([diagnosticsLogURL])
        diagnosticsMessage = "Opened log in Finder"
    }

    func copyDiagnosticsSummary() {
        let summary = diagnosticsSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        diagnosticsMessage = "Copied diagnostics summary"
    }

    func clearDiagnosticsLog() {
        DebugLog.clear()
        diagnosticsMessage = "Cleared debug log"
    }

    func exportHistory(format: HistoryExportFormat) {
        guard let host = historyExportHost else {
            historyExportMessage = "No host selected"
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export PingScope History"
        panel.nameFieldStringValue = "\(Self.safeFilename(host.displayName))-\(historyExportRange.rawValue).\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExportingHistory = true
        historyExportMessage = "Exporting..."
        let range = historyExportRange
        Task {
            let samples = await runtime.historySamples(
                hostID: host.id,
                since: Date().addingTimeInterval(-range.duration),
                limit: 100_000
            )
            do {
                try await Task.detached(priority: .utility) {
                    try HistoryExporter.write(samples: samples, host: host, format: format, to: url)
                }.value
                await MainActor.run {
                    self.isExportingHistory = false
                    self.historyExportMessage = "Exported \(samples.count) samples"
                }
            } catch {
                await MainActor.run {
                    self.isExportingHistory = false
                    self.historyExportMessage = "Export failed"
                }
            }
        }
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
        Task { [gatewayDetector] in
            let host = await gatewayDetector.detect()
            await MainActor.run {
                guard let host else {
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
                Task {
                    await self.runtime.upsertHost(gatewayHost)
                    await self.runtime.selectPrimaryHost(gatewayHost.id)
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
            visibleHistorySamples = []
            recomputeVisibleSamples()
            lastHistoryKey = nil
            return
        }

        let key = "\(hostID.uuidString)-\(selectedRange.rawValue)"
        guard key != lastHistoryKey else { return }
        lastHistoryKey = key
        refreshVisibleHistory()
    }

    private func refreshVisibleHistory() {
        guard let hostID = primaryHost?.id else {
            visibleHistorySamples = []
            recomputeVisibleSamples()
            lastHistoryKey = nil
            return
        }

        let range = selectedRange
        let key = "\(hostID.uuidString)-\(range.rawValue)"
        lastHistoryKey = key
        visibleHistorySamples = []
        recomputeVisibleSamples()
        historyTask?.cancel()
        historyTask = Task { [runtime] in
            let samples = await runtime.historySamples(
                hostID: hostID,
                since: Date().addingTimeInterval(-range.duration),
                limit: 10_000
            )
            await MainActor.run {
                guard self.lastHistoryKey == key else { return }
                self.visibleHistorySamples = samples
                self.recomputeVisibleSamples()
            }
        }
    }

    private func recomputeVisibleSamples() {
        let samples = presenter.mergedSamples(
            history: visibleHistorySamples,
            live: presenter.visibleSamples(in: primarySeries, range: selectedRange),
            range: selectedRange
        )
        visibleSamples = samples
        primaryStats = SampleStats(samples: samples)
        allHostGraphSeries = overlayShowsAllHosts || popoverShowsAllHosts ? makeAllHostGraphSeries() : []
    }

    private func makeAllHostGraphSeries() -> [HostLatencyGraphSeries] {
        let cutoff = Date().addingTimeInterval(-selectedRange.duration)
        return snapshot.hosts.enumerated().compactMap { index, host in
            guard host.isEnabled else { return nil }
            let samples = snapshot.samplesByHost[host.id]?.samples(since: cutoff) ?? []
            return HostLatencyGraphSeries(
                host: host,
                samples: samples,
                color: HostLatencyGraphSeries.palette[index % HostLatencyGraphSeries.palette.count],
                isPrimary: host.id == primaryHost?.id
            )
        }
    }

    private func persistOverlayFrame(_ notification: Notification) {
        // The model may become the delegate of other windows; only the overlay
        // window's frame may be persisted as the overlay frame, or an unrelated
        // window's move teleports the overlay (potentially off-screen).
        guard let window = notification.object as? NSWindow, window is OverlayWindow else { return }
        overlayFrame = window.frame
        UserDefaults.standard.overlayFrame = window.frame
    }

    private func persistHostState(_ snapshot: RuntimeSnapshot) {
        let hostState = PersistedHostState(hosts: snapshot.hosts, primaryHostID: snapshot.primaryHostID)
        guard hostState != lastPersistedHostState else { return }
        lastPersistedHostState = hostState
        UserDefaults.standard.hostConfigs = snapshot.hosts
        UserDefaults.standard.primaryHostID = snapshot.primaryHostID
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
            for alert in alerts {
                await notificationDispatcher.deliver(alert, hosts: hosts)
            }
        }
    }

    private func evaluateInternetLoss(from snapshot: RuntimeSnapshot) {
        guard notificationRules.isEnabled,
              notificationRules.alertTypes.contains(.internetLoss),
              enabledNetworkStatusAlerts.contains(.noInternet),
              currentNetworkStatus != .noInternet else { return }
        let enabledHostIDs = Set(snapshot.hosts.filter(\.isEnabled).map(\.id))
        let latestResults = snapshot.healthByHost.values
            .filter { enabledHostIDs.contains($0.hostID) }
            .compactMap(\.latestResult)
        guard !latestResults.isEmpty, latestResults.count == enabledHostIDs.count else { return }

        Task {
            if let alert = await runtime.evaluateInternetLoss(results: latestResults) {
                await notificationDispatcher.deliver(alert, hosts: snapshot.hosts)
            }
        }
    }

    private func startNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = Task { [weak self, gatewayDetector, starlinkDetector] in
            while !Task.isCancelled {
                async let gatewayOutcome = gatewayDetector.detectionOutcome()
                async let starlinkOutcome = starlinkDetector.detectionOutcome(timeout: .seconds(5))

                let gateway = await gatewayOutcome
                await MainActor.run {
                    self?.handleGatewayObservation(gateway)
                }

                let outcome = await starlinkOutcome
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self?.reconcileStarlinkDetection(outcome, removeMissing: true)
                }
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

    private func handleGatewayObservation(_ outcome: DefaultGatewayDetector.DetectionOutcome) {
        switch outcome {
        case let .detected(host):
            handleGatewayObservation(host.address)
        case .notFound:
            handleGatewayObservation(nil)
        case .failed:
            DebugLog.write("gateway observation failed currentStatus=\(currentNetworkStatus.rawValue)")
        case .cancelled:
            DebugLog.write("gateway observation cancelled currentStatus=\(currentNetworkStatus.rawValue)")
        }
    }

    private func handleGatewayObservation(_ gateway: String?) {
        DebugLog.write("gateway observation gateway=\(DebugLog.redacted(gateway)) currentStatus=\(currentNetworkStatus.rawValue)")
        if gateway == nil, currentNetworkStatus == .connected {
            handleNetworkStatus(.noInternet)
        }
        if let gateway {
            syncDefaultGatewayHost(address: gateway)
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
            if widgetsEnabled {
                publishWidgetSnapshot(snapshot)
            }
        }
        if status == .connected {
            startNetworkMonitoring()
        }
        Task { await runtime.restartScheduler() }
        guard changedStatus else { return }
        guard notificationRules.isEnabled, enabledNetworkStatusAlerts.contains(status) else { return }
        Task {
            await notificationDispatcher.deliver(.networkStatus(status), hosts: snapshot.hosts)
        }
    }

    private func publishWidgetSnapshot(_ snapshot: RuntimeSnapshot) {
        guard widgetsEnabled else { return }
        if widgetSnapshotStore == nil {
            widgetSnapshotStore = WidgetSnapshotStore()
        }
        guard let widgetSnapshotStore else { return }
        let widgetSnapshot = WidgetSnapshot.make(from: snapshot, networkStatus: currentNetworkStatus)
        let shouldPublish = !widgetSnapshot.hasSameContent(as: lastPublishedWidgetSnapshot)
            || widgetSnapshot.generatedAt.timeIntervalSince(lastPublishedWidgetSnapshot?.generatedAt ?? .distantPast) >= widgetSnapshotHeartbeatInterval
        guard shouldPublish else { return }
        lastPublishedWidgetSnapshot = widgetSnapshot
        Task { [widgetSnapshotStore] in
            await widgetSnapshotStore.save(widgetSnapshot)
        }
    }

    private func refreshNetworkEndpoints(removeMissingStarlink: Bool, retryDelays: [Duration] = []) {
        endpointRefreshTask?.cancel()
        endpointRefreshTask = Task { [weak self, gatewayDetector, starlinkDetector] in
            await Self.detectNetworkEndpoints(
                gatewayDetector: gatewayDetector,
                starlinkDetector: starlinkDetector,
                removeMissingStarlink: removeMissingStarlink,
                owner: self
            )
            for delay in retryDelays {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await Self.detectNetworkEndpoints(
                    gatewayDetector: gatewayDetector,
                    starlinkDetector: starlinkDetector,
                    removeMissingStarlink: removeMissingStarlink,
                    owner: self
                )
            }
        }
    }

    private nonisolated static func detectNetworkEndpoints(
        gatewayDetector: DefaultGatewayDetector,
        starlinkDetector: StarlinkDishDetector,
        removeMissingStarlink: Bool,
        owner: PingScopeModel?
    ) async {
        DebugLog.write("network endpoint refresh started removeMissingStarlink=\(removeMissingStarlink)")
        async let gatewayOutcome = gatewayDetector.detectionOutcome()
        async let starlinkOutcome = starlinkDetector.detectionOutcome(timeout: .seconds(5))
        let gateway = await gatewayOutcome
        let outcome = await starlinkOutcome
        await MainActor.run {
            guard !Task.isCancelled else { return }
            owner?.handleGatewayObservation(gateway)
            owner?.reconcileStarlinkDetection(outcome, removeMissing: removeMissingStarlink)
        }
    }

    private func reconcileStarlinkDetection(_ outcome: StarlinkDishDetector.DetectionOutcome, removeMissing: Bool) {
        switch outcome {
        case let .detected(host):
            syncStarlinkHost(host)
        case .notFound:
            DebugLog.write("starlink discovery pass missed removeMissing=\(removeMissing)")
            if removeMissing {
                removeStaleStarlinkHosts()
            }
        case .failed:
            DebugLog.write("starlink discovery failed removeMissing=\(removeMissing)")
        case .cancelled:
            DebugLog.write("starlink discovery cancelled removeMissing=\(removeMissing)")
        }
    }

    private func syncStarlinkHost(_ host: HostConfig) {
        var starlinkHost = host
        let preferredPrimaryID = preferredPrimaryAfterStarlinkSync(starlinkHost)
        if let existing = snapshot.hosts.first(where: {
            $0.method == .starlink || $0.displayName == host.displayName || ($0.address == host.address && $0.port == host.port)
        }) {
            starlinkHost.id = existing.id
            starlinkHost.isEnabled = existing.isEnabled
            starlinkHost.notifications = existing.notifications
        }

        if !allowsLocalNetworkProbes {
            allowsLocalNetworkProbes = true
        }

        let isExisting = snapshot.hosts.contains { $0.id == starlinkHost.id }
        DebugLog.write("starlink dish detected address=\(DebugLog.redacted(starlinkHost.address)) existing=\(isExisting)")
        if editingHostID == starlinkHost.id {
            loadDraft(from: starlinkHost)
        }
        if let existing = snapshot.hosts.first(where: { $0.id == starlinkHost.id }), existing == starlinkHost {
            return
        }
        Task {
            await runtime.upsertHost(starlinkHost)
            if let preferredPrimaryID {
                await runtime.selectPrimaryHost(preferredPrimaryID)
            }
            DebugLog.write("starlink host upsert requested address=\(DebugLog.redacted(starlinkHost.address))")
        }
    }

    private func preferredPrimaryAfterStarlinkSync(_ starlinkHost: HostConfig) -> UUID? {
        let gatewayHost = snapshot.hosts.first { $0.displayName == "Default Gateway" }
        if gatewayHost?.address == starlinkHost.address {
            return nil
        }
        if let primary = snapshot.primaryHost, primary.method != .starlink {
            return primary.id
        }
        return gatewayHost?.id ?? snapshot.hosts.first(where: { $0.method != .starlink })?.id
    }

    private func removeStaleStarlinkHosts() {
        Task {
            let removedIDs = await runtime.removeStarlinkHosts()
            if let editingHostID, removedIDs.contains(editingHostID) {
                clearDraftHost()
            }
            DebugLog.write("stale starlink removal completed count=\(removedIDs.count)")
        }
    }

    private func syncDefaultGatewayHost(address gateway: String) {
        guard let existing = snapshot.hosts.first(where: { $0.displayName == "Default Gateway" }) else {
            return
        }
        if !allowsLocalNetworkProbes {
            allowsLocalNetworkProbes = true
        }
        guard existing.address != gateway else {
            return
        }

        var updated = existing
        updated.address = gateway
        updated.method = .tcp
        updated.port = 80
        allowsLocalNetworkProbes = true
        DebugLog.write("default gateway host updated from \(DebugLog.redacted(existing.address)) to \(DebugLog.redacted(gateway))")
        if editingHostID == existing.id {
            loadDraft(from: updated)
        }
        let isPrimary = primaryHost?.id == existing.id
        Task {
            await runtime.upsertHost(updated)
            if isPrimary {
                await runtime.selectPrimaryHost(existing.id)
            }
        }
    }

    private func ensureLocalNetworkProbesForSelectedLocalHost(_ snapshot: RuntimeSnapshot) {
        guard let primaryHost = snapshot.primaryHost,
              primaryHost.requiresLocalNetworkPermission,
              !allowsLocalNetworkProbes else {
            return
        }
        allowsLocalNetworkProbes = true
    }

}

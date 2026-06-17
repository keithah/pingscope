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
            refreshVisibleHistory()
        }
    }
    @Published var draftHostName = ""
    @Published var draftHostAddress = ""
    @Published var draftMethod: PingMethod = .tcp
    @Published var draftPort: Int = Int(PingMethod.tcp.defaultPort ?? 0)
    @Published var draftIntervalMilliseconds: Double = 2_000
    @Published var draftTimeoutMilliseconds: Double = 2_000
    @Published var draftDegradedThresholdMilliseconds: Double = LatencyThresholds.defaults.degradedMilliseconds
    @Published var draftDownAfterFailures: Int = LatencyThresholds.defaults.downAfterFailures
    @Published var draftIsEnabled = true
    @Published var draftNotificationPolicy: HostNotificationPolicy = .inherit
    @Published private(set) var draftTestResultText: String?
    @Published private(set) var isTestingDraftHost = false
    @Published var editingHostID: UUID?
    @Published private(set) var gatewayDetectionText: String?
    @Published var notificationRules: NotificationRuleSet {
        didSet {
            UserDefaults.standard.notificationRules = notificationRules
            Task { await runtime.updateNotificationRules(notificationRules) }
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
            overlayOpacity = min(max(overlayOpacity, 0.55), 1)
            UserDefaults.standard.overlayOpacity = overlayOpacity
        }
    }
    @Published var overlayCompactMode: Bool {
        didSet {
            UserDefaults.standard.overlayCompactMode = overlayCompactMode
        }
    }
    @Published var allowsLocalNetworkProbes: Bool {
        didSet {
            UserDefaults.standard.allowsLocalNetworkProbes = allowsLocalNetworkProbes
            Task { await runtime.setAllowsLocalNetworkProbes(allowsLocalNetworkProbes) }
        }
    }
    @Published var startsAtLogin: Bool {
        didSet {
            UserDefaults.standard.startsAtLogin = startsAtLogin
            configureStartAtLogin(startsAtLogin)
        }
    }
    @Published var widgetsEnabled: Bool {
        didSet {
            UserDefaults.standard.widgetsEnabled = widgetsEnabled
            if widgetsEnabled {
                publishWidgetSnapshot(snapshot)
            } else {
                widgetSnapshotStore = nil
            }
        }
    }
    @Published private(set) var currentNetworkStatus: NetworkConnectivityStatus = .connected
    @Published private(set) var notificationPermissionState: NotificationPermissionState = .unknown
    @Published private(set) var notificationRequestMessage: String?
    @Published private(set) var visibleHistorySamples: [PingResult] = []
    @Published var historyExportHostID: UUID?
    @Published var historyExportRange: TimeRange = .oneHour
    @Published private(set) var historyExportMessage: String?
    @Published private(set) var isExportingHistory = false
    @Published var overlayFrame: NSRect

    private let presenter = DisplayStatePresenter()
    private let runtime: PingRuntime
    private let hostTester: HostTester
    private let gatewayDetector = DefaultGatewayDetector()
    private let notificationDispatcher = MacNotificationDispatcher()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.pingscope.network-path")
    private var widgetSnapshotStore: WidgetSnapshotStore?
    private var snapshotTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var historyTask: Task<Void, Never>?
    private var lastHistoryKey: String?
    private var lastObservedGateway: String?
    var onMenuStateChanged: ((MenuBarState) -> Void)?
    var onOverlayGraphClicked: (() -> Void)?

    override init() {
        let savedHosts = UserDefaults.standard.hostConfigs
        let hosts = savedHosts.isEmpty ? [HostConfig.defaultInternet] : BuildFlavor.current.normalizedHosts(savedHosts)
        let hostStore = HostStore(defaultHosts: hosts, primaryHostID: UserDefaults.standard.primaryHostID)
        let probeFactory = DefaultProbeFactory()
        let historyStore = try? SQLiteHistoryStore(url: SQLiteHistoryStore.defaultURL())
        let allowsLocalNetworkProbes = UserDefaults.standard.allowsLocalNetworkProbes
        let notificationRules = UserDefaults.standard.notificationRules ?? NotificationRuleSet()
        self.runtime = PingRuntime(
            hostStore: hostStore,
            scheduler: MeasurementScheduler(probeFactory: probeFactory),
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
        self.allowsLocalNetworkProbes = allowsLocalNetworkProbes
        self.startsAtLogin = UserDefaults.standard.startsAtLogin ?? (SMAppService.mainApp.status == .enabled)
        self.widgetsEnabled = UserDefaults.standard.widgetsEnabled
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

    var menuBarGlyphContent: MenuBarGlyphContent {
        presenter.menuBarGlyphContent(for: primaryHost, health: snapshot.primaryHealth)
    }

    var visibleSamples: [PingResult] {
        presenter.mergedSamples(
            history: visibleHistorySamples,
            live: presenter.visibleSamples(in: primarySeries, range: selectedRange),
            range: selectedRange
        )
    }

    var primaryStats: SampleStats {
        primarySeries?.stats ?? SampleStats(samples: [])
    }

    var historyExportHost: HostConfig? {
        let selectedID = historyExportHostID ?? primaryHost?.id
        return snapshot.hosts.first { $0.id == selectedID } ?? primaryHost ?? snapshot.hosts.first
    }

    var methodsForCurrentBuild: [PingMethod] {
        BuildFlavor.current.availableMethods
    }

    var draftHost: HostConfig {
        HostConfig(
            id: editingHostID ?? UUID(),
            displayName: draftHostName,
            address: draftHostAddress,
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

    var canAddDraftHost: Bool {
        draftHost.validationErrors.isEmpty
    }

    var draftActionTitle: String {
        editingHostID == nil ? "Add" : "Save"
    }

    func start() {
        snapshotTask?.cancel()
        let stream = Task { await runtime.snapshots() }
        snapshotTask = Task { [weak self] in
            let snapshots = await stream.value
            for await snapshot in snapshots {
                await MainActor.run {
                    self?.snapshot = snapshot
                    self?.persistHostState(snapshot)
                    if let state = self?.menuBarState {
                        self?.onMenuStateChanged?(state)
                    }
                    self?.deliverAlerts(snapshot.alerts, hosts: snapshot.hosts)
                    self?.evaluateInternetLoss(from: snapshot)
                    self?.refreshVisibleHistoryIfNeeded()
                    if self?.widgetsEnabled == true {
                        self?.publishWidgetSnapshot(snapshot)
                    }
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
        networkTask?.cancel()
        historyTask?.cancel()
        pathMonitor.cancel()
        Task { await runtime.stop() }
    }

    func pauseMeasurementsForSleep() {
        Task { await runtime.stopMeasurements() }
    }

    func resumeMeasurementsAfterSystemChange() {
        startNetworkMonitoring()
        Task { await runtime.restartScheduler() }
    }

    func selectHost(_ id: UUID) {
        Task { await runtime.selectPrimaryHost(id) }
        lastHistoryKey = nil
    }

    func selectHostForEditing(_ id: UUID) {
        guard let host = snapshot.hosts.first(where: { $0.id == id }) else { return }
        loadDraft(from: host)
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
        draftHostName = ""
        draftHostAddress = ""
        draftMethod = .tcp
        draftPort = Int(PingMethod.tcp.defaultPort ?? 0)
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

    func testDraftHost() {
        let host = draftHost
        guard host.validationErrors.isEmpty else {
            draftTestResultText = "Fix host settings before testing"
            return
        }

        isTestingDraftHost = true
        draftTestResultText = nil
        Task { [hostTester] in
            let result = await hostTester.test(host)
            await MainActor.run {
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
                let data = try HistoryExporter.data(samples: samples, host: host, format: format)
                try data.write(to: url, options: .atomic)
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
            lastHistoryKey = nil
            return
        }

        let range = selectedRange
        let key = "\(hostID.uuidString)-\(range.rawValue)"
        lastHistoryKey = key
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
            }
        }
    }

    private func persistOverlayFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        overlayFrame = window.frame
        UserDefaults.standard.overlayFrame = window.frame
    }

    private func persistHostState(_ snapshot: RuntimeSnapshot) {
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
            return
        }
    }

    private func deliverAlerts(_ alerts: [AlertDecision], hosts: [HostConfig]) {
        guard notificationRules.isEnabled else { return }
        for alert in alerts {
            Task { [notificationDispatcher] in
                await notificationDispatcher.deliver(alert, hosts: hosts)
            }
        }
    }

    private func evaluateInternetLoss(from snapshot: RuntimeSnapshot) {
        guard enabledNetworkStatusAlerts.contains(.noInternet) else { return }
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
        networkTask = Task { [gatewayDetector] in
            while !Task.isCancelled {
                let host = await gatewayDetector.detect()
                await MainActor.run {
                    self.handleGatewayObservation(host?.address)
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func startNetworkPathMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = Self.networkStatus(from: path)
            Task { @MainActor in
                self?.handleNetworkStatus(status)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func handleGatewayObservation(_ gateway: String?) {
        if gateway == nil, currentNetworkStatus == .connected {
            handleNetworkStatus(.noInternet)
        }
        if let gateway {
            syncDefaultGatewayHost(address: gateway)
        }
        defer { lastObservedGateway = gateway }
        guard lastObservedGateway != nil, lastObservedGateway != gateway else { return }
        guard enabledNetworkStatusAlerts.contains(.connected) || enabledNetworkStatusAlerts.contains(.notConnected) else { return }
        let previousGateway = lastObservedGateway
        Task {
            if let alert = await runtime.evaluateNetworkChange(previousGateway: previousGateway, currentGateway: gateway) {
                await notificationDispatcher.deliver(alert, hosts: snapshot.hosts)
            }
        }
    }

    private func handleNetworkStatus(_ status: NetworkConnectivityStatus) {
        guard status != currentNetworkStatus else { return }
        currentNetworkStatus = status
        if widgetsEnabled {
            publishWidgetSnapshot(snapshot)
        }
        if status == .connected {
            startNetworkMonitoring()
        }
        Task { await runtime.restartScheduler() }
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
        Task { [widgetSnapshotStore] in
            await widgetSnapshotStore.save(widgetSnapshot)
        }
    }

    private func syncDefaultGatewayHost(address gateway: String) {
        guard let existing = snapshot.hosts.first(where: { $0.displayName == "Default Gateway" }),
              existing.address != gateway else {
            return
        }

        var updated = existing
        updated.address = gateway
        updated.method = .tcp
        updated.port = 80
        allowsLocalNetworkProbes = true
        DebugLog.write("default gateway host updated from \(existing.address) to \(gateway)")
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

    nonisolated private static func networkStatus(from path: NWPath) -> NetworkConnectivityStatus {
        switch path.status {
        case .satisfied:
            .connected
        case .requiresConnection:
            .noInternet
        case .unsatisfied:
            path.availableInterfaces.isEmpty ? .notConnected : .noIPAddress
        @unknown default:
            .notConnected
        }
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "PingScope-History" : cleaned
    }

    private func loadDraft(from host: HostConfig) {
        editingHostID = host.id
        draftHostName = host.displayName
        draftHostAddress = host.address
        draftMethod = host.method
        draftPort = Int(host.port ?? host.method.defaultPort ?? 0)
        draftIntervalMilliseconds = host.interval.milliseconds
        draftTimeoutMilliseconds = host.timeout.milliseconds
        draftDegradedThresholdMilliseconds = host.thresholds.degradedMilliseconds
        draftDownAfterFailures = host.thresholds.downAfterFailures
        draftIsEnabled = host.isEnabled
        draftNotificationPolicy = host.notifications
        draftTestResultText = nil
    }
}

private extension UserDefaults {
    var overlayFrame: NSRect? {
        get {
            guard let string = string(forKey: "overlayFrame") else { return nil }
            return NSRectFromString(string)
        }
        set {
            guard let newValue else {
                removeObject(forKey: "overlayFrame")
                return
            }
            set(NSStringFromRect(newValue), forKey: "overlayFrame")
        }
    }

    var hostConfigs: [HostConfig] {
        get {
            guard let data = data(forKey: "hostConfigs") else { return [] }
            return (try? JSONDecoder().decode([HostConfig].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            set(data, forKey: "hostConfigs")
        }
    }

    var primaryHostID: UUID? {
        get {
            guard let string = string(forKey: "primaryHostID") else { return nil }
            return UUID(uuidString: string)
        }
        set {
            set(newValue?.uuidString, forKey: "primaryHostID")
        }
    }

    var notificationRules: NotificationRuleSet? {
        get {
            guard let data = data(forKey: "notificationRules") else { return nil }
            return try? JSONDecoder().decode(NotificationRuleSet.self, from: data)
        }
        set {
            if let data = try? newValue.map(JSONEncoder().encode) {
                set(data, forKey: "notificationRules")
            } else {
                removeObject(forKey: "notificationRules")
            }
        }
    }

    var overlayVisible: Bool {
        get {
            bool(forKey: "overlayVisible")
        }
        set {
            set(newValue, forKey: "overlayVisible")
        }
    }

    var overlayAlwaysOnTop: Bool {
        get {
            guard object(forKey: "overlayAlwaysOnTop") != nil else { return true }
            return bool(forKey: "overlayAlwaysOnTop")
        }
        set {
            set(newValue, forKey: "overlayAlwaysOnTop")
        }
    }

    var overlayOpacity: Double {
        get {
            guard object(forKey: "overlayOpacity") != nil else { return 1 }
            return double(forKey: "overlayOpacity")
        }
        set {
            set(newValue, forKey: "overlayOpacity")
        }
    }

    var overlayCompactMode: Bool {
        get {
            bool(forKey: "overlayCompactMode")
        }
        set {
            set(newValue, forKey: "overlayCompactMode")
        }
    }

    var widgetsEnabled: Bool {
        get {
            bool(forKey: "widgetsEnabled")
        }
        set {
            set(newValue, forKey: "widgetsEnabled")
        }
    }

    var allowsLocalNetworkProbes: Bool {
        get {
            bool(forKey: "allowsLocalNetworkProbes")
        }
        set {
            set(newValue, forKey: "allowsLocalNetworkProbes")
        }
    }

    var startsAtLogin: Bool? {
        get {
            guard object(forKey: "startsAtLogin") != nil else { return nil }
            return bool(forKey: "startsAtLogin")
        }
        set {
            if let newValue {
                set(newValue, forKey: "startsAtLogin")
            } else {
                removeObject(forKey: "startsAtLogin")
            }
        }
    }

    var enabledNetworkStatusAlerts: Set<NetworkConnectivityStatus> {
        get {
            guard let values = array(forKey: "enabledNetworkStatusAlerts") as? [String] else {
                return Set(NetworkConnectivityStatus.allCases)
            }
            return Set(values.compactMap(NetworkConnectivityStatus.init(rawValue:)))
        }
        set {
            set(newValue.map(\.rawValue), forKey: "enabledNetworkStatusAlerts")
        }
    }
}

private extension HistoryExportFormat {
    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        case .text: .plainText
        }
    }
}

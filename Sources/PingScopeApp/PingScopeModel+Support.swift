import AppKit
import Foundation
import PingScopeCore
import PingScopeHistoryKit
import UniformTypeIdentifiers

struct SetupChecklistItem: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let isComplete: Bool
    let actionTitle: String?
    let action: (() -> Void)?
}

extension PingScopeModel {
    var canAddDraftHost: Bool {
        draftHost.validationErrors.isEmpty
    }

    var draftActionTitle: String {
        editingHostID == nil ? "Add Host" : "Save Changes"
    }

    func scheduleNotificationRuleUpdate() {
        notificationRulesTask?.cancel()
        let rules = notificationRules
        notificationRulesTask = Task { [runtime] in
            await runtime.updateNotificationRules(rules)
        }
    }

    func scheduleLocalNetworkProbeUpdate() {
        localNetworkProbeTask?.cancel()
        let allowsLocalNetworkProbes = allowsLocalNetworkProbes
        localNetworkProbeTask = Task { [runtime] in
            await runtime.setAllowsLocalNetworkProbes(allowsLocalNetworkProbes)
        }
    }

    func loadDraft(from host: HostConfig) {
        draftHostID = host.id
        editingHostID = host.id
        isCreatingHost = false
        showsAdvancedHostFields = false
        draftHostName = host.displayName
        draftHostAddress = host.address
        draftNetworkTier = host.tier
        draftMethod = host.method
        draftPort = Int(host.port ?? host.method.defaultPort ?? 0)
        draftIntervalMilliseconds = host.interval.milliseconds
        draftTimeoutMilliseconds = host.timeout.milliseconds
        draftDegradedThresholdMilliseconds = host.thresholds.degradedMilliseconds
        draftDownAfterFailures = host.thresholds.downAfterFailures
        draftIsEnabled = host.isEnabled
        draftNotificationPolicy = host.notifications
        draftDisplayColor = host.displayColor
        draftTestResultText = nil
    }
}

extension UserDefaults {
    var pingScopeMacHistoryRange: HistoryRange {
        get {
            guard let rawValue = string(forKey: "pingScopeMacHistoryRange"),
                  let range = HistoryRange(rawValue: rawValue) else {
                return .defaultValue
            }
            return range
        }
        set {
            set(newValue.rawValue, forKey: "pingScopeMacHistoryRange")
        }
    }

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
            switch storedHostConfigs() {
            case .decoded(let hosts):
                return hosts
            case .missing, .decodeFailed:
                return []
            }
        }
        set {
            try? setHostConfigs(newValue)
        }
    }

    func setHostConfigs(_ hosts: [HostConfig]) throws {
        let store = UserDefaultsSharedHostStore(defaults: self, legacyPlatform: .macOS)
        let existing = store.load().state
        try store.save(
            SharedHostStoreState(
                hosts: hosts,
                primaryHostID: existing?.primaryHostID ?? primaryHostID,
                selectedHostID: existing?.selectedHostID
            )
        )
    }

    func storedHostConfigs() -> StoredHostConfigs {
        guard let data = data(forKey: "hostConfigs") else { return .missing }
        do {
            return .decoded(try JSONDecoder().decode([HostConfig].self, from: data))
        } catch {
            return .decodeFailed(error)
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
            return min(max(double(forKey: "overlayOpacity"), 0.55), 1)
        }
        set {
            set(min(max(newValue, 0.55), 1), forKey: "overlayOpacity")
        }
    }

    var overlayCompactMode: Bool {
        get {
            guard object(forKey: "overlayCompactMode") != nil else { return false }
            return bool(forKey: "overlayCompactMode")
        }
        set {
            set(newValue, forKey: "overlayCompactMode")
        }
    }

    var pingScopeDisplayMode: PingScopeDisplayMode {
        get {
            guard let rawValue = string(forKey: "pingScopeDisplayMode"),
                  let mode = PingScopeDisplayMode(rawValue: rawValue) else {
                return .signal
            }
            return mode
        }
        set {
            set(newValue.rawValue, forKey: "pingScopeDisplayMode")
        }
    }

    var overlayShowsAllHosts: Bool {
        get {
            bool(forKey: "overlayShowsAllHosts")
        }
        set {
            set(newValue, forKey: "overlayShowsAllHosts")
        }
    }

    var popoverShowsAllHosts: Bool {
        get {
            bool(forKey: "popoverShowsAllHosts")
        }
        set {
            set(newValue, forKey: "popoverShowsAllHosts")
        }
    }

    var overlayShowsLegend: Bool {
        get {
            bool(forKey: "overlayShowsLegend")
        }
        set {
            set(newValue, forKey: "overlayShowsLegend")
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

    var widgetSharingOptedIn: Bool? {
        get {
            guard object(forKey: "widgetSharingOptedIn") != nil else { return nil }
            return bool(forKey: "widgetSharingOptedIn")
        }
        set {
            if let newValue {
                set(newValue, forKey: "widgetSharingOptedIn")
            } else {
                removeObject(forKey: "widgetSharingOptedIn")
            }
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
                return NetworkConnectivityStatus.defaultAlertStatuses
            }
            return Set(values.compactMap(NetworkConnectivityStatus.init(rawValue:)))
        }
        set {
            set(newValue.map(\.rawValue), forKey: "enabledNetworkStatusAlerts")
        }
    }

    func migrateNoisyNetworkStatusAlertDefaults() {
        let migrationKey = "didMigrateNoisyNetworkStatusAlertDefaults"
        guard !bool(forKey: migrationKey) else { return }
        defer { set(true, forKey: migrationKey) }

        guard let values = array(forKey: "enabledNetworkStatusAlerts") as? [String] else { return }
        let statuses = Set(values.compactMap(NetworkConnectivityStatus.init(rawValue:)))
        if statuses == Set(NetworkConnectivityStatus.allCases) {
            enabledNetworkStatusAlerts = NetworkConnectivityStatus.defaultAlertStatuses
        }
    }
}

extension HistoryExportFormat {
    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        case .text: .plainText
        }
    }
}

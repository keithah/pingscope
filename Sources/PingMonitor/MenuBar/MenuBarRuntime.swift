import Foundation

@MainActor
final class MenuBarRuntime {
    let menuBarViewModel: MenuBarViewModel
    let hostStore: HostStore
    let gatewayDetector: GatewayDetector
    let globalDefaults: GlobalDefaults

    private let modePreferenceStore: ModePreferenceStore
    private(set) var selectedHostID: UUID?
    private(set) var networkChangeIndicator: Bool = false

    init(
        hostStore: HostStore = HostStore(),
        gatewayDetector: GatewayDetector = GatewayDetector(),
        globalDefaults: GlobalDefaults = .default,
        modePreferenceStore: ModePreferenceStore = ModePreferenceStore()
    ) {
        self.hostStore = hostStore
        self.gatewayDetector = gatewayDetector
        self.globalDefaults = globalDefaults
        self.modePreferenceStore = modePreferenceStore

        menuBarViewModel = MenuBarViewModel(
            isCompactModeEnabled: modePreferenceStore.isCompactModeEnabled,
            isStayOnTopEnabled: modePreferenceStore.isStayOnTopEnabled
        )
    }

    var contextMenuState: ContextMenuState {
        ContextMenuState(
            currentHostSummary: menuBarViewModel.selectedHostSummary,
            isCompactModeEnabled: menuBarViewModel.isCompactModeEnabled,
            isStayOnTopEnabled: menuBarViewModel.isStayOnTopEnabled
        )
    }

    var displayMode: DisplayMode {
        menuBarViewModel.isCompactModeEnabled ? .compact : .full
    }

    func syncSelection(with hosts: [Host], preferredHostID: UUID? = nil) -> Host? {
        let targetHostID = preferredHostID ?? selectedHostID
        let selectedHost = hosts.first { $0.id == targetHostID } ?? hosts.first

        selectedHostID = selectedHost?.id
        if let selectedHost {
            menuBarViewModel.setSelectedHost(selectedHost, globalDefaults: globalDefaults)
        }

        return selectedHost
    }

    func ingestSchedulerResult(_ result: PingResult, isHostUp _: Bool, matchedHostID: UUID?) {
        guard let matchedHostID, matchedHostID == selectedHostID else {
            return
        }

        menuBarViewModel.ingest(result: result)
    }

    func switchHost(in hosts: [Host]) -> Host? {
        guard !hosts.isEmpty else {
            return nil
        }

        guard let selectedHostID,
              let selectedIndex = hosts.firstIndex(where: { $0.id == selectedHostID })
        else {
            return syncSelection(with: hosts)
        }

        let nextIndex = (selectedIndex + 1) % hosts.count
        return syncSelection(with: hosts, preferredHostID: hosts[nextIndex].id)
    }

    func setNetworkChangeIndicator(_ isVisible: Bool) {
        networkChangeIndicator = isVisible
    }

    func toggleCompactMode() {
        setCompactModeEnabled(!menuBarViewModel.isCompactModeEnabled)
    }

    func toggleStayOnTop() {
        setStayOnTopEnabled(!menuBarViewModel.isStayOnTopEnabled)
    }

    func setCompactModeEnabled(_ isEnabled: Bool) {
        menuBarViewModel.isCompactModeEnabled = isEnabled
        modePreferenceStore.isCompactModeEnabled = isEnabled
    }

    func setStayOnTopEnabled(_ isEnabled: Bool) {
        menuBarViewModel.isStayOnTopEnabled = isEnabled
        modePreferenceStore.isStayOnTopEnabled = isEnabled
    }
}

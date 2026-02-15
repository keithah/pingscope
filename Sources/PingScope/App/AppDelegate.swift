import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let modePreferenceStore = ModePreferenceStore()
    private let displayPreferencesStore = DisplayPreferencesStore()
    private lazy var runtime = MenuBarRuntime(modePreferenceStore: modePreferenceStore)
    private let contextMenuFactory = ContextMenuFactory()
    private lazy var displayViewModel = DisplayViewModel(
        preferencesStore: displayPreferencesStore,
        initialMode: modePreferenceStore.displayMode
    )
    private var displayContentFactory: DisplayContentFactory {
        DisplayContentFactory(
            viewModel: displayViewModel,
            menuActions: DisplayMenuActions(
                onToggleCompact: { [weak self] in
                    guard let self else { return }
                    self.setCompactModeEnabled(!self.runtime.menuBarViewModel.isCompactModeEnabled)
                },
                onToggleStayOnTop: { [weak self] in
                    guard let self else { return }
                    self.setStayOnTopEnabled(!self.runtime.menuBarViewModel.isStayOnTopEnabled)
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.quitApp()
                },
                isCompactEnabled: runtime.menuBarViewModel.isCompactModeEnabled,
                isStayOnTopEnabled: runtime.menuBarViewModel.isStayOnTopEnabled
            )
        )
    }
    private lazy var displayCoordinator = DisplayModeCoordinator(
        displayPreferencesStore: displayPreferencesStore
    )
    private let scheduler = PingScheduler(
        pingService: PingService(),
        healthTracker: HostHealthTracker()
    )

    private let notificationPreferencesStore = NotificationPreferencesStore()
    private lazy var notificationService = NotificationService(
        preferencesStore: notificationPreferencesStore
    )
    private var previousGatewayIP: String? = nil
    private var latestHostUpStates: [UUID: Bool] = [:]

    private var statusItemController: StatusItemController?
    private var hostListViewModel: HostListViewModel?
    private var settingsWindowController: NSWindowController?
    private var gatewayMonitorTask: Task<Void, Never>?
    private var networkIndicatorTask: Task<Void, Never>?
    private var monitoredHosts: [Host] = []
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else {
            // Bring existing instance forward and exit this one.
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.setActivationPolicy(.accessory)

        hostListViewModel = makeHostListViewModel()
        bindDisplaySelection()

        statusItemController = StatusItemController(
            viewModel: runtime.menuBarViewModel,
            onTogglePopover: { [weak self] in
                self?.togglePopover()
            },
            onRequestContextMenu: { [weak self] button in
                self?.showContextMenu(from: button)
            }
        )

        startScheduler()
        startGatewayMonitoring()

        Task {
            let status = await notificationService.checkAuthorizationStatus()
            guard status == .notDetermined else {
                return
            }

            // Give the run loop a moment to settle before prompting.
            try? await Task.sleep(for: .milliseconds(400))

            // The permission prompt is system-modal; make sure we're frontmost when it appears.
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
            }
            _ = await notificationService.requestAuthorization()
        }

        Task {
            await self.refreshHostsAndScheduler()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gatewayMonitorTask?.cancel()
        networkIndicatorTask?.cancel()

        Task {
            await scheduler.stop()
            await runtime.gatewayDetector.stopMonitoring()
        }
    }

    private func startScheduler() {
        Task { [weak self] in
            guard let self else { return }

            await scheduler.setResultHandler { [weak self] result, isHostUp in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let matchedHostID = self.hostID(for: result)
                    self.runtime.ingestSchedulerResult(result, isHostUp: isHostUp, matchedHostID: matchedHostID)
                    if let matchedHostID {
                        self.displayViewModel.ingest(result, for: matchedHostID)
                    }

                    guard let matchedHostID else {
                        return
                    }

                    let latencyMS = result.latency.map(Self.durationToMilliseconds)
                    self.hostListViewModel?.updateLatency(for: matchedHostID, latencyMS: latencyMS)

                    if let host = self.monitoredHosts.first(where: { $0.id == matchedHostID }) {
                        self.latestHostUpStates[matchedHostID] = isHostUp
#if DEBUG
                        let latencyText = result.latency.map { "\(Int(Self.durationToMilliseconds($0).rounded()))ms" } ?? "failed"
                        print("[Notifications] Evaluating result for \(host.name): \(latencyText)")
#endif
                        Task {
                            await self.notificationService.evaluateResult(result, for: host, isHostUp: isHostUp)
                        }
                    }

                    Task {
                        let hostResults = await self.collectHostResults()
                        await self.notificationService.evaluateInternetLoss(hostResults: hostResults)
                    }
                }
            }

            await scheduler.start(hosts: [], intervalFallback: runtime.globalDefaults.interval)
        }
    }

    private func startGatewayMonitoring() {
        gatewayMonitorTask?.cancel()
        gatewayMonitorTask = Task { [weak self] in
            guard let self else {
                return
            }

            let stream = await runtime.gatewayDetector.startMonitoring()
            for await gatewayInfo in stream {
                await self.handleGatewayUpdate(gatewayInfo)
            }
        }
    }

    private func handleGatewayUpdate(_ gatewayInfo: GatewayInfo) async {
        let previousGateway = await runtime.hostStore.gatewayHost

        let currentGatewayIP = gatewayInfo.isAvailable ? gatewayInfo.ipAddress : nil

        if gatewayInfo.isAvailable {
            await runtime.hostStore.setGatewayHost(gatewayInfo)
        } else {
            await runtime.hostStore.clearGatewayHost()
        }

        let gatewayChanged = previousGatewayIP != currentGatewayIP
            || previousGateway?.name != (gatewayInfo.isAvailable ? gatewayInfo.displayName : nil)

        if gatewayChanged {
            showNetworkChangeIndicator()

            let previousIP = previousGatewayIP
            previousGatewayIP = currentGatewayIP
            Task {
                await notificationService.evaluateGatewayChange(from: previousIP, to: currentGatewayIP)
            }
        }

        await refreshHostsAndScheduler()
    }

    private func showNetworkChangeIndicator() {
        networkIndicatorTask?.cancel()
        runtime.setNetworkChangeIndicator(true)

        networkIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self else {
                    return
                }
                self.runtime.setNetworkChangeIndicator(false)
            }
        }
    }

    private func togglePopover() {
        guard let button = statusItemController?.button else {
            return
        }

        if isDisplayPresented {
            displayCoordinator.closeAll()
        } else {
            presentDisplay(from: button)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = contextMenuFactory.makeMenu(
            state: runtime.contextMenuState,
            actions: ContextMenuActions(
                onSwitchHost: { [weak self] in
                    self?.switchHostAndRefreshScheduler()
                },
                onToggleCompactMode: { [weak self] in
                    guard let self else {
                        return
                    }

                    self.setCompactModeEnabled(!self.runtime.menuBarViewModel.isCompactModeEnabled)
                },
                onToggleStayOnTop: { [weak self] in
                    guard let self else {
                        return
                    }

                    self.setStayOnTopEnabled(!self.runtime.menuBarViewModel.isStayOnTopEnabled)
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.quitApp()
                }
            )
        )

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func switchHostAndRefreshScheduler() {
        Task {
            let hosts = await runtime.hostStore.allHosts
            _ = runtime.switchHost(in: hosts)
            hostListViewModel?.activeHostID = runtime.selectedHostID
            displayViewModel.selectHost(id: runtime.selectedHostID)
            await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
        }
    }

    private func makeHostListViewModel() -> HostListViewModel {
        HostListViewModel(
            onSelectHost: { [weak self] host in
                guard let self else {
                    return
                }

                Task {
                    await self.selectHostAndRefresh(host)
                }
            },
            onAddHost: { [weak self] host in
                guard let self else {
                    return
                }

                Task {
                    await self.runtime.hostStore.add(host)
                    await self.refreshHostsAndScheduler(preferredHostID: host.id)
                }
            },
            onUpdateHost: { [weak self] host in
                guard let self else {
                    return
                }

                Task {
                    await self.runtime.hostStore.update(host)
                    await self.refreshHostsAndScheduler(preferredHostID: host.id)
                }
            },
            onDeleteHost: { [weak self] host in
                guard let self else {
                    return
                }

                Task {
                    await self.runtime.hostStore.remove(host)
                    await self.refreshHostsAndScheduler()
                }
            }
        )
    }

    private func selectHostAndRefresh(_ host: Host) async {
        let hosts = await runtime.hostStore.allHosts
        _ = runtime.syncSelection(with: hosts, preferredHostID: host.id)
        hostListViewModel?.activeHostID = runtime.selectedHostID
        displayViewModel.selectHost(id: runtime.selectedHostID)
        await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
    }

    private func refreshHostsAndScheduler(preferredHostID: UUID? = nil) async {
        let hosts = await runtime.hostStore.allHosts
        monitoredHosts = hosts

        let currentHostIDs = Set(hosts.map(\.id))
        latestHostUpStates = latestHostUpStates.filter { currentHostIDs.contains($0.key) }

        let selectedHost = runtime.syncSelection(with: hosts, preferredHostID: preferredHostID)
        hostListViewModel?.hosts = hosts
        hostListViewModel?.activeHostID = selectedHost?.id
        displayViewModel.setHosts(hosts)
        displayViewModel.selectHost(id: selectedHost?.id)

        let currentLatencyHostIDs = Set(hostListViewModel?.latencies.keys.map { $0 } ?? [])
        let staleHostIDs = currentLatencyHostIDs.subtracting(Set(hosts.map(\.id)))
        for staleHostID in staleHostIDs {
            hostListViewModel?.latencies.removeValue(forKey: staleHostID)
        }

        await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
    }

    private func collectHostResults() async -> [(Host, Bool)] {
        monitoredHosts.map { host in
            let isUp = latestHostUpStates[host.id] ?? true
            return (host, isUp)
        }
    }

    private func hostID(for result: PingResult) -> UUID? {
        monitoredHosts.first {
            $0.address.caseInsensitiveCompare(result.host) == .orderedSame &&
                $0.port == result.port
        }?.id
    }

    private static func durationToMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let secondsMS = Double(components.seconds) * 1_000
        let attosecondsMS = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMS + attosecondsMS
    }

    @objc
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI's built-in Settings scene can be unreliable for accessory/menu-bar apps
        // launched outside of Xcode. Always use a dedicated settings window.
        if settingsWindowController == nil {
            guard let hostListViewModel else {
                return
            }

            let rootView = PingMonitorSettingsView(
                hostListViewModel: hostListViewModel,
                displayViewModel: displayViewModel,
                notificationStore: notificationPreferencesStore,
                onSetCompactModeEnabled: { [weak self] isEnabled in
                    self?.setCompactModeEnabled(isEnabled)
                },
                onSetStayOnTopEnabled: { [weak self] isEnabled in
                    self?.setStayOnTopEnabled(isEnabled)
                },
                onResetAll: { [weak self] in
                    self?.resetToDefaults()
                },
                onClose: { [weak self] in
                    self?.settingsWindowController?.close()
                }
            )

            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "PingMonitor Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 660))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func resetToDefaults() {
        // App/display preferences
        modePreferenceStore.reset()
        displayPreferencesStore.reset()
        notificationPreferencesStore.reset()
        _ = StartOnLaunchService.setEnabled(false)

        // Apply mode toggles immediately in the running UI
        setCompactModeEnabled(false)
        setStayOnTopEnabled(false)

        // Restore display section defaults
        displayViewModel.setShowsMonitoredHosts(true)
        displayViewModel.setShowsHistorySummary(false)
        displayViewModel.setGraphVisible(true, for: .full)
        displayViewModel.setHistoryVisible(true, for: .full)
        displayViewModel.setTimeRange(.fiveMinutes)

        // Reset hosts
        Task { [weak self] in
            guard let self else { return }
            await self.runtime.hostStore.resetToDefaults()
            await self.refreshHostsAndScheduler()
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func enforceSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, !bundleIdentifier.isEmpty else {
            // When launched via a non-bundled SwiftPM executable, there is no bundle identifier.
            // Don't attempt to enforce single-instance in that case.
            return true
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = others.first else {
            return true
        }

        existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return false
    }

    func setCompactModeEnabled(_ isEnabled: Bool) {
        guard runtime.menuBarViewModel.isCompactModeEnabled != isEnabled else {
            return
        }

        runtime.setCompactModeEnabled(isEnabled)
        displayViewModel.setDisplayMode(runtime.displayMode)
        refreshPresentedDisplayIfNeeded()
    }

    func setStayOnTopEnabled(_ isEnabled: Bool) {
        guard runtime.menuBarViewModel.isStayOnTopEnabled != isEnabled else {
            return
        }

        runtime.setStayOnTopEnabled(isEnabled)
        refreshPresentedDisplayIfNeeded()
    }

    private var isDisplayPresented: Bool {
        displayCoordinator.isDisplayVisible
    }

    private func refreshPresentedDisplayIfNeeded() {
        guard let button = statusItemController?.button, isDisplayPresented else {
            return
        }

        presentDisplay(from: button)
    }

    private func presentDisplay(from button: NSStatusBarButton) {
        displayViewModel.setDisplayMode(runtime.displayMode)
        let contentViewController = displayContentFactory.make(
            mode: runtime.displayMode,
            showsFloatingChrome: runtime.menuBarViewModel.isStayOnTopEnabled
        )
        displayCoordinator.open(
            from: button,
            mode: runtime.displayMode,
            isStayOnTopEnabled: runtime.menuBarViewModel.isStayOnTopEnabled,
            contentViewController: contentViewController
        )
    }

    private func bindDisplaySelection() {
        displayViewModel.$selectedHostID
            .dropFirst()
            .sink { [weak self] selectedHostID in
                guard let self else {
                    return
                }

                Task {
                    await self.syncRuntimeSelection(with: selectedHostID)
                }
            }
            .store(in: &cancellables)
    }

    private func syncRuntimeSelection(with selectedHostID: UUID?) async {
        guard runtime.selectedHostID != selectedHostID else {
            return
        }

        let hosts = await runtime.hostStore.allHosts
        _ = runtime.syncSelection(with: hosts, preferredHostID: selectedHostID)
        hostListViewModel?.activeHostID = runtime.selectedHostID
        await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
    }
}

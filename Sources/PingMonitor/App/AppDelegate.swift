import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime = MenuBarRuntime()
    private let contextMenuFactory = ContextMenuFactory()
    private let scheduler = PingScheduler(
        pingService: PingService(),
        healthTracker: HostHealthTracker()
    )

    private var statusItemController: StatusItemController?
    private var statusPopoverViewModel: StatusPopoverViewModel?
    private var hostListViewModel: HostListViewModel?
    private let popover = NSPopover()
    private var settingsWindowController: NSWindowController?
    private var gatewayMonitorTask: Task<Void, Never>?
    private var networkIndicatorTask: Task<Void, Never>?
    private var monitoredHosts: [Host] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 340, height: 440)

        hostListViewModel = makeHostListViewModel()
        statusPopoverViewModel = StatusPopoverViewModel(
            menuBarViewModel: runtime.menuBarViewModel,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task {
                    await self.scheduler.refresh(intervalFallback: self.runtime.globalDefaults.interval)
                }
            },
            onSwitchHost: { [weak self] in
                self?.switchHostAndRefreshScheduler()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )

        if let statusPopoverViewModel {
            popover.contentViewController = NSHostingController(
                rootView: StatusPopoverView(
                    viewModel: statusPopoverViewModel,
                    hostListViewModel: hostListViewModel
                )
            )
        }

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

                    guard let matchedHostID else {
                        return
                    }

                    let latencyMS = result.latency.map(Self.durationToMilliseconds)
                    self.hostListViewModel?.updateLatency(for: matchedHostID, latencyMS: latencyMS)
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

        if gatewayInfo.isAvailable {
            await runtime.hostStore.setGatewayHost(gatewayInfo)
        } else {
            await runtime.hostStore.clearGatewayHost()
        }

        let gatewayChanged = previousGateway?.address != (gatewayInfo.isAvailable ? gatewayInfo.ipAddress : nil)
            || previousGateway?.name != (gatewayInfo.isAvailable ? gatewayInfo.displayName : nil)

        if gatewayChanged {
            showNetworkChangeIndicator()
        }

        await refreshHostsAndScheduler()
    }

    private func showNetworkChangeIndicator() {
        networkIndicatorTask?.cancel()
        runtime.setNetworkChangeIndicator(true)
        statusPopoverViewModel?.setNetworkChangeIndicator(true)

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
                self.statusPopoverViewModel?.setNetworkChangeIndicator(false)
            }
        }
    }

    private func togglePopover() {
        guard let button = statusItemController?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
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
                    self?.runtime.toggleCompactMode()
                },
                onToggleStayOnTop: { [weak self] in
                    self?.runtime.toggleStayOnTop()
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
        await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
    }

    private func refreshHostsAndScheduler(preferredHostID: UUID? = nil) async {
        let hosts = await runtime.hostStore.allHosts
        monitoredHosts = hosts

        let selectedHost = runtime.syncSelection(with: hosts, preferredHostID: preferredHostID)
        hostListViewModel?.hosts = hosts
        hostListViewModel?.activeHostID = selectedHost?.id

        let currentLatencyHostIDs = Set(hostListViewModel?.latencies.keys.map { $0 } ?? [])
        let staleHostIDs = currentLatencyHostIDs.subtracting(Set(hosts.map(\.id)))
        for staleHostID in staleHostIDs {
            hostListViewModel?.latencies.removeValue(forKey: staleHostID)
        }

        await scheduler.updateHosts(hosts, intervalFallback: runtime.globalDefaults.interval)
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

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }

        if settingsWindowController == nil {
            let hostingController = NSHostingController(rootView: SettingsPlaceholderView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 420, height: 260))
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

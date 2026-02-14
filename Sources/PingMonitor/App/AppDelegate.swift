import AppKit
import SwiftUI

@MainActor
final class MenuBarRuntime {
    let menuBarViewModel: MenuBarViewModel

    private let modePreferenceStore: ModePreferenceStore
    private(set) var availableHosts: [Host]
    private(set) var selectedHostIndex: Int

    init(
        hosts: [Host] = [.googleDNS, .cloudflareDNS],
        selectedHostIndex: Int = 0,
        modePreferenceStore: ModePreferenceStore = ModePreferenceStore()
    ) {
        self.modePreferenceStore = modePreferenceStore
        availableHosts = hosts
        self.selectedHostIndex = max(0, min(selectedHostIndex, max(0, hosts.count - 1)))

        menuBarViewModel = MenuBarViewModel(
            isCompactModeEnabled: modePreferenceStore.isCompactModeEnabled,
            isStayOnTopEnabled: modePreferenceStore.isStayOnTopEnabled
        )

        if let selectedHost {
            menuBarViewModel.setSelectedHost(selectedHost)
        }
    }

    var selectedHost: Host? {
        guard availableHosts.indices.contains(selectedHostIndex) else {
            return nil
        }

        return availableHosts[selectedHostIndex]
    }

    var contextMenuState: ContextMenuState {
        ContextMenuState(
            currentHostSummary: menuBarViewModel.selectedHostSummary,
            isCompactModeEnabled: menuBarViewModel.isCompactModeEnabled,
            isStayOnTopEnabled: menuBarViewModel.isStayOnTopEnabled
        )
    }

    func ingestSchedulerResult(_ result: PingResult, isHostUp _: Bool) {
        menuBarViewModel.ingest(result: result)
    }

    func switchHost() {
        guard !availableHosts.isEmpty else {
            return
        }

        selectedHostIndex = (selectedHostIndex + 1) % availableHosts.count
        if let selectedHost {
            menuBarViewModel.setSelectedHost(selectedHost)
        }
    }

    func toggleCompactMode() {
        menuBarViewModel.isCompactModeEnabled.toggle()
        modePreferenceStore.isCompactModeEnabled = menuBarViewModel.isCompactModeEnabled
    }

    func toggleStayOnTop() {
        menuBarViewModel.isStayOnTopEnabled.toggle()
        modePreferenceStore.isStayOnTopEnabled = menuBarViewModel.isStayOnTopEnabled
    }
}

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
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 300, height: 220)
        statusPopoverViewModel = StatusPopoverViewModel(
            menuBarViewModel: runtime.menuBarViewModel,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task {
                    await self.scheduler.refresh()
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
                rootView: StatusPopoverView(viewModel: statusPopoverViewModel)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await scheduler.stop()
        }
    }

    private func startScheduler() {
        Task { [weak self] in
            guard let self else { return }

            await scheduler.setResultHandler { [weak self] result, isHostUp in
                Task { @MainActor [weak self] in
                    self?.runtime.ingestSchedulerResult(result, isHostUp: isHostUp)
                }
            }

            if let selectedHost = runtime.selectedHost {
                await scheduler.start(hosts: [selectedHost], interval: .seconds(30))
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
        runtime.switchHost()

        guard let selectedHost = runtime.selectedHost else {
            return
        }

        Task {
            await scheduler.updateHosts([selectedHost])
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

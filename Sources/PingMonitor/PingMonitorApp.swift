import AppKit
import SwiftUI

@main
struct PingMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ContentView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarViewModel: MenuBarViewModel?
    private var statusItemController: StatusItemController?
    private let contextMenuFactory = ContextMenuFactory()
    private let modePreferenceStore = ModePreferenceStore()
    private var popover = NSPopover()
    private var availableHosts: [Host] = [.googleDNS, .cloudflareDNS]
    private var selectedHostIndex = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = MenuBarViewModel(
            isCompactModeEnabled: modePreferenceStore.isCompactModeEnabled,
            isStayOnTopEnabled: modePreferenceStore.isStayOnTopEnabled
        )
        viewModel.setSelectedHost(availableHosts[selectedHostIndex])
        menuBarViewModel = viewModel

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 180)
        popover.contentViewController = NSHostingController(rootView: ContentView())

        statusItemController = StatusItemController(
            viewModel: viewModel,
            onTogglePopover: { [weak self] in
                self?.togglePopover()
            },
            onRequestContextMenu: { [weak self] button in
                self?.showContextMenu(from: button)
            }
        )
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
        guard let viewModel = menuBarViewModel else {
            return
        }

        let menu = contextMenuFactory.makeMenu(
            state: ContextMenuState(
                currentHostSummary: viewModel.selectedHostSummary,
                isCompactModeEnabled: viewModel.isCompactModeEnabled,
                isStayOnTopEnabled: viewModel.isStayOnTopEnabled
            ),
            actions: ContextMenuActions(
                onSwitchHost: { [weak self] in self?.switchHost() },
                onToggleCompactMode: { [weak self] in self?.toggleCompactMode() },
                onToggleStayOnTop: { [weak self] in self?.toggleStayOnTop() },
                onOpenSettings: { [weak self] in self?.openSettings() },
                onQuit: { [weak self] in self?.quitApp() }
            )
        )

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func switchHost() {
        guard let viewModel = menuBarViewModel, !availableHosts.isEmpty else {
            return
        }

        selectedHostIndex = (selectedHostIndex + 1) % availableHosts.count
        viewModel.setSelectedHost(availableHosts[selectedHostIndex])
    }

    private func toggleCompactMode() {
        guard let viewModel = menuBarViewModel else {
            return
        }

        viewModel.isCompactModeEnabled.toggle()
        modePreferenceStore.isCompactModeEnabled = viewModel.isCompactModeEnabled
    }

    private func toggleStayOnTop() {
        guard let viewModel = menuBarViewModel else {
            return
        }

        viewModel.isStayOnTopEnabled.toggle()
        modePreferenceStore.isStayOnTopEnabled = viewModel.isStayOnTopEnabled
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

struct ContentView: View {
    var body: some View {
        Text("PingMonitor")
            .font(.title2)
            .padding()
    }
}

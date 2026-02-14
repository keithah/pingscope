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
    private var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = MenuBarViewModel()
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
                self?.showFallbackContextMenu(from: button)
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

    private func showFallbackContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu(title: "PingMonitor")
        menu.addItem(NSMenuItem(title: "Switch Host...", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
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

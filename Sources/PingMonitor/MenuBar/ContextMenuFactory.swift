import AppKit
import Foundation

struct ContextMenuState: Equatable {
    var currentHostSummary: String
    var isCompactModeEnabled: Bool
    var isStayOnTopEnabled: Bool
}

struct ContextMenuActions {
    var onSwitchHost: () -> Void
    var onToggleCompactMode: () -> Void
    var onToggleStayOnTop: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
}

enum ContextMenuItemID {
    static let currentHost = NSUserInterfaceItemIdentifier("context.currentHost")
    static let switchHost = NSUserInterfaceItemIdentifier("context.switchHost")
    static let compactMode = NSUserInterfaceItemIdentifier("context.compactMode")
    static let stayOnTop = NSUserInterfaceItemIdentifier("context.stayOnTop")
    static let settings = NSUserInterfaceItemIdentifier("context.settings")
    static let quit = NSUserInterfaceItemIdentifier("context.quit")
}

@MainActor
final class ContextMenuFactory {
    func makeMenu(state: ContextMenuState, actions: ContextMenuActions) -> NSMenu {
        let relay = MenuActionRelay(actions: actions)
        let menu = NSMenu(title: "PingMonitor")
        menu.autoenablesItems = false
        menu.delegate = relay

        let currentHostItem = NSMenuItem(title: "Current Host: \(state.currentHostSummary)", action: nil, keyEquivalent: "")
        currentHostItem.isEnabled = false
        currentHostItem.identifier = ContextMenuItemID.currentHost
        menu.addItem(currentHostItem)

        let switchHostItem = NSMenuItem(
            title: "Switch Host...",
            action: #selector(MenuActionRelay.switchHost),
            keyEquivalent: ""
        )
        switchHostItem.target = relay
        switchHostItem.identifier = ContextMenuItemID.switchHost
        menu.addItem(switchHostItem)

        menu.addItem(.separator())

        let compactModeItem = NSMenuItem(
            title: "Compact Mode",
            action: #selector(MenuActionRelay.toggleCompactMode),
            keyEquivalent: ""
        )
        compactModeItem.target = relay
        compactModeItem.state = state.isCompactModeEnabled ? .on : .off
        compactModeItem.identifier = ContextMenuItemID.compactMode
        menu.addItem(compactModeItem)

        let stayOnTopItem = NSMenuItem(
            title: "Stay on Top",
            action: #selector(MenuActionRelay.toggleStayOnTop),
            keyEquivalent: ""
        )
        stayOnTopItem.target = relay
        stayOnTopItem.state = state.isStayOnTopEnabled ? .on : .off
        stayOnTopItem.identifier = ContextMenuItemID.stayOnTop
        menu.addItem(stayOnTopItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(MenuActionRelay.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = relay
        settingsItem.identifier = ContextMenuItemID.settings
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(MenuActionRelay.quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = relay
        quitItem.identifier = ContextMenuItemID.quit
        menu.addItem(quitItem)

        objc_setAssociatedObject(menu, MenuAssociationKey.relayKey, relay, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return menu
    }
}

private enum MenuAssociationKey {
    static var relayKey = "ContextMenuRelayKey"
}

@MainActor
private final class MenuActionRelay: NSObject, NSMenuDelegate {
    private let actions: ContextMenuActions

    init(actions: ContextMenuActions) {
        self.actions = actions
    }

    @objc
    func switchHost() {
        actions.onSwitchHost()
    }

    @objc
    func toggleCompactMode() {
        actions.onToggleCompactMode()
    }

    @objc
    func toggleStayOnTop() {
        actions.onToggleStayOnTop()
    }

    @objc
    func openSettings() {
        actions.onOpenSettings()
    }

    @objc
    func quitApp() {
        actions.onQuit()
    }
}

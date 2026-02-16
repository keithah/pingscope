import AppKit
import Foundation
import XCTest
@testable import PingScope

@MainActor
final class MenuBarIntegrationSmokeTests: XCTestCase {
    func testSchedulerResultUpdatesMenuBarViewModelState() {
        let runtime = MenuBarRuntime()
        let hosts = [Host.googleDNS]
        let selectedHost = runtime.syncSelection(with: hosts)

        runtime.ingestSchedulerResult(
            PingResult.success(host: "8.8.8.8", port: 443, latency: .milliseconds(48)),
            isHostUp: true,
            matchedHostID: selectedHost?.id
        )

        XCTAssertEqual(runtime.menuBarViewModel.status, .green)
        XCTAssertEqual(runtime.menuBarViewModel.compactLatencyText, "48 ms")
    }

    func testContextMenuCallbacksToggleAndPersistModePreferences() {
        let suiteName = "MenuBarIntegrationSmokeTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }

        let store = ModePreferenceStore(userDefaults: userDefaults, keyPrefix: "integration.mode")
        let runtime = MenuBarRuntime(modePreferenceStore: store)
        let hosts = [Host.googleDNS, Host.cloudflareDNS]
        let menu = ContextMenuFactory().makeMenu(
            state: runtime.contextMenuState,
            actions: .init(
                onSwitchHost: { runtime.switchHost(in: hosts) },
                onToggleCompactMode: { runtime.toggleCompactMode() },
                onToggleStayOnTop: { runtime.toggleStayOnTop() },
                onOpenSettings: {},
                onOpenAbout: {},
                onQuit: {}
            )
        )

        trigger(menuItem(in: menu, id: ContextMenuItemID.compactMode))
        trigger(menuItem(in: menu, id: ContextMenuItemID.stayOnTop))

        XCTAssertEqual(runtime.displayMode, .compact)
        XCTAssertTrue(runtime.menuBarViewModel.isCompactModeEnabled)
        XCTAssertTrue(runtime.menuBarViewModel.isStayOnTopEnabled)
        XCTAssertEqual(preferredShell(for: runtime), "floating")
        XCTAssertTrue(store.isCompactModeEnabled)
        XCTAssertTrue(store.isStayOnTopEnabled)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSwitchHostActionUpdatesMenuAndPopoverReadableState() {
        let runtime = MenuBarRuntime()
        let hosts = [Host.googleDNS, Host.cloudflareDNS]
        _ = runtime.syncSelection(with: hosts, preferredHostID: hosts[0].id)
        let popoverViewModel = StatusPopoverViewModel(menuBarViewModel: runtime.menuBarViewModel)

        XCTAssertEqual(runtime.contextMenuState.currentHostSummary, "Google DNS (8.8.8.8)")
        XCTAssertEqual(popoverViewModel.snapshot.hostSummary, "Google DNS (8.8.8.8)")

        _ = runtime.switchHost(in: hosts)

        XCTAssertEqual(runtime.contextMenuState.currentHostSummary, "Cloudflare (1.1.1.1)")
        XCTAssertEqual(popoverViewModel.snapshot.hostSummary, "Cloudflare (1.1.1.1)")
    }

    func testDisplayModeTogglePreservesDisplaySelectionContext() {
        let suiteName = "MenuBarIntegrationSmokeTests-DisplaySelection-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let runtime = MenuBarRuntime(
            modePreferenceStore: ModePreferenceStore(
                userDefaults: userDefaults,
                keyPrefix: "integration.mode"
            )
        )
        let displayViewModel = DisplayViewModel(
            preferencesStore: DisplayPreferencesStore(
                userDefaults: userDefaults,
                keyPrefix: "integration.display"
            )
        )
        let hosts = [Host.googleDNS, Host.cloudflareDNS]

        _ = runtime.syncSelection(with: hosts, preferredHostID: hosts[1].id)
        displayViewModel.setHosts(hosts)
        displayViewModel.selectHost(id: hosts[1].id)
        displayViewModel.setTimeRange(.oneHour)

        runtime.toggleCompactMode()
        displayViewModel.setDisplayMode(runtime.displayMode)
        runtime.toggleCompactMode()
        displayViewModel.setDisplayMode(runtime.displayMode)

        XCTAssertEqual(displayViewModel.selectedHostID, hosts[1].id)
        XCTAssertEqual(displayViewModel.selectedTimeRange, .oneHour)
        XCTAssertEqual(runtime.selectedHostID, hosts[1].id)
    }

    private func menuItem(in menu: NSMenu, id: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        menu.items.first { $0.identifier == id }
    }

    private func trigger(_ item: NSMenuItem?) {
        guard let item, let target = item.target else {
            XCTFail("Menu item missing target")
            return
        }

        guard let action = item.action else {
            XCTFail("Menu item missing action")
            return
        }

        _ = target.perform(action, with: item)
    }

    private func preferredShell(for runtime: MenuBarRuntime) -> String {
        runtime.menuBarViewModel.isStayOnTopEnabled ? "floating" : "standardWindow"
    }
}

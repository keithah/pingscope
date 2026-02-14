import AppKit
import Foundation
import XCTest
@testable import PingMonitor

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
                onQuit: {}
            )
        )

        trigger(menuItem(in: menu, id: ContextMenuItemID.compactMode))
        trigger(menuItem(in: menu, id: ContextMenuItemID.stayOnTop))

        XCTAssertTrue(runtime.menuBarViewModel.isCompactModeEnabled)
        XCTAssertTrue(runtime.menuBarViewModel.isStayOnTopEnabled)
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
}

import AppKit
import Foundation
import XCTest
@testable import PingMonitor

@MainActor
final class MenuBarIntegrationSmokeTests: XCTestCase {
    func testSchedulerResultUpdatesMenuBarViewModelState() {
        let runtime = MenuBarRuntime()

        runtime.ingestSchedulerResult(
            PingResult.success(host: "8.8.8.8", port: 443, latency: .milliseconds(48)),
            isHostUp: true
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
        let menu = ContextMenuFactory().makeMenu(
            state: runtime.contextMenuState,
            actions: .init(
                onSwitchHost: { runtime.switchHost() },
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
        let runtime = MenuBarRuntime(hosts: [.googleDNS, .cloudflareDNS], selectedHostIndex: 0)
        let popoverViewModel = StatusPopoverViewModel(menuBarViewModel: runtime.menuBarViewModel)

        XCTAssertEqual(runtime.contextMenuState.currentHostSummary, "Google DNS (8.8.8.8)")
        XCTAssertEqual(popoverViewModel.snapshot.hostSummary, "Google DNS (8.8.8.8)")

        runtime.switchHost()

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

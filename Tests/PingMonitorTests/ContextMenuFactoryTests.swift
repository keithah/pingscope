import AppKit
import Foundation
import XCTest
@testable import PingMonitor

@MainActor
final class ContextMenuFactoryTests: XCTestCase {
    func testMenuStructureIncludesRequiredSectionsAndItems() {
        let menu = makeMenu(state: .init(currentHostSummary: "Google DNS (8.8.8.8)", isCompactModeEnabled: false, isStayOnTopEnabled: false))

        XCTAssertEqual(menu.items.count, 8)
        XCTAssertEqual(menu.items[0].title, "Current Host: Google DNS (8.8.8.8)")
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertEqual(menu.items[1].title, "Switch Host...")
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Compact Mode")
        XCTAssertEqual(menu.items[4].title, "Stay on Top")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, "Settings...")
        XCTAssertEqual(menu.items[7].title, "Quit")
    }

    func testToggleCheckedStateReflectsState() {
        let menu = makeMenu(state: .init(currentHostSummary: "Cloudflare (1.1.1.1)", isCompactModeEnabled: true, isStayOnTopEnabled: false))

        XCTAssertEqual(menuItem(in: menu, id: ContextMenuItemID.compactMode)?.state, .on)
        XCTAssertEqual(menuItem(in: menu, id: ContextMenuItemID.stayOnTop)?.state, .off)
    }

    func testActionsInvokeCallbacks() {
        var switchHostCalled = false
        var toggleCompactCalled = false
        var toggleStayOnTopCalled = false
        var openSettingsCalled = false
        var quitCalled = false

        let factory = ContextMenuFactory()
        let menu = factory.makeMenu(
            state: .init(currentHostSummary: "Google DNS (8.8.8.8)", isCompactModeEnabled: false, isStayOnTopEnabled: false),
            actions: .init(
                onSwitchHost: { switchHostCalled = true },
                onToggleCompactMode: { toggleCompactCalled = true },
                onToggleStayOnTop: { toggleStayOnTopCalled = true },
                onOpenSettings: { openSettingsCalled = true },
                onQuit: { quitCalled = true }
            )
        )

        trigger(menuItem(in: menu, id: ContextMenuItemID.switchHost))
        trigger(menuItem(in: menu, id: ContextMenuItemID.compactMode))
        trigger(menuItem(in: menu, id: ContextMenuItemID.stayOnTop))
        trigger(menuItem(in: menu, id: ContextMenuItemID.settings))
        trigger(menuItem(in: menu, id: ContextMenuItemID.quit))

        XCTAssertTrue(switchHostCalled)
        XCTAssertTrue(toggleCompactCalled)
        XCTAssertTrue(toggleStayOnTopCalled)
        XCTAssertTrue(openSettingsCalled)
        XCTAssertTrue(quitCalled)
    }

    func testModePreferenceStorePersistsValues() {
        let suiteName = "ContextMenuFactoryTests-\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }

        let store = ModePreferenceStore(userDefaults: userDefaults, keyPrefix: "test.mode")
        store.isCompactModeEnabled = true
        store.isStayOnTopEnabled = true

        let restored = ModePreferenceStore(userDefaults: userDefaults, keyPrefix: "test.mode")
        XCTAssertTrue(restored.isCompactModeEnabled)
        XCTAssertTrue(restored.isStayOnTopEnabled)

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeMenu(state: ContextMenuState) -> NSMenu {
        ContextMenuFactory().makeMenu(
            state: state,
            actions: .init(
                onSwitchHost: {},
                onToggleCompactMode: {},
                onToggleStayOnTop: {},
                onOpenSettings: {},
                onQuit: {}
            )
        )
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
